import AppKit
import ApplicationServices

/// Troubleshooting's insertion compatibility test (backlog 6.6): probe
/// the currently focused field exactly the way TextInserter decides —
/// but read-only, without writing a character — and report which
/// insertion path a dictation would take there.
enum InsertionTester {

    struct Verdict {
        /// Short answer ("Direct insertion", "Paste fallback (⌘V)"…).
        let title: String
        /// One-sentence explanation for the user.
        let detail: String
        /// False when dictations would land on the clipboard instead.
        let good: Bool
    }

    static func testFocusedField() -> Verdict {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "the frontmost app"

        guard AXIsProcessTrusted() else {
            return Verdict(
                title: "No Accessibility permission",
                detail: "Dictations will be copied to the clipboard everywhere. Re-enable GeorgesWords in System Settings → Privacy & Security → Accessibility.",
                good: false
            )
        }

        // Mirror TextInserter.insert: the conservative door decides.
        if let element = AXFocus.systemWideFocusedElement() {
            var settable = DarwinBoolean(false)
            let accepts = AXUIElementIsAttributeSettable(
                element, kAXSelectedTextAttribute as CFString, &settable
            ) == .success && settable.boolValue

            var valueRef: AnyObject?
            let readable = AXUIElementCopyAttributeValue(
                element, kAXValueAttribute as CFString, &valueRef
            ) == .success && valueRef is String

            DebugLog.log("Insertion test (\(appName)): settable=\(accepts) readable=\(readable)")
            if accepts && readable {
                return Verdict(
                    title: "Direct insertion",
                    detail: "\(appName)'s field supports the cleanest path — text appears at the cursor with the clipboard untouched, and the field can be re-read for correction learning.",
                    good: true
                )
            }
            return Verdict(
                title: "Paste fallback (⌘V)",
                detail: accepts
                    ? "\(appName)'s field accepts text but its content can't be verified, so the app pastes to be safe. Your clipboard is restored afterwards."
                    : "\(appName)'s field doesn't accept direct edits — the app pastes instead. Your clipboard is restored afterwards.",
                good: true
            )
        }

        // The permissive read path (with the Electron wake) tells us
        // whether a field exists at all, even though writes never use it.
        if AXFocus.focusedElement(logContext: "Insertion test") != nil {
            DebugLog.log("Insertion test (\(appName)): field visible only after wake")
            return Verdict(
                title: "Paste fallback (⌘V)",
                detail: "\(appName) only reveals its fields after a nudge; dictations use paste there, which works. Correction learning may not see your edits in this app.",
                good: true
            )
        }

        DebugLog.log("Insertion test (\(appName)): no focused element by any route")
        return Verdict(
            title: "Paste, unverified",
            detail: "No text field is visible to Accessibility in \(appName). The app will still try ⌘V paste — if nothing appears when you dictate there, use Paste Last Transcript from the menu bar.",
            good: false
        )
    }
}
