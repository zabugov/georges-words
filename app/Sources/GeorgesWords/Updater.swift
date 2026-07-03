import AppKit

/// One-click self-update: git pull → rebuild → relaunch.
///
/// Works because the app runs out of its own source checkout
/// (<repo>/app/build/GeorgesWords.app), so the repository root can be
/// derived from the bundle path. With the stable signing identity from
/// setup-signing.sh, the relaunched build keeps its permissions.
final class Updater {

    enum UpdateResult {
        case upToDate
        case updated
        case failed(String)
    }

    private(set) var isUpdating = false

    /// Progress text for the menu bar (nil when finished).
    var onProgress: ((String?) -> Void)?

    /// <repo>/app/build/GeorgesWords.app → <repo>
    private var repoRoot: URL? {
        let candidate = Bundle.main.bundleURL
            .deletingLastPathComponent() // build/
            .deletingLastPathComponent() // app/
            .deletingLastPathComponent() // repo root
        let fm = FileManager.default
        guard fm.fileExists(atPath: candidate.appendingPathComponent(".git").path),
              fm.fileExists(atPath: candidate.appendingPathComponent("app/build.sh").path)
        else { return nil }
        return candidate
    }

    func checkAndInstall() {
        guard !isUpdating else { return }
        guard let repo = repoRoot else {
            Self.alert(
                "Can’t find the source checkout",
                "Self-update needs the app to run from its build folder inside the georges-words repository (app/build/GeorgesWords.app). Rebuild with ./app/build.sh and launch that copy."
            )
            return
        }

        isUpdating = true
        let appURL = Bundle.main.bundleURL
        Task.detached { [weak self] in
            let report: (String?) -> Void = { text in
                DispatchQueue.main.async { self?.onProgress?(text) }
            }
            let result = Self.performUpdate(repo: repo, progress: report)
            DispatchQueue.main.async {
                self?.isUpdating = false
                self?.onProgress?(nil)
                switch result {
                case .upToDate:
                    Self.alert("You’re up to date", "No new changes on GitHub.")
                case .failed(let message):
                    Self.alert("Update failed", message)
                case .updated:
                    Self.relaunch(appURL: appURL)
                }
            }
        }
    }

    // MARK: - The update pipeline

    private static func performUpdate(repo: URL, progress: (String?) -> Void) -> UpdateResult {
        progress("Update: pulling latest…")
        let pull = run("/usr/bin/git", ["pull", "--ff-only"], cwd: repo)
        guard pull.status == 0 else {
            return .failed("git pull failed:\n\(tail(pull.output))")
        }
        if pull.output.contains("Already up to date") {
            return .upToDate
        }

        progress("Update: compiling (can take a few minutes)…")
        let build = run(
            "/bin/bash", ["app/build.sh"], cwd: repo,
            extraEnvironment: ["GW_SKIP_OPEN": "1"]
        )
        guard build.status == 0 else {
            // build.sh compiles before it replaces the bundle, so a failed
            // build leaves the currently-running version intact on disk.
            return .failed("Build failed — still running the previous version.\n\n\(tail(build.output))")
        }
        return .updated
    }

    private static func relaunch(appURL: URL) {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = ["-c", "sleep 0.7; /usr/bin/open \"\(appURL.path)\""]
        try? helper.run()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL,
        extraEnvironment: [String: String] = [:]
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        // GUI apps get a minimal PATH; the toolchain lives in /usr/bin.
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        for (key, value) in extraEnvironment { environment[key] = value }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (127, error.localizedDescription)
        }
        // Read before waiting so a chatty build can't fill and deadlock the pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func tail(_ output: String, lines: Int = 15) -> String {
        output
            .split(separator: "\n")
            .suffix(lines)
            .joined(separator: "\n")
    }

    private static func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
