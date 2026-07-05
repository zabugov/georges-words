import CryptoKit
import Foundation

/// Where the managed engine is listening right now. Thread-safe because
/// LLMFormatter reads it from background tasks while ManagedOllama
/// (main-actor) sets it at server start.
enum EngineEndpoint {
    private static let lock = NSLock()
    private static var current = URL(string: "http://127.0.0.1:11499")!

    static var baseURL: URL {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); defer { lock.unlock() }; current = newValue }
    }
}

/// Backlog 7.7: a polish engine the app installs and runs itself, so a
/// fresh Mac never needs Terminal or a separate Ollama install.
///
/// This is THE polish engine (Zach's call, 2026-07-04): the app always
/// runs its own, regardless of any separately installed Ollama — one
/// identical code path on every machine.
/// - Fully isolated: binary + models live in Application Support/
///   GeorgesWords/PolishEngine, the server runs on a private port
///   (11499), and the child process dies with the app. Deleting the
///   folder is a complete uninstall.
@MainActor
final class ManagedOllama: ObservableObject {

    static let shared = ManagedOllama()

    /// The engine's address. The port is chosen fresh at every server
    /// start (see startServer): a fixed well-known port would let any
    /// local process squat it before we launch and impersonate the
    /// engine — receiving every transcript (ADR 0006).
    static var baseURL: URL { EngineEndpoint.baseURL }

    /// Pinned engine build (ADR 0006). Never `latest`: the app runs this
    /// binary on machines whose owners can't debug it, so upgrades are
    /// deliberate — bump the version and digest TOGETHER, verified against
    /// the release's sha256sum.txt.
    static let engineVersion = "v0.31.1"
    static let engineSHA256 = "0c4f92389fcc1f651c17282e2eaffd68c8d3d06e1f7b307604102ad0e09a10c9"
    static let engineDownloadURL = URL(string: "https://github.com/ollama/ollama/releases/download/\(engineVersion)/ollama-darwin.tgz")!

    enum Phase: Equatable {
        case off
        case downloadingEngine
        case startingEngine
        case downloadingModel(percent: Int?)
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .off

    private var serverProcess: Process?
    private var setupTask: Task<Void, Never>?
    private var crashRestarts = 0

    private let engineDir: URL
    private var binaryURL: URL { engineDir.appendingPathComponent("ollama") }
    private var modelsDir: URL { engineDir.appendingPathComponent("models") }

    private init() {
        engineDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeorgesWords/PolishEngine", isDirectory: true)
    }

    func setEnabled(_ enabled: Bool, model: String) {
        if enabled {
            ensureReady(model: model)
        } else {
            shutdown()
        }
    }

    func ensureReady(model: String) {
        setupTask?.cancel()
        setupTask = Task {
            await self.run(model: model)
            self.setupTask = nil
        }
    }

    /// Stop the engine. Instant off-switch.
    func shutdown() {
        setupTask?.cancel()
        setupTask = nil
        // Clear the reference before terminating so the supervision
        // handler recognizes this as intentional and doesn't restart.
        let process = serverProcess
        serverProcess = nil
        process?.terminate()
        phase = .off
    }

    private func run(model: String) async {
        do {
            if !FileManager.default.isExecutableFile(atPath: binaryURL.path) {
                phase = .downloadingEngine
                try await downloadEngine()
            }
            // Only trust a responding server if WE spawned it — an
            // impostor on our port must never receive transcripts.
            let ourServerAlive: Bool
            if serverProcess == nil {
                ourServerAlive = false
            } else {
                ourServerAlive = await Self.responds(Self.baseURL)
            }
            if !ourServerAlive {
                phase = .startingEngine
                try startServer()
                try await waitForServer()
            }
            if !(await hasModel(model)) {
                phase = .downloadingModel(percent: nil)
                try await pull(model: model)
            }
            guard !Task.isCancelled else { return }
            crashRestarts = 0
            phase = .ready
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Engine install

    private func downloadEngine() async throws {
        let (tempFile, response) = try await URLSession.shared.download(from: Self.engineDownloadURL)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EngineError(message: "Engine download failed — check the internet connection and try again.")
        }

        // Verify BEFORE anything gets extracted or executed: a tampered or
        // corrupted archive must never become code running on this Mac.
        let digest = try Self.sha256(of: tempFile)
        guard digest == Self.engineSHA256 else {
            throw EngineError(message: "Engine download didn't match its expected fingerprint — not installing it. Try again later.")
        }

        // Extract into a staging directory, then move into place — a
        // half-unpacked engineDir never looks installed.
        try FileManager.default.createDirectory(at: engineDir, withIntermediateDirectories: true)
        let stage = engineDir.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }

        let status = try await Self.runProcess("/usr/bin/tar", ["-xzf", tempFile.path, "-C", stage.path])
        guard status == 0,
              FileManager.default.fileExists(atPath: stage.appendingPathComponent("ollama").path)
        else {
            throw EngineError(message: "Engine archive could not be unpacked.")
        }
        for item in try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            let destination = engineDir.appendingPathComponent(item.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: item, to: destination)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
    }

    /// Streaming SHA-256 so the ~120 MB archive never loads whole.
    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Server lifecycle

    private func startServer() throws {
        // Replace, never orphan: a hung previous child would otherwise
        // linger while we start a fresh one.
        if let old = serverProcess {
            old.terminationHandler = nil
            serverProcess = nil
            old.terminate()
        }

        let port = Self.pickFreePort() ?? 11499
        EngineEndpoint.baseURL = URL(string: "http://127.0.0.1:\(port)")!

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:\(port)"
        environment["OLLAMA_MODELS"] = modelsDir.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Supervision: the engine is invisible (no menu-bar icon, no Dock
        // entry), so nobody can quit it by accident — and if it dies
        // anyway, bring it back rather than silently losing polish.
        process.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in
                guard let self, self.serverProcess === terminated else { return }
                self.serverProcess = nil
                guard AppSettings.shared.llmEnabled else {
                    self.phase = .off
                    return
                }
                guard self.crashRestarts < 3 else {
                    self.phase = .failed("The engine keeps stopping — try Recheck, or delete Application Support/GeorgesWords/PolishEngine and toggle the setting again.")
                    return
                }
                self.crashRestarts += 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.ensureReady(model: AppSettings.shared.effectiveLLMModel)
            }
        }
        try process.run()
        serverProcess = process
    }

    private func waitForServer() async throws {
        for _ in 0..<60 {
            if Task.isCancelled { throw CancellationError() }
            if await Self.responds(Self.baseURL) { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw EngineError(message: "The polish engine didn't start.")
    }

    // MARK: - Model pull

    private func hasModel(_ model: String) async -> Bool {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Tags.self, from: data)
        else { return false }
        return decoded.models.contains { $0.name == model }
    }

    private func pull(model: String) async throws {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        request.timeoutInterval = 3600

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EngineError(message: "Model download failed to start.")
        }
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if let message = Self.pullError(fromLine: line) {
                throw EngineError(message: "Model download failed: \(message)")
            }
            if let percent = Self.pullPercent(fromLine: line) {
                phase = .downloadingModel(percent: percent)
            }
        }
    }

    /// Progress from one NDJSON pull-status line, when it carries totals.
    nonisolated static func pullPercent(fromLine line: String) -> Int? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let total = object["total"] as? Double, total > 0,
              let completed = object["completed"] as? Double
        else { return nil }
        return max(0, min(100, Int(completed / total * 100)))
    }

    nonisolated static func pullError(fromLine line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["error"] as? String
    }

    // MARK: - Helpers

    /// Ask the kernel for a free localhost port: bind port 0, read back
    /// the assignment, release it for the child to claim moments later.
    nonisolated private static func pickFreePort() -> UInt16? {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                getsockname(sock, pointer, &length)
            }
        }
        guard named == 0 else { return nil }
        return UInt16(bigEndian: assigned.sin_port)
    }

    nonisolated private static func responds(_ base: URL) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("api/version"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    nonisolated private static func runProcess(_ executable: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private struct EngineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
