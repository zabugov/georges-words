import AppKit
import ApplicationServices

/// Inserts text at the cursor of whatever app has focus, using the same
/// chain the polished commercial dictation apps use:
///
///   1. Direct Accessibility-API insertion into the focused element
///      (replaces the current selection; inserts at the caret when the
///      selection is empty). Cleanest: no clipboard involvement at all.
///   2. Fallback: clipboard + simulated ⌘V, restoring the user's previous
///      clipboard afterwards.
final class TextInserter {

    enum Outcome {
        /// Text was inserted into the focused app.
        case inserted
        /// No Accessibility permission — text was left on the clipboard
        /// for a manual paste instead.
        case copiedToClipboard
    }

    private static let vKeyCode: CGKeyCode = 9

    @discardableResult
    func insert(_ text: String) -> Outcome {
        guard AXIsProcessTrusted() else {
            // Without Accessibility we can neither use the AX API nor
            // simulate ⌘V — leave the text on the clipboard so the user can
            // paste manually. This happens after every rebuild while we're
            // ad-hoc signed: macOS silently invalidates the stale grant.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            NSLog("Accessibility permission missing — transcript left on clipboard.")
            return .copiedToClipboard
        }

        if insertViaAccessibility(text) { return .inserted }
        insertViaPasteboard(text)
        return .inserted
    }

    // MARK: - Strategy 1: Accessibility API

    private func insertViaAccessibility(_ text: String) -> Bool {
        // Writes use only the conservative focus lookup — see
        // AXFocus.systemWideFocusedElement for why the Electron wake is
        // insertion-unsafe. Failure here means the ⌘V path runs instead.
        guard let element = AXFocus.systemWideFocusedElement() else { return false }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue
        else { return false }

        // Chromium/Electron fields report success for the set below without
        // inserting anything — and once their AX tree has been woken (which
        // outlives our own restarts), they pass the focus and settable
        // checks too. Never trust the claim: require the field's value to
        // be readable, and confirm it actually changed. Anything short of
        // proof falls through to the ⌘V path, which works everywhere.
        guard let before = fieldValue(of: element) else {
            DebugLog.log("Insert: field value unreadable — using paste")
            return false
        }
        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else { return false }

        guard fieldValue(of: element) != before else {
            DebugLog.log("Insert: app claimed success but the field never changed — using paste")
            return false
        }
        return true
    }

    private func fieldValue(of element: AXUIElement) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &ref
        ) == .success else { return nil }
        return ref as? String
    }

    // MARK: - Strategy 2: clipboard + simulated ⌘V

    private func insertViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Snapshot ALL current contents — rich text, images, file
        // references — not just the plain-string representation.
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy[type] = data
                }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        // Give the focused app a moment to read the pasteboard, then restore
        // what the user had on it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            guard !saved.isEmpty else { return }
            let items = saved.map { entry -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entry {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.writeObjects(items)
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
