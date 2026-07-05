import AppKit
import ApplicationServices

/// Finds the UI element with keyboard focus. Surprisingly app-dependent:
/// the system-wide query works almost everywhere, but Chromium/Electron
/// apps keep their accessibility tree dormant until a client pokes it, so
/// the system-wide query (and everything built on it — selection reads,
/// AX insertion, the correction learner's field re-read) silently fails
/// there. This helper tries every known door and logs which one opened.
enum AXFocus {

    /// The conservative door only: the system-wide query, no Electron wake.
    /// Use this for WRITES (text insertion). Chromium-based apps woken via
    /// AXManualAccessibility will report a successful kAXSelectedText set
    /// without actually inserting anything — the caller then skips its paste
    /// fallback and the dictation vanishes (seen in Claude Desktop,
    /// 2026-07-05). If the system-wide query fails, let insertion fall back
    /// to ⌘V, which is proven everywhere.
    static func systemWideFocusedElement() -> AXUIElement? {
        copyFocused(from: AXUIElementCreateSystemWide())
    }

    /// Every door, including the Electron wake. Safe for READS (selection,
    /// field re-reads) — a wrong answer can't lose user text.
    static func focusedElement(logContext: String) -> AXUIElement? {
        if let element = copyFocused(from: AXUIElementCreateSystemWide()) {
            return element
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            DebugLog.log("\(logContext): no frontmost application")
            return nil
        }
        let appID = app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let element = copyFocused(from: appElement) {
            DebugLog.log("\(logContext): focused element via direct app query (\(appID))")
            return element
        }

        // Chromium/Electron: the AX tree sleeps until this attribute is
        // set, then needs a beat to build itself.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        usleep(80_000)
        if let element = copyFocused(from: appElement) {
            DebugLog.log("\(logContext): focused element after AXManualAccessibility wake (\(appID))")
            return element
        }

        DebugLog.log("\(logContext): no focused element by any route (frontmost: \(appID))")
        return nil
    }

    private static func copyFocused(from parent: AXUIElement) -> AXUIElement? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(
            parent,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        ) == .success,
            let ref,
            CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return (ref as! AXUIElement)
    }
}
