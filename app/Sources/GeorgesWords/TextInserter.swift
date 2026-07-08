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

    /// The element the AX path most recently wrote into, kept so the
    /// correction learner can re-read the exact field later instead of
    /// trusting whatever happens to have focus then (backlog 2.5). Nil
    /// after a paste-fallback insertion — no element was proven there.
    private(set) var lastInsertionTarget: AXUIElement?

    @discardableResult
    func insert(_ text: String) -> Outcome {
        lastInsertionTarget = nil
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
        lastInsertionTarget = element
        return true
    }

    /// Replace the most recent insertion in place (command mode, 4.4;
    /// also the machinery Undo Last Insertion needs — backlog 5.5):
    /// select the last occurrence of `old` in the field and set the
    /// selection to `new` — the same select-and-replace door insert()
    /// uses. Prefers the tracked element from insertion time; falls back
    /// to the focused element. Returns false when the text can't be
    /// found or the field refuses (caller decides the fallback).
    func replaceLastInsertion(of old: String, with new: String, target: AXUIElement?) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let element = target ?? AXFocus.systemWideFocusedElement(),
              let value = fieldValue(of: element) else { return false }

        // AX text ranges count UTF-16 units — go through NSString.
        let nsValue = value as NSString
        let range = nsValue.range(of: old, options: .backwards)
        guard range.location != NSNotFound else { return false }

        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, new as CFString) == .success
        else { return false }

        // Same rule as insert(): never trust the claim — Chromium fields
        // report success without changing anything.
        guard let after = fieldValue(of: element), after != value else {
            DebugLog.log("Replace: app claimed success but the field never changed")
            return false
        }
        lastInsertionTarget = element
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
        let ourChangeCount = pasteboard.changeCount

        simulatePaste()

        // Give the focused app a moment to read the pasteboard, then restore
        // what the user had on it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // If the user copied something new during that window, theirs
            // wins — never overwrite a fresher clipboard.
            guard pasteboard.changeCount == ourChangeCount else { return }
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
        postKey(Self.vKeyCode, flags: .maskCommand)
    }

    // MARK: - Strategy 3: keyboard select-and-replace (Electron fallback)

    private static let leftArrowKeyCode: CGKeyCode = 123
    private static let deleteKeyCode: CGKeyCode = 51
    /// Above this, character-by-character selection is too slow to be
    /// worth it — fall back to the clipboard message instead.
    private static let maxKeyboardReplaceLength = 2000

    /// Replace the previous insertion by keyboard when the AX path can't
    /// (Electron/Chromium fields — Claude Desktop, VS Code, Slack…):
    /// select the last `length` characters (Shift+←) and paste `new` over
    /// them, or delete them when `new` is empty (Undo). Real keystrokes,
    /// so it works anywhere ⌘V does.
    ///
    /// It assumes the caret still sits at the END of that text — true in
    /// the normal flow (insert, then immediately command). We can't read
    /// Electron fields to verify, so this is optimistic like the paste
    /// path; the caller uses it only after the verifiable AX path fails.
    /// Returns false only when it declines up front (no permission, or an
    /// out-of-range length).
    @MainActor
    @discardableResult
    func replaceLastInsertionByKeyboard(previousLength length: Int, with new: String) async -> Bool {
        guard AXIsProcessTrusted(), (1...Self.maxKeyboardReplaceLength).contains(length) else { return false }

        // Select the inserted run: Shift+← once per character. Paced so a
        // busy target app doesn't drop events mid-selection.
        for _ in 0..<length {
            postKey(Self.leftArrowKeyCode, flags: .maskShift)
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        // Let the selection settle before replacing it.
        try? await Task.sleep(nanoseconds: 30_000_000)

        if new.isEmpty {
            postKey(Self.deleteKeyCode, flags: [])
        } else {
            insertViaPasteboard(new)
        }
        return true
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
