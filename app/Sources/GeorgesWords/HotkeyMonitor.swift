import AppKit

/// Watches the Fn key globally: press starts dictation, release stops it.
///
/// Requires the Accessibility permission. Note: macOS may also assign the
/// Fn/🌐 key to emoji/dictation — set System Settings → Keyboard →
/// "Press 🌐 key" to "Do Nothing" for the cleanest experience.
final class HotkeyMonitor {

    private static let fnKeyCode: UInt16 = 63

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnIsDown = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == Self.fnKeyCode else { return }
            let isDown = event.modifierFlags.contains(.function)
            if isDown && !self.fnIsDown {
                self.fnIsDown = true
                onPress()
            } else if !isDown && self.fnIsDown {
                self.fnIsDown = false
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
