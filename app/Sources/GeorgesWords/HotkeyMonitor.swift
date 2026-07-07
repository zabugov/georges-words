import AppKit

/// Any single physical key usable as a hold-to-talk hotkey: one of the
/// built-in presets, or whatever the user captured in Settings (5.4).
/// Two watching styles: modifier-type keys arrive via flagsChanged with a
/// flag set; everything else via keyDown/keyUp.
struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt16
    /// Raw NSEvent.ModifierFlags for modifier-type keys; nil = normal key.
    var modifierFlagRawValue: UInt?
    var displayName: String

    var modifierFlag: NSEvent.ModifierFlags? {
        modifierFlagRawValue.map { NSEvent.ModifierFlags(rawValue: $0) }
    }

    /// The same physical key is the same hotkey, whatever it's labeled.
    static func == (lhs: HotkeySpec, rhs: HotkeySpec) -> Bool {
        lhs.keyCode == rhs.keyCode
    }

    static let fn = HotkeySpec(keyCode: 63, modifierFlagRawValue: NSEvent.ModifierFlags.function.rawValue, displayName: "Fn (🌐)")
    static let rightCommand = HotkeySpec(keyCode: 54, modifierFlagRawValue: NSEvent.ModifierFlags.command.rawValue, displayName: "Right ⌘")
    static let rightOption = HotkeySpec(keyCode: 61, modifierFlagRawValue: NSEvent.ModifierFlags.option.rawValue, displayName: "Right ⌥")
    static let rightControl = HotkeySpec(keyCode: 62, modifierFlagRawValue: NSEvent.ModifierFlags.control.rawValue, displayName: "Right ⌃")

    /// Pre-5.4 settings stored a three-choice enum's raw value.
    static func legacy(_ raw: String?) -> HotkeySpec? {
        switch raw {
        case "fn": return .fn
        case "rightCommand": return .rightCommand
        case "rightOption": return .rightOption
        default: return nil
        }
    }
}

/// Watches the chosen key globally: press starts dictation, release stops
/// it. Requires the Accessibility permission.
///
/// For Fn, macOS may also assign the key to emoji/dictation — set
/// System Settings → Keyboard → "Press 🌐 key" to "Do Nothing".
final class HotkeyMonitor {

    private var monitors: [Any] = []
    private var keyIsDown = false

    init(hotkey: HotkeySpec, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        let keyCode = hotkey.keyCode

        if let flag = hotkey.modifierFlag {
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
            add(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler))
            add(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                handler(event)
                return event
            })
        } else {
            // Normal key: keyDown repeats while held — ignore autorepeats.
            let down: (NSEvent) -> Void = { [weak self] event in
                guard let self, event.keyCode == keyCode, !event.isARepeat else { return }
                if !self.keyIsDown {
                    self.keyIsDown = true
                    onPress()
                }
            }
            let up: (NSEvent) -> Void = { [weak self] event in
                guard let self, event.keyCode == keyCode else { return }
                if self.keyIsDown {
                    self.keyIsDown = false
                    onRelease()
                }
            }
            add(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { down($0) })
            add(NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { up($0) })
            add(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                down(event)
                return event
            })
            add(NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
                up(event)
                return event
            })
        }
    }

    /// Forget a half-seen press. Sleep, secure input, and app switches can
    /// eat the release event, leaving `keyIsDown` stuck and the next real
    /// press ignored.
    func reset() {
        keyIsDown = false
    }

    private func add(_ monitor: Any?) {
        if let monitor { monitors.append(monitor) }
    }

    deinit {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// Settings-side key capture: click "Change…", press any key, and the
/// next keystroke (or modifier press) becomes the hotkey. Esc cancels.
final class HotkeyCapture: ObservableObject {

    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var onCapture: ((HotkeySpec) -> Void)?

    /// keyCode → (flag it sets, human name). Caps Lock is excluded — it
    /// toggles rather than holds.
    private static let modifierKeys: [UInt16: (flag: NSEvent.ModifierFlags, name: String)] = [
        63: (.function, "Fn (🌐)"),
        55: (.command, "Left ⌘"), 54: (.command, "Right ⌘"),
        58: (.option, "Left ⌥"), 61: (.option, "Right ⌥"),
        56: (.shift, "Left ⇧"), 60: (.shift, "Right ⇧"),
        59: (.control, "Left ⌃"), 62: (.control, "Right ⌃"),
    ]

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 48: "Tab", 36: "Return", 51: "Delete", 117: "Forward Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    func begin(_ handler: @escaping (HotkeySpec) -> Void) {
        cancel()
        onCapture = handler
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }

            if event.type == .keyDown {
                if event.keyCode == 53 { // Esc cancels (it's the cancel key elsewhere too)
                    self.cancel()
                    return nil
                }
                let name = Self.specialKeys[event.keyCode]
                    ?? event.charactersIgnoringModifiers.flatMap { $0.isEmpty ? nil : $0.uppercased() }
                    ?? "Key \(event.keyCode)"
                self.finish(HotkeySpec(keyCode: event.keyCode, modifierFlagRawValue: nil, displayName: name))
                return nil
            }

            // flagsChanged: capture on the press (flag present), not release.
            if let entry = Self.modifierKeys[event.keyCode], event.modifierFlags.contains(entry.flag) {
                self.finish(HotkeySpec(keyCode: event.keyCode, modifierFlagRawValue: entry.flag.rawValue, displayName: entry.name))
                return nil
            }
            return event
        }
    }

    private func finish(_ spec: HotkeySpec) {
        onCapture?(spec)
        cancel()
    }

    func cancel() {
        isRecording = false
        onCapture = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
