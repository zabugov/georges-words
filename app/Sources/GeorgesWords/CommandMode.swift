import AppKit
import ApplicationServices

/// Voice edit commands (backlog 4.4): hold the command hotkey, say how
/// the last dictation should change — "make it more formal", "remove
/// the word actually", "translate to French" — release, and the local
/// LLM applies the instruction, replacing the text right where it was
/// inserted.
///
/// Deliberately its OWN small state machine, fully separate from
/// dictation's hold/latch logic in AppDelegate (the old command mode
/// died of sharing that state machine). Commands are hold-only — no
/// quick-tap latch, no live preview — and they never insert at the
/// caret; they rewrite the last insertion in place.
///
/// Main-thread only by convention, like AppDelegate and PillController:
/// key events arrive on main, and the async work hops back explicitly.
final class CommandModeController {

    enum Phase {
        case idle
        case listening
        case processing
    }

    private(set) var phase: Phase = .idle
    var isBusy: Bool { phase != .idle }

    private let recorder: AudioRecorder
    private let transcriber: Transcriber
    private let llmFormatter: LLMFormatter
    private let inserter: TextInserter
    private let pill: PillController
    private let settings: AppSettings

    /// True while dictation owns the microphone — commands must wait.
    var isDictationBusy: () -> Bool = { false }
    /// The text most recently inserted, and (when known) the exact field
    /// element it went into.
    var lastInsertion: () -> (text: String, target: AXUIElement?)? = { nil }
    /// Called with the edited text after a successful command, so the
    /// app's "last dictation" state follows it and commands can chain
    /// ("make it formal" … "now translate it to French").
    var didEdit: (String) -> Void = { _ in }

    init(
        recorder: AudioRecorder,
        transcriber: Transcriber,
        llmFormatter: LLMFormatter,
        inserter: TextInserter,
        pill: PillController,
        settings: AppSettings
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.llmFormatter = llmFormatter
        self.inserter = inserter
        self.pill = pill
        self.settings = settings
    }

    func keyDown() {
        guard phase == .idle else { return }
        guard !isDictationBusy() else {
            pill.flash("Finish dictating first", seconds: 2)
            return
        }
        guard settings.llmEnabled else {
            pill.flash("Voice commands need AI polish — turn it on in Settings", seconds: 3)
            return
        }
        guard lastInsertion() != nil else {
            pill.flash("Dictate something first — commands edit your last dictation", seconds: 2.5)
            return
        }
        if IsSecureEventInputEnabled() {
            pill.flash("A password field is active — commands are paused until it's dismissed", seconds: 3)
            return
        }
        do {
            try recorder.start()
            SoundFeedback.recordingStarted()
            phase = .listening
            pill.flash("Say how to change your last dictation…", seconds: 600)
        } catch {
            DebugLog.log("Command recorder start failed: \(error.localizedDescription)")
            pill.flash("Microphone error: \(error.localizedDescription)", seconds: 3)
        }
    }

    func keyUp() {
        guard phase == .listening else { return }
        phase = .processing
        let samples = AudioTrim.trimSilence(recorder.stop())
        SoundFeedback.recordingStopped()

        guard samples.count > 4800 else {
            phase = .idle
            pill.flash("Didn't catch that — hold the key while you speak", seconds: 2.5)
            return
        }
        guard let last = lastInsertion() else {
            phase = .idle
            return
        }
        pill.flash("Working on it…", seconds: 60)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.phase = .idle }

            let instruction = await self.transcriber.transcribe(samples)
            guard !instruction.isEmpty else {
                self.pill.flash("Didn't catch that — try again", seconds: 2.5)
                return
            }
            DebugLog.log("Command: instruction \(instruction.count) chars on \(last.text.count) chars")

            let edited = await self.llmFormatter.applyInstruction(
                instruction,
                to: last.text,
                model: self.settings.effectiveLLMModel
            )
            guard let edited, edited != last.text else {
                self.pill.flash("No change made — try rephrasing the command", seconds: 3)
                return
            }

            if self.inserter.replaceLastInsertion(of: last.text, with: edited, target: last.target) {
                self.didEdit(edited)
                self.pill.flash("Done", seconds: 2)
            } else {
                // The field moved on (or refuses edits) — never type into
                // the unknown; hand the result over via the clipboard.
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(edited, forType: .string)
                self.didEdit(edited)
                self.pill.flashAlert("Couldn't edit in place — the new version is copied, press ⌘V")
            }
        }
    }

    /// Esc while listening: stop the mic, change nothing.
    func cancelListening() {
        guard phase == .listening else { return }
        _ = recorder.stop()
        phase = .idle
        pill.flash("Cancelled", seconds: 1.5)
    }
}
