import AppKit
import ApplicationServices

/// Inserts text at the cursor of whatever app has focus.
///
/// M1 approach: put the text on the pasteboard and simulate ⌘V, then restore
/// the user's previous clipboard. (M2 will add direct Accessibility-API
/// insertion with this as the fallback, matching commercial Flow's chain.)
final class TextInserter {

    private static let vKeyCode: CGKeyCode = 9

    func insert(_ text: String) {
        let pasteboard = NSPasteboard.general

        guard AXIsProcessTrusted() else {
            // Without Accessibility we can't simulate ⌘V — leave the text on
            // the clipboard so the user can paste manually.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            NSLog("Accessibility permission missing — transcript left on clipboard.")
            return
        }

        let savedClipboard = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        // Give the focused app a moment to read the pasteboard, then restore
        // what the user had on it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let savedClipboard {
                pasteboard.setString(savedClipboard, forType: .string)
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
