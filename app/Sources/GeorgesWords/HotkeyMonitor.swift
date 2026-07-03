import AppKit

/// Watches a chosen modifier key globally: press starts dictation, release
/// stops it. Requires the Accessibility permission.
///
/// For Fn, macOS may also assign the key to emoji/dictation — set
/// System Settings → Keyboard → "Press 🌐 key" to "Do Nothing".
final class HotkeyMonitor {

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyIsDown = false

    init(hotkey: HotkeyChoice, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        let keyCode = hotkey.keyCode
        let flag = hotkey.flag

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == keyCode else { return }
            let isDown = event.modifierFlags.contains(flag)
            if isDown && !self.keyIsDown {
                self.keyIsDown = true
                onPress()
            } else if !isDown && self.keyIsDown {
                self.keyIsDown = false
                onRelease()
            }
        }

        // Fires when other apps have focus (the common case for dictation).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        // Fires when our own UI has focus.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
