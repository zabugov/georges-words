import AppKit

/// Audio cues for recording start/stop, using the built-in macOS system
/// sounds (found in /System/Library/Sounds — Tink, Pop, Morse, Ping, …).
enum SoundFeedback {

    /// NSSound playback is asynchronous; without a strong reference the
    /// sound can be deallocated mid-play and never be heard.
    private static var activeSound: NSSound?

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

        // Prefer the named lookup; fall back to the file on disk in case
        // the name isn't registered on this macOS version.
        let sound = NSSound(named: name)
            ?? NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
        guard let sound else {
            NSLog("SoundFeedback: system sound '\(name)' not found")
            return
        }

        sound.volume = 0.7
        activeSound = sound

        // play() returns false if this (cached) instance is already playing
        // — stop and retry so rapid press/release still clicks.
        if !sound.play() {
            sound.stop()
            if !sound.play() {
                NSLog("SoundFeedback: failed to play '\(name)'")
            }
        }
    }
}
