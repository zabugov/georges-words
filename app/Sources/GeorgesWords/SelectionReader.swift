import AppKit
import ApplicationServices

/// Reads the currently selected text from the frontmost app — the input to
/// command mode. Tries the Accessibility API first, then falls back to
/// simulating ⌘C (restoring the clipboard afterwards).
enum SelectionReader {

    private static let cKeyCode: CGKeyCode = 8

    static func read() -> String? {
        if let selection = readViaAccessibility(), !selection.isEmpty {
            return selection
        }
        return readViaCopy()
    }

    private static func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
            let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedRef as! AXUIElement
        var selectedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success else { return nil }
        return selectedRef as? String
    }

    /// Re-selects the text this app most recently inserted — the follow-up
    /// path for command mode (4.3). Right after an insertion the caret sits
    /// at its end, so the inserted text occupies the `text.utf16.count`
    /// units before the caret. Selects that range, then verifies the
    /// selection really is the expected text; on any mismatch (the user
    /// moved the caret, sent the message, edited around it) the caret is
    /// restored and this reports failure.
    static func reselect(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
            let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return false }
        let element = focusedRef as! AXUIElement

        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
            let rangeRef,
            CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return false }

        var caret = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &caret),
              caret.length == 0
        else { return false }

        let length = text.utf16.count
        guard length > 0, caret.location >= length else { return false }

        var target = CFRange(location: caret.location - length, length: length)
        guard let targetValue = AXValueCreate(.cfRange, &target),
              AXUIElementSetAttributeValue(
                  element,
                  kAXSelectedTextRangeAttribute as CFString,
                  targetValue
              ) == .success
        else { return false }

        var selectedRef: AnyObject?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success,
            let selected = selectedRef as? String,
            selected == text {
            return true
        }

        // Wrong text under the range — put the caret back where it was.
        var original = caret
        if let originalValue = AXValueCreate(.cfRange, &original) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                originalValue
            )
        }
        return false
    }

    private static func readViaCopy() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let changeCountBefore = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Give the frontmost app a beat to service the copy.
        usleep(150_000)

        var copied: String?
        if pasteboard.changeCount != changeCountBefore {
            copied = pasteboard.string(forType: .string)
        }

        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }

        return (copied?.isEmpty == false) ? copied : nil
    }
}
