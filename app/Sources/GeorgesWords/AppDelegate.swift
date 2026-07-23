import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import Combine
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    enum State {
        case loadingModel
        case idle
        case recording
        case processing
        case error(String)
    }

    /// A polish computed during a pause in speech (ADR 0008). Usable only
    /// if the final transcript cleans to the same text under the same
    /// knobs — every field must match, or the guess is silently discarded.
    private struct SpeculativeGuess {
        let cleaned: String
        let tone: ToneProfile
        let dictionary: [String]
        let model: String
        let strength: PolishStrength
        let polished: String
    }

    private var statusItem: NSStatusItem!
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let updateMenuItem = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let appStatus = AppStatus.shared

    private let settings = AppSettings.shared
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let cleaner = TranscriptCleaner()
    private let llmFormatter = LLMFormatter()
    private let inserter = TextInserter()
    private let pill = PillController()
    private let updater = Updater()
    /// Sparkle drives updates for DMG installs; nil on the source checkout,
    /// where the git-pull updater owns the job instead (ADR 0007).
    private var sparkle: SPUStandardUpdaterController?
    private var dictationHotkey: HotkeyMonitor?
    private var commandHotkeyMonitor: HotkeyMonitor?
    /// Voice edit commands (backlog 4.4) — its own state machine.
    private var commandMode: CommandModeController!
    /// What command mode edits: the last inserted text and, when the AX
    /// path proved one, the exact field element it went into.
    private var lastInsertion: (text: String, target: AXUIElement?)?
    /// The pre-polish text when the LLM reworded the last insertion —
    /// "Undo AI Rewording" (3.7) swaps it back in.
    private var lastRawAlternative: String?
    /// True once the user typed or clicked in ANOTHER app after the last
    /// insertion. The blind keyboard fallback (Electron apps) rests
    /// entirely on "the caret still sits at the end of an untouched
    /// insertion" — once this flips, destructive fallbacks refuse rather
    /// than guess (QA finding, 2026-07-22: Undo ate surrounding text).
    /// Privacy: the monitor records a single boolean — never which key.
    private var lastInsertionDisturbed = false
    /// True when the last insertion went into a private app (8.1): later
    /// edits of it (command mode, raw swap) must stay out of History too.
    private var lastInsertionPrivate = false
    /// Debounces capture rebuilds after audio-configuration changes.
    private var lastCaptureRebuild = Date.distantPast
    /// Launch-time audio warm-up (owner report, 2026-07-23: the FIRST
    /// press after every update/install never worked — macOS rebuilds
    /// the audio graph on the first capture, historically eating the
    /// recording silently). A throwaway capture takes that hit before
    /// the user's first real press.
    private var warmingUpAudio = false
    private var audioWarmedUp = false
    private let launchDate = Date()
    private var disturbanceMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var previewTask: Task<Void, Never>?

    // Speculative polish (backlog 1.2, ADR 0008): while the user pauses
    // mid-recording, polish the transcript-so-far; if they release the
    // key without saying more, the final pass reuses the cached result.
    private var speculationTask: Task<Void, Never>?
    private var speculationWork: (sampleCount: Int, task: Task<Void, Never>)?
    private var speculativeGuess: SpeculativeGuess?
    private var lastSpeculatedCleaned: String?

    private var lastTranscript: String?

    /// The app dictation started in — the only app the result may be
    /// inserted into (Zach's rule, 2026-07-05). Switch apps mid-recording
    /// or mid-processing and the text lands on the clipboard instead.
    private var recordingContext: AppContext?
    /// Increments per recording so the max-duration watchdog can tell
    /// whether "its" recording is still the live one.
    private var recordingGeneration = 0
    /// Increments per correction check so a newer insertion retires the
    /// re-read attempts still pending for the previous one.
    private var correctionCheckGeneration = 0

    // Quick-tap toggle (hands-free) state.
    private var pressStartedAt: Date?
    private var toggleLatched = false
    private var ignoreNextRelease = false
    /// True while the end-of-speech grace beat (finishRecording) has been
    /// granted for the current dictation — it is granted at most once.
    private var finishGraceApplied = false
    private var escMonitorGlobal: Any?
    private var escMonitorLocal: Any?

    private var state: State = .loadingModel {
        didSet { updateStatusUI() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        appStatus.checkForUpdates = { [weak self] in self?.checkForUpdates() }

        // DMG installs can't self-update via git — Sparkle takes over
        // there, with its own standard UI. Never both at once.
        if !updater.runsFromSourceCheckout {
            sparkle = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
        updateStatusUI()

        // First-run onboarding (5.2): the wizard explains each permission
        // before its system prompt appears. Shown until completed once;
        // wiping the defaults domain (fresh-install testing) brings it back.
        let needsOnboarding = !UserDefaults.standard.bool(forKey: "OnboardingCompleted")
        appStatus.replayOnboarding = { [weak self] in self?.showOnboarding() }

        if !needsOnboarding {
            requestPermissions()
        }

        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            self.pill.updateLevel(level)
            // Menu-bar icon dances with the voice while recording.
            if case .recording = self.state {
                let image = NSImage(
                    systemSymbolName: "waveform",
                    variableValue: Double(min(1, level * 1.2)),
                    accessibilityDescription: "Recording"
                ) ?? NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
                self.statusItem.button?.image = image
            }
        }

        recorder.onConfigurationChange = { [weak self] in
            guard let self, case .recording = self.state else { return }
            // The engine graph is stale once the configuration changes —
            // AirPods connect, or macOS builds its voice-processing
            // aggregate on the FIRST capture after launch. Rebuild the
            // capture path and KEEP recording: captured audio is already
            // converted and survives. Cancelling here killed the first
            // dictation after every update (owner report, 2026-07-23).
            // Debounced: the rebuild itself can echo one more change.
            guard Date().timeIntervalSince(self.lastCaptureRebuild) > 0.75 else { return }
            self.lastCaptureRebuild = Date()
            do {
                try self.recorder.restart()
                DebugLog.log("Audio configuration changed mid-recording — capture rebuilt, recording continues")
            } catch {
                // Right after launch this is the graph still settling,
                // not a device swap — say so (owner request, 2026-07-23).
                let message = Date().timeIntervalSince(self.launchDate) < 8
                    ? "Just starting up — try that dictation again"
                    : "Audio device changed — dictation cancelled"
                self.cancelRecording(message: message)
            }
        }

        // Sleep eats key-up events: without this, waking the Mac could
        // leave the hotkey state stuck and the next press ignored.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if case .recording = self.state {
                self.cancelRecording(message: "Mac went to sleep — dictation cancelled")
            }
            self.dictationHotkey?.reset()
            self.commandHotkeyMonitor?.reset()
            self.commandMode.cancelListening()
            self.toggleLatched = false
            self.ignoreNextRelease = false
        }

        // All update UI lives in the sidebar footer (UpdateFooter): the
        // pill is for dictation feedback only. The menu-bar item still
        // mirrors the phase so it can't be re-triggered mid-run.
        updater.onProgress = { [weak self] text in
            guard let self else { return }
            if let text {
                self.statusMenuItem.title = text
                self.updateMenuItem.title = text
                self.updateMenuItem.isEnabled = false
                self.appStatus.updateProgress = text
            } else {
                self.updateMenuItem.title = "Check for Updates…"
                self.updateMenuItem.isEnabled = true
                self.appStatus.updateProgress = nil
                self.updateStatusUI()
            }
        }
        updater.onNotice = { [weak self] text in
            self?.showUpdateNotice(text)
        }
        // Confirmation from the new build after a successful self-update.
        if UserDefaults.standard.bool(forKey: "JustUpdated") {
            UserDefaults.standard.set(false, forKey: "JustUpdated")
            showUpdateNotice("Updated to the latest version ✓")
        }

        wireCommandMode()
        recorder.preferredInputUID = settings.inputDeviceUID
        // During onboarding, holding fn must do nothing until the Try-it
        // page — the wizard turns dictation on at that moment.
        if !needsOnboarding {
            installHotkeys()
            installEscMonitor()
            installDisturbanceMonitor()
        }
        observeSettings()

        // The polish engine manages itself (7.7, ADR 0006): the app always
        // runs its own private engine — never a user-installed Ollama.
        if settings.llmEnabled {
            ManagedOllama.shared.ensureReady(model: settings.effectiveLLMModel)
        }

        Task { await loadModel() }

        // Opened by the user → show the window like a normal app. Started
        // by login (or launchd) → stay in the background; the menu-bar icon
        // is presence enough. Fresh install → the onboarding wizard instead.
        if needsOnboarding {
            showOnboarding()
        } else if !launchedAsLoginItem {
            openMainWindow()
        }

        // Settle the audio graph BEFORE the first real press: the first
        // capture after a launch makes macOS rebuild the graph (and
        // spawn its voice-processing aggregate), which ate the first
        // dictation after every update — silently for weeks, then with
        // a confusing cancellation (owner report, 2026-07-23). A brief
        // throwaway capture takes that hit now instead. Skipped without
        // the mic permission — never trigger the prompt at startup; the
        // onboarding practice page is the warm-up on a fresh install.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.warmUpAudioCapture()
        }
    }

    private func warmUpAudioCapture() {
        guard !audioWarmedUp, !warmingUpAudio else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        if case .recording = state {
            // The user beat the warm-up to it — their capture settles
            // the graph (the config-change rebuild covers them).
            audioWarmedUp = true
            return
        }
        do {
            try recorder.start()
        } catch {
            DebugLog.log("Audio warm-up skipped: \(error.localizedDescription)")
            audioWarmedUp = true
            return
        }
        warmingUpAudio = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            // A real press may have taken the mic over meanwhile —
            // startRecording cleared the flag and owns the engine now.
            guard self.warmingUpAudio else { return }
            _ = self.recorder.stop()
            self.warmingUpAudio = false
            self.audioWarmedUp = true
            DebugLog.log("Audio warm-up complete — graph settled before the first dictation")
        }
    }

    // MARK: - Onboarding (backlog 5.2)

    private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(
                onFinish: { [weak self] in self?.completeOnboarding() },
                onReachedPractice: { [weak self] in
                    self?.installHotkeys()
                    self?.installEscMonitor()
                    self?.installDisturbanceMonitor()
                }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to George's Words"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // Closing the wizard early is a skip, not a dead end: the
            // hotkeys still get installed so dictation works this run,
            // and the wizard returns on the next launch/reopen because
            // OnboardingCompleted was never set (review P2, 2026-07-22).
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let self,
                      !UserDefaults.standard.bool(forKey: "OnboardingCompleted")
                else { return }
                self.installHotkeys()
                self.installEscMonitor()
                self.installDisturbanceMonitor()
            }
            onboardingWindow = window
        }
        onboardingWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "OnboardingCompleted")
        onboardingWindow?.close()
        onboardingWindow = nil
        // Global event monitors registered before the Accessibility grant
        // never receive events — install fresh ones now.
        installHotkeys()
        installEscMonitor()
        installDisturbanceMonitor()
        openMainWindow()
    }

    /// Dock icon clicked (or app re-opened) with no visible windows.
    /// Unfinished onboarding resumes instead of jumping to the main
    /// window — a closed wizard would otherwise be unreachable this run.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !UserDefaults.standard.bool(forKey: "OnboardingCompleted") {
            showOnboarding()
        } else {
            openMainWindow()
        }
        return false
    }

    /// Closing the window must not quit — dictation keeps running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the managed polish engine running as an orphan.
        ManagedOllama.shared.shutdown()
    }

    /// True when launchd started us as a login item: the initial 'oapp'
    /// Apple Event carries propData 'lgit'. Four-char codes are spelled as
    /// literals so this compiles without the Carbon constant headers.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventClass == AEEventClass(0x6165_7674) // 'aevt'
            && event.eventID == AEEventID(0x6F61_7070)       // 'oapp'
            && event.paramDescriptor(forKeyword: AEKeyword(0x7072_6474))? // 'prdt'
                .enumCodeValue == OSType(0x6C67_6974)        // 'lgit'
    }

    // MARK: - Permissions

    private func requestPermissions() {
        // Microphone: triggers the system prompt on first launch.
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                NSLog("Microphone access denied — dictation cannot work without it.")
            }
        }
        // Accessibility: needed to observe the global hotkeys and insert text.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Settings wiring

    private func installHotkeys() {
        dictationHotkey = HotkeyMonitor(
            hotkey: settings.hotkey,
            onPress: { [weak self] in self?.beginRecording() },
            onRelease: { [weak self] in self?.endRecording() }
        )
        // Command hotkey: off until assigned, and never the dictation key
        // (Settings refuses the conflict; this guard covers stale data).
        commandHotkeyMonitor = nil
        if let spec = settings.commandHotkey, spec != settings.hotkey {
            commandHotkeyMonitor = HotkeyMonitor(
                hotkey: spec,
                onPress: { [weak self] in self?.commandMode.keyDown() },
                onRelease: { [weak self] in self?.commandMode.keyUp() }
            )
        }
    }

    private func wireCommandMode() {
        commandMode = CommandModeController(
            recorder: recorder,
            transcriber: transcriber,
            llmFormatter: llmFormatter,
            inserter: inserter,
            pill: pill,
            settings: settings
        )
        commandMode.isDictationBusy = { [weak self] in
            guard let self else { return true }
            if case .idle = self.state { return false }
            return true
        }
        commandMode.lastInsertion = { [weak self] in self?.lastInsertion }
        commandMode.isLastInsertionUndisturbed = { [weak self] in
            self.map { !$0.lastInsertionDisturbed } ?? false
        }
        commandMode.didEdit = { [weak self] edited in
            guard let self else { return }
            // The edit becomes the new "last dictation" so commands chain
            // ("make it formal" … "now translate it to French"). The
            // unpolished alternative no longer corresponds to it.
            self.lastInsertion = (edited, self.lastInsertion?.target)
            self.lastRawAlternative = nil
            self.lastInsertionDisturbed = false
            self.lastTranscript = edited
            self.appStatus.lastTranscript = edited
            // A dictation born in a private app stays out of History
            // through every later edit too (review P1, 2026-07-22).
            if !self.lastInsertionPrivate {
                HistoryStore.shared.add(edited)
            }
        }
    }

    private func observeSettings() {
        settings.$hotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installHotkeys() }
            .store(in: &cancellables)

        settings.$commandHotkey
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installHotkeys() }
            .store(in: &cancellables)

        settings.$inputDeviceUID
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uid in self?.recorder.preferredInputUID = uid }
            .store(in: &cancellables)

        settings.$modelName
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.loadModel() }
            }
            .store(in: &cancellables)

        settings.$engine
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.loadModel() }
            }
            .store(in: &cancellables)

        settings.$llmEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                let model = self.settings.effectiveLLMModel
                // ManagedOllama is @MainActor; the sink closure isn't
                // (statically), so hop explicitly.
                Task { @MainActor in
                    ManagedOllama.shared.setEnabled(enabled, model: model)
                }
            }
            .store(in: &cancellables)

        settings.$llmModel
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.settings.llmEnabled else { return }
                let model = self.settings.effectiveLLMModel
                // A newly picked model may need pulling on the managed engine.
                Task { @MainActor in
                    ManagedOllama.shared.ensureReady(model: model)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Model

    /// Guards overlapping loads: only the NEWEST call may touch app
    /// state afterwards. A superseded load's CancellationError used to
    /// land in the catch and stamp .error over the newer load's flow
    /// (review follow-up, 2026-07-22).
    private var modelLoadGeneration = 0

    private func loadModel() async {
        let generation = await MainActor.run { () -> Int in
            // A model swap can land mid-recording; don't leave the mic running.
            if case .recording = self.state { _ = self.recorder.stop() }
            self.previewTask?.cancel()
            self.state = .loadingModel
            self.modelLoadGeneration += 1
            return self.modelLoadGeneration
        }
        do {
            try await transcriber.load()
            await MainActor.run {
                guard generation == self.modelLoadGeneration else { return }
                // A press may have started a recording while we loaded —
                // don't clobber it; it resolves to .idle on its own.
                if case .loadingModel = self.state { self.state = .idle }
            }
        } catch is CancellationError {
            // Superseded by a newer load — that call owns the state now.
        } catch {
            await MainActor.run {
                guard generation == self.modelLoadGeneration else { return }
                self.state = .error("Model failed to load: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recording

    /// GLOBAL monitor only, deliberately: it fires for events in OTHER
    /// apps — exactly the ones that move the target field's caret. Our
    /// own windows (menu clicks, Settings typing) never disturb the
    /// target, and our own synthetic keystrokes are filtered out by
    /// their timestamp. Records only that SOMETHING was pressed.
    private func installDisturbanceMonitor() {
        if let disturbanceMonitor { NSEvent.removeMonitor(disturbanceMonitor) }
        disturbanceMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            guard Date().timeIntervalSince(self.inserter.lastSyntheticKeyAt) > 0.5 else { return }
            self.lastInsertionDisturbed = true
        }
    }

    private func installEscMonitor() {
        if let escMonitorGlobal { NSEvent.removeMonitor(escMonitorGlobal) }
        if let escMonitorLocal { NSEvent.removeMonitor(escMonitorLocal) }
        let handle: (NSEvent) -> Bool = { [weak self] event in
            guard let self, event.keyCode == 53 else { return false }
            if self.commandMode.phase == .listening {
                self.commandMode.cancelListening()
                return true
            }
            guard case .recording = self.state else { return false }
            self.cancelRecording(message: "Cancelled")
            return true
        }
        escMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ = handle($0) }
        escMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    /// Discard the in-progress recording without inserting anything.
    private func cancelRecording(message: String) {
        guard case .recording = state else { return }
        previewTask?.cancel()
        speculationTask?.cancel()
        speculativeGuess = nil
        _ = recorder.stop()
        toggleLatched = false
        ignoreNextRelease = false
        finishGraceApplied = false
        recordingContext = nil
        state = .idle
        pill.flash(message, seconds: 1.5)
    }

    /// Hands-free mode has no natural end — an accidental quick tap could
    /// otherwise leave the microphone recording forever. Ten minutes is the
    /// ceiling; whatever was said still transcribes and inserts normally.
    private func scheduleRecordingCap(generation: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            guard let self,
                  generation == self.recordingGeneration,
                  case .recording = self.state
            else { return }
            self.toggleLatched = false
            self.ignoreNextRelease = true
            self.finishRecording()
        }
    }

    private func beginRecording() {
        // Second press while latched = the stop signal for toggle mode.
        if toggleLatched, case .recording = state {
            toggleLatched = false
            ignoreNextRelease = true
            finishRecording()
            return
        }

        // The microphone is single-owner: a voice command in progress
        // keeps it until it resolves.
        if commandMode.isBusy {
            pill.flash("A voice command is in progress…", seconds: 2)
            return
        }

        // Never swallow a press silently — explain why it can't start yet.
        switch state {
        case .idle:
            break
        case .loadingModel:
            // The recorder doesn't need the model. Start capturing now —
            // transcribe() explicitly awaits the in-flight load (see
            // Transcriber), so the result just arrives once the model is
            // ready. Without this, the first press after launch got
            // rejected and felt broken.
            DebugLog.log("Press while model still loading — recording anyway")
            break
        case .processing:
            pill.flash("Finishing the previous dictation…", seconds: 2)
            return
        case .error(let message):
            pill.flash(message, seconds: 4)
            return
        case .recording:
            return
        }

        // Secure input (password fields) blocks both our event monitors and
        // AX insertion — refuse up front with an explanation instead of
        // recording into a black hole.
        if IsSecureEventInputEnabled() {
            pill.flash("A password field is active — dictation is paused until it's dismissed", seconds: 3)
            return
        }

        pressStartedAt = Date()
        recordingContext = AppContext.current()
        // A real press takes the microphone over from the launch
        // warm-up — stop it first so the tap is never installed twice.
        if warmingUpAudio {
            _ = recorder.stop()
            warmingUpAudio = false
            audioWarmedUp = true
        }
        do {
            try recorder.start()
            SoundFeedback.recordingStarted()
            state = .recording
            recordingGeneration += 1
            scheduleRecordingCap(generation: recordingGeneration)
            if settings.previewEnabled {
                startPreviewLoop()
            }
            speculativeGuess = nil
            lastSpeculatedCleaned = nil
            speculationWork = nil
            // Load the LLM / prime its prompt cache while the user speaks,
            // so the polish pass starts hot.
            if settings.llmEnabled {
                llmFormatter.warmUpIfStale(model: settings.effectiveLLMModel, strength: settings.polishStrength)
                startSpeculationLoop()
            }
        } catch {
            DebugLog.log("Recorder start failed: \(error.localizedDescription)")
            state = .error("Microphone error: \(error.localizedDescription)")
        }
    }

    /// Hotkey release: either finish, or — for a quick tap — latch into
    /// hands-free toggle mode (tap again to stop).
    private func endRecording() {
        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        guard case .recording = state else { return }
        if toggleLatched { return }
        if let pressStartedAt, Date().timeIntervalSince(pressStartedAt) < 0.35 {
            toggleLatched = true
            return
        }
        finishRecording()
    }

    private func finishRecording() {
        guard case .recording = state else { return }
        // Released while — or a beat after — still speaking? Then the last
        // word's audio is clipped, and rare words decode wrong from a
        // clipped waveform ("Abugov" came out "Abercov"; on-device finding,
        // 2026-07-22). Keep the mic open one grace beat so the decoder
        // gets the whole word. Pause-then-release stays instant: the tail
        // is already silent. One grace per dictation, so continuing to
        // talk past the release can't stall the finish.
        if !finishGraceApplied, !AudioTrim.isNearSilence(recorder.snapshotTail(seconds: 0.25)) {
            finishGraceApplied = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                // Esc or sleep may have cancelled the recording meanwhile.
                guard case .recording = self.state else { return }
                self.finishRecording()
            }
            return
        }
        finishGraceApplied = false
        previewTask?.cancel()
        // Stop hunting for pauses; a speculation already in flight keeps
        // running — the final pass may be about to collect its result.
        speculationTask?.cancel()
        let rawSamples = recorder.stop()
        let samples = AudioTrim.trimSilence(rawSamples)
        SoundFeedback.recordingStopped()

        // Taps shorter than ~0.3 s of audio can't transcribe — but say so
        // instead of going silently idle, which read as "the app ignored
        // me" to first-time users. A long recording that trimmed down to
        // nothing is a different story: the mic heard only silence (6.5).
        guard samples.count > 4800 else {
            state = .idle
            if rawSamples.count > 16_000 && AudioTrim.isNearSilence(rawSamples) {
                DebugLog.log("Recording dropped: \(rawSamples.count) raw samples, all near-silence — mic muted or wrong input?")
                pill.flashAlert("Only silence was heard — is the microphone muted, or the wrong one selected in Settings?")
            } else {
                DebugLog.log("Recording dropped: only \(samples.count) samples captured")
                pill.flash("Didn't catch that — hold the key down while you speak", seconds: 2.5)
            }
            return
        }

        // The dictation belongs to the app it STARTED in; tone and
        // insertion both follow that, not whatever is frontmost later.
        let context = recordingContext ?? AppContext.current()
        recordingContext = nil
        state = .processing

        Task {
            let (text, rawAlternative) = await self.processDictation(samples: samples, context: context)
            await MainActor.run {
                var outcome: TextInserter.Outcome?
                var switchedApps = false
                if !text.isEmpty {
                    self.lastTranscript = text
                    self.appStatus.lastTranscript = text
                    // Private apps (8.1): nothing dictated into them is
                    // kept in history (word-count stats carry no content).
                    if !self.settings.isPrivateApp(context.bundleID) {
                        HistoryStore.shared.add(text)
                    }
                    StatsStore.shared.record(words: text.split(separator: " ").count)
                    if AppContext.current().bundleID == context.bundleID {
                        outcome = self.inserter.insert(text)
                        if outcome == .inserted {
                            self.lastInsertion = (text, self.inserter.lastInsertionTarget)
                            self.lastRawAlternative = rawAlternative
                            self.lastInsertionDisturbed = false
                            self.lastInsertionPrivate = self.settings.isPrivateApp(context.bundleID)
                            self.scheduleCorrectionCheck(
                                inserted: text,
                                context: context,
                                target: self.inserter.lastInsertionTarget
                            )
                        }
                    } else {
                        // Different app frontmost than where dictation
                        // began — never type into the wrong window.
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                        switchedApps = true
                    }
                }
                // A model swap may have taken over the state meanwhile.
                if case .processing = self.state { self.state = .idle }
                // Flash AFTER the state change: setting .idle refreshes the
                // status UI, and a flash shown before it would be hidden.
                if switchedApps {
                    self.pill.flashAlert("You switched apps — press ⌘V to paste your dictation")
                }
                if outcome == .copiedToClipboard { self.flashAccessibilityWarning() }
            }
        }
    }

    // MARK: - Auto-learning dictionary (ADR 0005)

    /// After inserting, re-read the edited field on a widening schedule and
    /// diff it against what was inserted — the user's fixes become dictionary
    /// suggestions (ADR 0005, amended for backlog 2.5). Prefers re-reading
    /// the exact element the text went into; only the focus-based fallback
    /// still requires the same app to be frontmost. Entirely local, and a
    /// newer dictation's check silently retires this one.
    private func scheduleCorrectionCheck(inserted: String, context: AppContext, target: AXUIElement?) {
        // The global off switch (backlog 8.3): no watching, no re-reads.
        guard settings.correctionLearningEnabled else { return }
        // Private apps (8.1) are never re-read.
        guard !settings.isPrivateApp(context.bundleID) else { return }
        correctionCheckGeneration += 1
        let generation = correctionCheckGeneration

        Task { @MainActor [weak self] in
            var target = target
            var waited = 0.0
            var alreadySuggested = Set<String>()

            // The paste fallback proves nothing about elements — grab the
            // focused one a beat after the paste lands, while the caret is
            // still almost certainly in the field we typed into.
            if target == nil {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waited = 1
                guard let self, generation == self.correctionCheckGeneration else { return }
                if case .idle = self.state, AppContext.current().bundleID == context.bundleID {
                    target = AXFocus.focusedElement(logContext: "Correction target capture")
                }
            }

            // One fixed 6 s peek (the original design) missed every fix made
            // after it — reaching for the mouse, re-reading the sentence.
            // Three peeks on a widening schedule catch the slow tail too.
            for mark in [6.0, 20.0, 60.0] {
                try? await Task.sleep(nanoseconds: UInt64((mark - waited) * 1_000_000_000))
                waited = mark
                guard let self, generation == self.correctionCheckGeneration else { return }
                let label = "Correction check \(Int(mark))s"

                // Settings can change while a check is pending: turning
                // learning off (or marking the app private) must also stop
                // reads scheduled BEFORE the change (review P2, 2026-07-22).
                guard self.settings.correctionLearningEnabled,
                      !self.settings.isPrivateApp(context.bundleID) else {
                    DebugLog.log("\(label): learning disabled since scheduling — stopped")
                    return
                }

                // Mid-dictation reads would race the next insertion.
                guard case .idle = self.state else {
                    DebugLog.log("\(label): busy, skipped")
                    continue
                }

                var fieldText: String?
                if let element = target {
                    fieldText = FocusedFieldReader.read(element: element)
                    if fieldText == nil {
                        // Window closed or the app recycled the element —
                        // the reference is dead; stop trying it.
                        DebugLog.log("\(label): tracked element gone")
                        target = nil
                    }
                }
                if fieldText == nil {
                    // Focus is only meaningful in the app we dictated into;
                    // anything else would read some unrelated field.
                    guard AppContext.current().bundleID == context.bundleID else {
                        DebugLog.log("\(label): other app frontmost, skipped")
                        continue
                    }
                    fieldText = FocusedFieldReader.read()
                }
                guard let fieldText, !fieldText.isEmpty else {
                    DebugLog.log("\(label): no field text")
                    continue
                }

                let candidates = CorrectionDetector.substitutions(from: inserted, to: fieldText)
                var newCount = 0
                for substitution in candidates {
                    // A later peek re-seeing the same fix isn't a second
                    // sighting — only count it once per insertion.
                    let key = substitution.heard.lowercased() + "\u{1F}" + substitution.corrected.lowercased()
                    guard alreadySuggested.insert(key).inserted else { continue }
                    if CorrectionStore.shared.add(
                        heard: substitution.heard,
                        corrected: substitution.corrected,
                        settings: self.settings
                    ) {
                        newCount += 1
                    }
                }
                DebugLog.log("\(label): field \(fieldText.count) chars, \(candidates.count) candidate(s), \(newCount) new")

                // The capture used to be silent, so the suggestion queue
                // went undiscovered (backlog 2.5) — one quiet, transient
                // nudge right after the user made the fix.
                if newCount > 0 {
                    self.pill.flash(
                        newCount == 1
                            ? "Noticed your fix — suggestion waiting in Dictionary"
                            : "Noticed \(newCount) fixes — suggestions waiting in Dictionary",
                        seconds: 3
                    )
                }
            }
        }
    }

    /// transcribe → rule cleanup → snippets → (optional) local-LLM polish.
    /// `rawAlternative` is the pre-LLM text whenever polish actually
    /// reworded it — "use raw instead" (3.7) swaps it back in.
    private func processDictation(samples: [Float], context: AppContext) async -> (text: String, rawAlternative: String?) {
        // A speculation still in flight from the last pause is about to be
        // a perfect hit if the user said nothing after its snapshot — wait
        // for it rather than duplicate its work. Meaningfully more final
        // audio than the snapshot means they kept talking; skip the wait.
        // (Both wrong guesses only cost latency — the equality check on
        // the guess below is what decides correctness.)
        if let pending = await MainActor.run(body: { self.speculationWork }),
           samples.count <= pending.sampleCount + 8_000 {
            await pending.task.value
        }

        let transcribeStart = Date()
        let raw = await transcriber.transcribe(samples)
        let transcribeSeconds = Date().timeIntervalSince(transcribeStart)
        guard !raw.isEmpty else { return ("", nil) }

        let (cleaned, polishEligible) = cleanForPolish(raw)
        guard polishEligible else {
            await updateTiming(transcribe: transcribeSeconds, polish: nil)
            return (cleaned, nil)
        }

        let dictionary = settings.dictionaryTerms
        let model = settings.effectiveLLMModel
        let strength = settings.polishStrength

        // The prize: a pause-time speculation that still matches means the
        // polish already happened while the user was silent.
        if let guess = await MainActor.run(body: { self.speculativeGuess }),
           guess.cleaned == cleaned, guess.tone == context.tone,
           guess.dictionary == dictionary, guess.model == model,
           guess.strength == strength {
            DebugLog.log("Speculative polish: hit (\(cleaned.count) chars)")
            await updateTiming(transcribe: transcribeSeconds, polish: 0)
            return (guess.polished, guess.polished == cleaned ? nil : cleaned)
        }

        let polishStart = Date()
        let polished = await llmFormatter.format(
            cleaned,
            tone: context.tone,
            dictionary: dictionary,
            model: model,
            strength: strength
        )
        await updateTiming(transcribe: transcribeSeconds, polish: Date().timeIntervalSince(polishStart))
        guard var polished, polished != cleaned else { return (cleaned, nil) }
        // The polish model re-copies the transcript and can mangle rare
        // letter-strings — debug.log 2026-07-23: the cleaned text held
        // the correct dictionary address ("Email fold: snapped") yet a
        // misspelled one reached the field. Emails are deliberately
        // excluded from the model's DICTIONARY line, so nothing anchors
        // them for it; re-fold deterministically after polish.
        polished = TranscriptCleaner.applyDictionaryEmails(polished, dictionary: dictionary)
        guard polished != cleaned else { return (cleaned, nil) }
        return (polished, cleaned)
    }

    /// Rule cleanup + snippets + the LLM eligibility gates — shared by the
    /// final pass and the speculative pass, which must agree exactly for a
    /// speculation to ever be usable. The gates: skip the LLM when a
    /// snippet fired (its expansion must be inserted verbatim), when spoken
    /// commands produced explicit line breaks (the polish pass writes
    /// single blocks and would flatten them), and for very short
    /// utterances (nothing to restructure; skipping keeps them instant).
    private func cleanForPolish(_ raw: String) -> (text: String, polishEligible: Bool) {
        let dictionary = settings.dictionaryTerms
        var cleaned = cleaner.clean(raw, dictionary: dictionary, replacements: settings.dictionaryReplacements)
        let (expanded, snippetApplied) = SnippetExpander.apply(settings.snippets, to: cleaned)
        cleaned = expanded
        let wordCount = cleaned.split(separator: " ").count
        let eligible = settings.llmEnabled && !snippetApplied && !cleaned.contains("\n") && wordCount >= 5
        return (cleaned, eligible)
    }

    @MainActor
    private func updateTiming(transcribe: TimeInterval, polish: TimeInterval?) {
        if let polish {
            appStatus.lastTiming = polish < 0.05
                // A speculative-polish hit: the work happened mid-pause.
                ? String(format: "Last dictation: %.1f s transcribe + polish done during a pause", transcribe)
                : String(format: "Last dictation: %.1f s transcribe + %.1f s polish", transcribe, polish)
        } else {
            appStatus.lastTiming = String(format: "Last dictation: %.1f s transcribe (no polish)", transcribe)
        }
    }

    // MARK: - Live preview

    /// While recording, periodically transcribe the audio-so-far and show it
    /// in the pill. The Transcriber actor serializes these with the final
    /// pass, so they can never collide.
    private func startPreviewLoop() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, !Task.isCancelled else { return }

                let stillRecording = await MainActor.run { () -> Bool in
                    if case .recording = self.state { return true }
                    return false
                }
                guard stillRecording else { return }

                // Need at least 1 s of audio (cheap count, no copy).
                guard self.recorder.sampleCount > 16_000 else { continue }
                // Preview re-transcribes only the last ~15 s — constant
                // cost however long the dictation runs, so the pill keeps
                // flowing to the very end instead of freezing at 30 s
                // (Zach's report, 2026-07-06).
                let snapshot = self.recorder.snapshotTail(seconds: 15)
                // A muted/silent mic must show nothing: speech models
                // hallucinate on empty audio ("Thank you." — QA finding,
                // 2026-07-22), and the final pass would refuse this same
                // recording with the silence alert. Don't transcribe it.
                guard !AudioTrim.isNearSilence(snapshot) else { continue }

                let text = await self.transcriber.transcribe(snapshot)
                guard !Task.isCancelled, !text.isEmpty else { continue }
                await MainActor.run {
                    if case .recording = self.state {
                        self.pill.updatePreview(text)
                    }
                }
            }
        }
    }

    // MARK: - Speculative polish (backlog 1.2, ADR 0008)

    /// Watch for pauses in speech; on each one, transcribe the whole
    /// buffer and polish it in the background. Release the key without
    /// saying more and the final pass reuses the result — the polish
    /// latency happened while the user was silent. Keep talking and the
    /// guess dies on the equality check instead. The Transcriber actor
    /// serializes these with the preview and final passes.
    private func startSpeculationLoop() {
        speculationTask?.cancel()
        speculationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let self, !Task.isCancelled else { return }
                guard case .recording = self.state else { return }

                let sampleCount = self.recorder.sampleCount
                // Not enough said yet to clear the 5-word polish gate.
                guard sampleCount > 16_000 else { continue }
                // Re-transcribing the full buffer is the cost of each
                // guess — don't burn battery on marathon dictations.
                guard sampleCount <= 16_000 * 90 else { continue }
                // A pause = the last ~0.7 s is near-silent.
                guard AudioTrim.isNearSilence(self.recorder.snapshotTail(seconds: 0.7)) else { continue }

                let samples = self.recorder.snapshot()
                let context = self.recordingContext ?? AppContext.current()
                let generation = self.recordingGeneration
                let work = Task { await self.speculate(samples: samples, context: context, generation: generation) }
                self.speculationWork = (samples.count, work)
                // One speculation at a time; the next pause check waits
                // for this one to land.
                await work.value
            }
        }
    }

    @MainActor
    private func speculate(samples: [Float], context: AppContext, generation: Int) async {
        let raw = await transcriber.transcribe(samples)
        guard !raw.isEmpty else { return }
        let (cleaned, eligible) = cleanForPolish(raw)
        // Same pause, same words as last time — the guess is already made.
        guard eligible, cleaned != lastSpeculatedCleaned else { return }
        lastSpeculatedCleaned = cleaned

        let dictionary = settings.dictionaryTerms
        let model = settings.effectiveLLMModel
        let strength = settings.polishStrength
        guard var polished = await llmFormatter.format(
            cleaned,
            tone: context.tone,
            dictionary: dictionary,
            model: model,
            strength: strength
        ) else { return }
        // Same post-polish email restoration as the final pass — the
        // cache must hold exactly what the final pass would produce.
        polished = TranscriptCleaner.applyDictionaryEmails(polished, dictionary: dictionary)

        // A newer recording may have started while we polished — never
        // hand it a stale guess.
        guard generation == recordingGeneration else { return }
        speculativeGuess = SpeculativeGuess(
            cleaned: cleaned,
            tone: context.tone,
            dictionary: dictionary,
            model: model,
            strength: strength,
            polished: polished
        )
        DebugLog.log("Speculative polish: guess ready (\(cleaned.count) chars)")
    }

    // MARK: - Main menu (Dock app)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "George's Words")
        appMenuItem.submenu = appMenu
        let aboutItem = appMenu.addItem(withTitle: "About George's Words", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        let updatesItem = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide George's Words", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit George's Words", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu bar status item

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open George's Words", action: #selector(openMainWindowAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let pasteLast = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLastTranscript), keyEquivalent: "")
        pasteLast.target = self
        menu.addItem(pasteLast)

        let correctLast = NSMenuItem(title: "Correct Last Transcript…", action: #selector(correctLastTranscript), keyEquivalent: "")
        correctLast.target = self
        menu.addItem(correctLast)

        let useRaw = NSMenuItem(title: "Undo AI Rewording", action: #selector(useRawTranscript), keyEquivalent: "")
        useRaw.target = self
        menu.addItem(useRaw)

        let undoInsert = NSMenuItem(title: "Undo Last Insertion", action: #selector(undoLastInsertion), keyEquivalent: "")
        undoInsert.target = self
        menu.addItem(undoInsert)

        menu.addItem(.separator())

        updateMenuItem.action = #selector(checkForUpdates)
        updateMenuItem.target = self
        menu.addItem(updateMenuItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit George's Words", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    /// The app icon shrunk for the menu bar — George himself, not a
    /// microphone glyph: the SF Symbols mic read as the SYSTEM's
    /// input indicator sitting next to the real one (owner request,
    /// 2026-07-22). Deliberately not a template image; the artwork is
    /// the recognizable brand mark. Built once.
    private static let menuBarAppIcon: NSImage? = {
        guard let icon = NSApp.applicationIconImage?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }()

    private func updateStatusUI() {
        let symbol: String?
        let text: String
        switch state {
        case .loadingModel:
            symbol = "hourglass"
            text = "Downloading / loading model…"
        case .idle:
            // The app icon when ready; the transient states below keep
            // their distinct glyphs so state feedback stays obvious
            // (recording additionally dances via the waveform in onLevel).
            symbol = nil
            text = "Ready — hold \(settings.hotkey.displayName) and speak"
        case .recording:
            symbol = "mic.fill"
            text = "Recording…"
        case .processing:
            symbol = "ellipsis.circle"
            text = "Transcribing…"
        case .error(let message):
            symbol = "exclamationmark.triangle"
            text = message
        }
        if let symbol {
            statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        } else {
            statusItem.button?.image = Self.menuBarAppIcon
                ?? NSImage(systemSymbolName: "text.bubble", accessibilityDescription: text)
        }
        statusItem.button?.toolTip = text
        statusMenuItem.title = text

        appStatus.statusText = text
        appStatus.health = {
            switch state {
            case .loadingModel: return .loading
            case .idle: return .ready
            case .recording: return .recording
            case .processing: return .processing
            case .error: return .error
            }
        }()
        appStatus.engineDescription = settings.engine == .parakeet
            ? "Parakeet v3 (parakeet-tdt-0.6b-v3), fully on-device"
            : "Whisper (\(settings.modelName)), fully on-device"

        switch state {
        case .recording:
            pill.show(.listening)
        case .processing:
            pill.show(.transcribing)
        default:
            // Never clobber an active flash — its own timer hides it.
            if !pill.isFlashing { pill.hide() }
        }
    }

    // MARK: - Actions

    @objc private func pasteLastTranscript() {
        guard let lastTranscript else { return }
        if inserter.insert(lastTranscript) == .copiedToClipboard {
            flashAccessibilityWarning()
        }
    }

    /// 3.7: polish reworded something it shouldn't have — swap the
    /// pre-polish text back into the field, in place.
    @objc private func useRawTranscript() {
        guard let last = lastInsertion, let raw = lastRawAlternative else {
            pill.flash("The AI didn\u{2019}t reword the last dictation \u{2014} nothing to undo", seconds: 2.5)
            return
        }
        if lastInsertionDisturbed {
            // The field changed since the insertion. Even the AX replace
            // is unsafe now: it targets the LAST occurrence of the text,
            // and typing since could have created a newer duplicate
            // (review P2, 2026-07-22). Hand over via clipboard.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(raw, forType: .string)
            pill.flashAlert("The text changed since it was inserted — your original words are copied; select the text and press ⌘V")
        } else if inserter.replaceLastInsertion(of: last.text, with: raw, target: last.target) {
            finishRawSwap(raw: raw, target: last.target)
        } else {
            // Electron/Chromium fields refuse the AX replace — try the
            // keyboard delete-and-paste, then the clipboard as last resort.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await self.inserter.replaceLastInsertionByKeyboard(previousLength: last.text.count, with: raw) {
                    self.finishRawSwap(raw: raw, target: last.target)
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(raw, forType: .string)
                    self.pill.flashAlert("Couldn't swap it in place — your exact words are copied; select your last dictation and press ⌘V")
                }
            }
        }
    }

    private func finishRawSwap(raw: String, target: AXUIElement?) {
        lastInsertion = (raw, target)
        lastRawAlternative = nil
        lastTranscript = raw
        appStatus.lastTranscript = raw
        if !lastInsertionPrivate {
            HistoryStore.shared.add(raw)
        }
        pill.flash("Swapped in your exact words", seconds: 2)
    }

    /// 5.5: remove the most recent insertion entirely.
    @objc private func undoLastInsertion() {
        guard let last = lastInsertion else {
            pill.flash("Nothing to undo yet", seconds: 2)
            return
        }
        if lastInsertionDisturbed {
            // Refuse before even the AX replace: it targets the last
            // OCCURRENCE, and edits since the insertion could have
            // created a newer duplicate of the same text.
            pill.flashAlert("Can't undo automatically — the text changed after it was inserted. Delete it by hand.")
        } else if inserter.replaceLastInsertion(of: last.text, with: "", target: last.target) {
            finishUndo()
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await self.inserter.replaceLastInsertionByKeyboard(previousLength: last.text.count, with: "") {
                    self.finishUndo()
                } else {
                    self.pill.flashAlert("Couldn't remove it automatically — delete it by hand")
                }
            }
        }
    }

    private func finishUndo() {
        lastInsertion = nil
        lastRawAlternative = nil
        pill.flash("Last insertion removed", seconds: 2)
    }

    /// The ad-hoc-signing trap: after a rebuild macOS silently invalidates
    /// the Accessibility grant while still showing it enabled. Tell the
    /// user instead of failing silently.
    private func flashAccessibilityWarning() {
        // Longer than the app-switch alert: this one carries instructions.
        pill.flashAlert("No Accessibility permission — copied to clipboard. Re-toggle GeorgesWords in System Settings → Accessibility.", seconds: 6)
    }

    func openMainWindow(section: MainSection? = nil) {
        if let section {
            appStatus.selectedSection = section
        }
        if mainWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MainWindowView()))
            window.title = "George's Words"
            window.setContentSize(NSSize(width: 900, height: 580))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("MainWindow")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openMainWindowAction() {
        openMainWindow()
    }

    @objc private func openSettings() {
        openMainWindow(section: .settings)
    }

    @objc private func openAbout() {
        openMainWindow(section: .about)
    }

    /// AX-read fallback: fix the last transcript by hand in the Dictionary
    /// tab and the diff is learned from that.
    @objc private func correctLastTranscript() {
        openMainWindow(section: .dictionary)
    }

    /// Transient outcome text in the sidebar's update footer.
    private func showUpdateNotice(_ text: String) {
        appStatus.updateNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.appStatus.updateNotice == text {
                self?.appStatus.updateNotice = nil
            }
        }
    }

    @objc private func checkForUpdates() {
        if let sparkle {
            NSApp.activate(ignoringOtherApps: true)
            sparkle.checkForUpdates(nil)
            return
        }
        guard !updater.isUpdating else { return }
        // Instant feedback on click — the first background progress message
        // may be a beat away while git starts up.
        updateMenuItem.title = "Checking for updates…"
        updateMenuItem.isEnabled = false
        appStatus.updateProgress = "Checking for updates…"
        updater.checkAndInstall()
    }
}
