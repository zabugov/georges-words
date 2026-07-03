import AppKit

/// Audio cues for recording start/stop, using the built-in macOS system
/// sounds (found in /System/Library/Sounds — Tink, Pop, Morse, Ping, …).
enum SoundFeedback {

    /// Played when the hotkey is pressed and recording begins.
    static func recordingStarted() {
        play("Tink")
    }

    /// Played when the hotkey is released and recording ends.
    static func recordingStopped() {
        play("Pop")
    }

    private static func play(_ name: String) {
        guard AppSettings.shared.soundsEnabled else { return }
        guard let sound = NSSound(named: name) else { return }
        sound.volume = 0.5
        sound.play()
    }
}
