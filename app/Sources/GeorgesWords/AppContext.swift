import AppKit

/// The privacy-respecting version of commercial "context awareness":
/// we look at ONE thing — the bundle identifier of the frontmost app —
/// to pick a tone profile. No screenshots, no window titles, no URLs.
enum ToneProfile {
    case casual        // chat apps
    case professional  // email
    case technical     // editors & terminals
    case neutral

    var styleDescription: String {
        switch self {
        case .casual:
            return "a casual chat message — contractions and a relaxed tone are fine, keep it light"
        case .professional:
            return "professional writing — complete sentences, clear and courteous"
        case .technical:
            return "technical text — preserve code identifiers, file names, commands, and jargon exactly as spoken"
        case .neutral:
            return "clean, neutral prose"
        }
    }
}

struct AppContext {
    let bundleID: String

    static func current() -> AppContext {
        AppContext(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? "")
    }

    var tone: ToneProfile {
        let casual = ["slack", "discord", "messages", "whatsapp", "telegram", "signal"]
        let professional = ["mail", "outlook", "airmail", "spark", "superhuman"]
        let technical = ["xcode", "vscode", "code", "cursor", "terminal", "iterm", "warp", "jetbrains", "sublime", "zed", "ghostty"]

        if casual.contains(where: bundleID.contains) { return .casual }
        if technical.contains(where: bundleID.contains) { return .technical }
        if professional.contains(where: bundleID.contains) { return .professional }
        return .neutral
    }
}
