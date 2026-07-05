import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    enum State {
        case loadingModel
        case idle
        case recording
        case processing
        case error(String)
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
    private var dictationHotkey: HotkeyMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var previewTask: Task<Void, Never>?

    private var lastTranscript: String?

    /// The app dictation started in — the only app the result may be
    /// inserted into (Zach's rule, 2026-07-05). Switch apps mid-recording
    /// or mid-processing and the text lands on the clipboard instead.
    private var recordingContext: AppContext?
    /// Increments per recording so the max-duration watchdog can tell
    /// whether "its" recording is still the live one.
    private var recordingGeneration = 0

    // Quick-tap toggle (hands-free) state.
    private var pressStartedAt: Date?
    private var toggleLatched = false
    private var ignoreNextRelease = false
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
            // The engine graph is stale once the input device changes
            // (AirPods connected/disconnected) — cancel cleanly.
            self.cancelRecording(message: "Audio device changed — dictation cancelled")
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

        // During onboarding, holding fn must do nothing until the Try-it
        // page — the wizard turns dictation on at that moment.
        if !needsOnboarding {
            installHotkeys()
            installEscMonitor()
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
    }

    // MARK: - Onboarding (backlog 5.2)

    private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(
                onFinish: { [weak self] in self?.completeOnboarding() },
                onReachedPractice: { [weak self] in
                    self?.installHotkeys()
                    self?.installEscMonitor()
                }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to George's Words"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
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
        openMainWindow()
    }

    /// Dock icon clicked (or app re-opened) with no visible windows.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
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
    }

    private func observeSettings() {
        settings.$hotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installHotkeys() }
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

    private func loadModel() async {
        await MainActor.run {
            // A model swap can land mid-recording; don't leave the mic running.
            if case .recording = self.state { _ = self.recorder.stop() }
            self.previewTask?.cancel()
            self.state = .loadingModel
        }
        do {
            try await transcriber.load()
            await MainActor.run {
                // A press may have started a recording while we loaded —
                // don't clobber it; it resolves to .idle on its own.
                if case .loadingModel = self.state { self.state = .idle }
            }
        } catch {
            await MainActor.run { self.state = .error("Model failed to load: \(error.localizedDescription)") }
        }
    }

    // MARK: - Recording

    private func installEscMonitor() {
        if let escMonitorGlobal { NSEvent.removeMonitor(escMonitorGlobal) }
        if let escMonitorLocal { NSEvent.removeMonitor(escMonitorLocal) }
        let handle: (NSEvent) -> Bool = { [weak self] event in
            guard let self, event.keyCode == 53, case .recording = self.state else { return false }
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
        _ = recorder.stop()
        toggleLatched = false
        ignoreNextRelease = false
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

        // Never swallow a press silently — explain why it can't start yet.
        switch state {
        case .idle:
            break
        case .loadingModel:
            // The recorder doesn't need the model. Start capturing now —
            // the Transcriber actor serializes transcribe() behind load(),
            // so the result just arrives a beat later. Without this, the
            // first press after launch got rejected and felt broken.
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
        do {
            try recorder.start()
            SoundFeedback.recordingStarted()
            state = .recording
            recordingGeneration += 1
            scheduleRecordingCap(generation: recordingGeneration)
            if settings.previewEnabled {
                startPreviewLoop()
            }
            // Load the LLM / prime its prompt cache while the user speaks,
            // so the polish pass starts hot.
            if settings.llmEnabled {
                llmFormatter.warmUpIfStale(model: settings.effectiveLLMModel, strength: settings.polishStrength)
            }
        } catch {
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
        previewTask?.cancel()
        let samples = AudioTrim.trimSilence(recorder.stop())
        SoundFeedback.recordingStopped()

        // Ignore accidental taps shorter than ~0.3 s of audio (16 kHz mono).
        guard samples.count > 4800 else {
            state = .idle
            return
        }

        // The dictation belongs to the app it STARTED in; tone and
        // insertion both follow that, not whatever is frontmost later.
        let context = recordingContext ?? AppContext.current()
        recordingContext = nil
        state = .processing

        Task {
            let text = await self.processDictation(samples: samples, context: context)
            await MainActor.run {
                var outcome: TextInserter.Outcome?
                if !text.isEmpty {
                    self.lastTranscript = text
                    self.appStatus.lastTranscript = text
                    HistoryStore.shared.add(text)
                    StatsStore.shared.record(words: text.split(separator: " ").count)
                    if AppContext.current().bundleID == context.bundleID {
                        outcome = self.inserter.insert(text)
                        if outcome == .inserted {
                            self.scheduleCorrectionCheck(inserted: text, context: context)
                        }
                    } else {
                        // Different app frontmost than where dictation
                        // began — never type into the wrong window.
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                        self.pill.flash("You switched apps — dictation copied, press ⌘V to paste it", seconds: 4)
                    }
                }
                // A model swap may have taken over the state meanwhile.
                if case .processing = self.state { self.state = .idle }
                if outcome == .copiedToClipboard { self.flashAccessibilityWarning() }
            }
        }
    }

    // MARK: - Auto-learning dictionary (ADR 0005)

    /// A few seconds after inserting, re-read the focused field and diff it
    /// against what was inserted — the user's quick fixes become dictionary
    /// suggestions. Entirely local, and bails out unless we're clearly still
    /// looking at the same text in the same app.
    private func scheduleCorrectionCheck(inserted: String, context: AppContext) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self else { return }
            // Same app still frontmost, and not mid-dictation.
            guard AppContext.current().bundleID == context.bundleID else { return }
            guard case .idle = self.state else { return }
            guard let fieldText = FocusedFieldReader.read(), !fieldText.isEmpty else { return }
            for substitution in CorrectionDetector.substitutions(from: inserted, to: fieldText) {
                CorrectionStore.shared.add(
                    heard: substitution.heard,
                    corrected: substitution.corrected,
                    settings: self.settings
                )
            }
        }
    }

    /// transcribe → rule cleanup → snippets → (optional) local-LLM polish.
    private func processDictation(samples: [Float], context: AppContext) async -> String {
        let transcribeStart = Date()
        let raw = await transcriber.transcribe(samples)
        let transcribeSeconds = Date().timeIntervalSince(transcribeStart)
        guard !raw.isEmpty else { return "" }

        let dictionary = settings.dictionaryTerms
        var cleaned = cleaner.clean(raw, dictionary: dictionary, replacements: settings.dictionaryReplacements)

        let (expanded, snippetApplied) = SnippetExpander.apply(settings.snippets, to: cleaned)
        cleaned = expanded

        // Skip the LLM when a snippet fired (its expansion must be inserted
        // verbatim), when spoken commands produced explicit line breaks
        // (the polish pass writes single blocks and would flatten them),
        // and for very short utterances (nothing to restructure, and
        // skipping keeps them near-instant).
        let wordCount = cleaned.split(separator: " ").count
        guard settings.llmEnabled, !snippetApplied, !cleaned.contains("\n"), wordCount >= 5 else {
            await updateTiming(transcribe: transcribeSeconds, polish: nil)
            return cleaned
        }

        let polishStart = Date()
        let polished = await llmFormatter.format(
            cleaned,
            tone: context.tone,
            dictionary: dictionary,
            model: settings.effectiveLLMModel,
            strength: settings.polishStrength,
            customInstruction: settings.appInstruction(for: context.bundleID)
        )
        await updateTiming(transcribe: transcribeSeconds, polish: Date().timeIntervalSince(polishStart))
        return polished ?? cleaned
    }

    @MainActor
    private func updateTiming(transcribe: TimeInterval, polish: TimeInterval?) {
        if let polish {
            appStatus.lastTiming = String(format: "Last dictation: %.1f s transcribe + %.1f s polish", transcribe, polish)
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

                // Check length BEFORE copying: a long hands-free recording
                // would otherwise re-copy an ever-growing buffer forever.
                let count = self.recorder.sampleCount
                guard count > 16_000 else { continue }
                // Past 30 s the preview is done for good — stop the loop,
                // don't just skip ticks.
                guard count < 16_000 * 30 else { return }
                let snapshot = self.recorder.snapshot()

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

    private func updateStatusUI() {
        let symbol: String
        let text: String
        switch state {
        case .loadingModel:
            symbol = "hourglass"
            text = "Downloading / loading model…"
        case .idle:
            symbol = "mic"
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
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
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
            pill.hide()
        }
    }

    // MARK: - Actions

    @objc private func pasteLastTranscript() {
        guard let lastTranscript else { return }
        if inserter.insert(lastTranscript) == .copiedToClipboard {
            flashAccessibilityWarning()
        }
    }

    /// The ad-hoc-signing trap: after a rebuild macOS silently invalidates
    /// the Accessibility grant while still showing it enabled. Tell the
    /// user instead of failing silently.
    private func flashAccessibilityWarning() {
        pill.flash("No Accessibility permission — copied to clipboard. Re-toggle GeorgesWords in System Settings → Accessibility.", seconds: 6)
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
        guard !updater.isUpdating else { return }
        // Instant feedback on click — the first background progress message
        // may be a beat away while git starts up.
        updateMenuItem.title = "Checking for updates…"
        updateMenuItem.isEnabled = false
        appStatus.updateProgress = "Checking for updates…"
        updater.checkAndInstall()
    }
}
