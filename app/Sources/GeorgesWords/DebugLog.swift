import Foundation

/// Appends diagnostic lines to Application Support/GeorgesWords/debug.log.
/// The unified system log filters third-party app messages too aggressively
/// to rely on (blank `log show` output while debugging follow-ups,
/// 2026-07-05); a plain file can't hide. Keep transcript text out of here —
/// stages, lengths, and bundle IDs only.
enum DebugLog {

    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeorgesWords", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func log(_ message: String) {
        NSLog("%@", message)
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "[\(stamp)] \(message)\n".data(using: .utf8) else { return }

        // Fresh file once it grows past ~1 MB — this is a diagnostic
        // scratchpad, not an archive.
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
           size > 1_000_000 {
            try? FileManager.default.removeItem(at: url)
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
