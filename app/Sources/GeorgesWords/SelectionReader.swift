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
