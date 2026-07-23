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

    /// True when the app runs out of its git checkout (the developer's
    /// machine). DMG installs return false and update via Sparkle instead
    /// (ADR 0007).
    var runsFromSourceCheckout: Bool { repoRoot != nil }

    /// Progress text for the menu bar (nil when finished).
    var onProgress: ((String?) -> Void)?

    /// Short user-facing outcome notice ("You're up to date", …).
    var onNotice: ((String) -> Void)?

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
                    self?.onNotice?("You’re up to date — no new changes")
                case .failed(let message):
                    self?.onNotice?("Update failed")
                    Self.alert("Update failed", message + "\n\nFull log: ~/Library/Logs/GeorgesWords/update.log")
                case .updated:
                    // Greet the user from the new build so success is visible.
                    UserDefaults.standard.set(true, forKey: "JustUpdated")
                    Self.relaunch(appURL: appURL)
                }
            }
        }
    }

    // MARK: - The update pipeline

    private static func performUpdate(repo: URL, progress: (String?) -> Void) -> UpdateResult {
        log("=== Update check started ===")
        progress("Checking for updates…")

        // An unexplained spinner reads as broken — say something when
        // the check is slower than it ever should be (2026-07-23).
        let slowNotice = DispatchWorkItem {
            progress("Still checking — the network or iCloud may be slow…")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: slowNotice)

        // Compare commits rather than parsing `git pull` prose (which varies
        // by git version and locale).
        let before = run("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repo, timeout: 30)
        let pull = run("/usr/bin/git", ["pull", "--ff-only"], cwd: repo, timeout: 120)
        slowNotice.cancel()
        log("git pull (status \(pull.status)):\n\(pull.output)")
        guard pull.status == 0 else {
            return .failed("git pull failed:\n\(tail(pull.output))")
        }
        let after = run("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repo, timeout: 30)
        let head = after.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // "Up to date" means the INSTALLED APP was built from HEAD — not
        // merely that the pull found nothing. Comparing only before/after
        // meant a failed build (or a manual reset) was never retried: HEAD
        // hadn't moved, so the updater shrugged while running stale code.
        let builtCommit = UserDefaults.standard.string(forKey: "BuiltCommit")
        let upToDate: Bool
        if let builtCommit {
            upToDate = head == builtCommit
        } else {
            // Legacy state (no record yet): fall back to the old check
            // once, and start keeping the record from here.
            upToDate = before.output == after.output
        }
        if upToDate {
            if builtCommit == nil { UserDefaults.standard.set(head, forKey: "BuiltCommit") }
            log("Already up to date (built commit \(head.prefix(7))).")
            return .upToDate
        }

        progress("Update found — compiling (a few minutes)…")
        let build = run(
            "/bin/bash", ["app/build.sh"], cwd: repo,
            extraEnvironment: ["GW_SKIP_OPEN": "1"],
            timeout: 900
        )
        log("build.sh (status \(build.status)):\n\(build.output)")
        guard build.status == 0 else {
            // build.sh compiles before it replaces the bundle, so a failed
            // build leaves the currently-running version intact on disk —
            // and BuiltCommit keeps its old value, so the next check
            // retries this build instead of claiming "up to date".
            return .failed("Build failed — still running the previous version.\n\n\(tail(build.output))")
        }
        UserDefaults.standard.set(head, forKey: "BuiltCommit")
        log("Update succeeded (built \(head.prefix(7))); relaunching.")
        return .updated
    }

    /// Append to ~/Library/Logs/GeorgesWords/update.log for diagnosis.
    /// Bounded twice over (a 436 MB log was found in the wild,
    /// 2026-07-23): each entry is capped, and the file rotates down to
    /// its recent tail once it exceeds a few MB.
    private static func log(_ message: String) {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/GeorgesWords", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("update.log")

        var bounded = message
        if bounded.count > 20_000 {
            bounded = "[entry truncated from \(bounded.count) chars]\n…" + bounded.suffix(20_000)
        }
        let line = "[\(Date().formatted(date: .abbreviated, time: .standard))] \(bounded)\n"

        // Rotate BEFORE appending: keep the newest ~200 KB and start
        // over. Tail is read via seek — never the whole file.
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
           size > 2_000_000,
           let handle = try? FileHandle(forReadingFrom: url) {
            try? handle.seek(toOffset: UInt64(max(0, size - 200_000)))
            let tail = (try? handle.readToEnd()) ?? Data()
            try? handle.close()
            let header = Data("[log rotated — was \(size / 1_000_000) MB]\n".utf8)
            try? (header + tail).write(to: url)
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
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
        extraEnvironment: [String: String] = [:],
        timeout: TimeInterval
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        // GUI apps get a minimal PATH; the toolchain lives in /usr/bin.
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        // Never let git sit waiting for credentials on stdin — fail instead.
        environment["GIT_TERMINAL_PROMPT"] = "0"
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

        // Read on a separate thread, NEVER on this one: a step can hang
        // unkillably (git in a disk wait while iCloud re-downloads an
        // evicted repo file), and blocking here meant an endless spinner
        // the user could only escape by restarting the Mac (on-device,
        // 2026-07-23). This thread only polls and enforces the deadline.
        let outputBox = NSLock()
        var outputData = Data()
        let readDone = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            // Chunked with a cap: a runaway child must not balloon
            // memory (or, downstream, the log) — keep the newest MB,
            // which is the part that explains a failure.
            var data = Data()
            let reader = pipe.fileHandleForReading
            while let chunk = try? reader.read(upToCount: 65_536), !chunk.isEmpty {
                data.append(chunk)
                if data.count > 2_000_000 {
                    data = data.suffix(1_000_000)
                }
            }
            outputBox.lock()
            outputData = data
            outputBox.unlock()
            readDone.signal()
        }

        var timedOut = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(100_000)
        }
        if process.isRunning {
            timedOut = true
            process.terminate()
            usleep(500_000)
            // SIGTERM can be ignored; escalate. (A process stuck in a
            // disk wait survives even this — handled below.)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        // Unblock the reader even when descendants — or an unkillable
        // parent — still hold the pipe's write end: closing OUR end
        // forces readDataToEndOfFile to return.
        if readDone.wait(timeout: .now() + 3) == .timedOut {
            try? pipe.fileHandleForReading.close()
            _ = readDone.wait(timeout: .now() + 2)
        }
        if !timedOut {
            process.waitUntilExit()
        }

        outputBox.lock()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        outputBox.unlock()
        if timedOut {
            return (1, output + "\n[timed out after \(Int(timeout)) s — if this repeats, iCloud may be re-downloading the repo folder: open it in Finder, let any cloud icons finish, then try again]")
        }
        return (process.terminationStatus, output)
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
