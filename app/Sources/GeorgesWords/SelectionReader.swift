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
    /// path for command mode (4.3). Two strategies:
    ///
    ///   1. Read the field's full value and select the last occurrence of
    ///      the remembered text — works no matter where the caret has
    ///      wandered, as long as the text is still in the field.
    ///   2. If the value can't be read (Electron apps often refuse), fall
    ///      back to caret arithmetic: the caret usually still sits right
    ///      after the insertion, so select the units just before it.
    ///
    /// Either way the selection is verified against the expected text
    /// before reporting success; on mismatch the original selection is
    /// restored. Failures log the stage to Console for diagnosis.
    static func reselect(_ text: String) -> Bool {
        let length = text.utf16.count
        guard length > 0 else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
            let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else {
            NSLog("Follow-up reselect: no focused element")
            return false
        }
        let element = focusedRef as! AXUIElement

        // Remember the current selection so a failed attempt is invisible.
        let original = selectedRange(of: element)

        // Strategy 1: find the text in the field's value.
        if let value = fieldValue(of: element) {
            let found = (value as NSString).range(of: text, options: .backwards)
            if found.location != NSNotFound {
                if select(CFRange(location: found.location, length: found.length),
                          in: element, expecting: text, restoreTo: original) {
                    return true
                }
            } else {
                NSLog("Follow-up reselect: inserted text no longer in the field")
                return false
            }
        }

        // Strategy 2: the units just before the caret.
        guard let caret = original, caret.length == 0 else {
            NSLog("Follow-up reselect: field value unreadable and no collapsed caret")
            return false
        }
        guard caret.location >= length else {
            NSLog("Follow-up reselect: caret too close to the start")
            return false
        }
        return select(CFRange(location: caret.location - length, length: length),
                      in: element, expecting: text, restoreTo: original)
    }

    private static func fieldValue(of element: AXUIElement) -> String? {
        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success else { return nil }
        return valueRef as? String
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
            let rangeRef,
            CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Sets the selection to `range`, verifies it reads back as `expected`,
    /// and restores the prior selection on any mismatch.
    private static func select(
        _ range: CFRange,
        in element: AXUIElement,
        expecting expected: String,
        restoreTo original: CFRange?
    ) -> Bool {
        var target = range
        guard let targetValue = AXValueCreate(.cfRange, &target),
              AXUIElementSetAttributeValue(
                  element,
                  kAXSelectedTextRangeAttribute as CFString,
                  targetValue
              ) == .success
        else {
            NSLog("Follow-up reselect: app rejected setting the selection range")
            return false
        }

        var selectedRef: AnyObject?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success,
            let selected = selectedRef as? String,
            selected == expected {
            return true
        }

        NSLog("Follow-up reselect: selection read back as different text")
        if var restore = original,
           let restoreValue = AXValueCreate(.cfRange, &restore) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                restoreValue
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
