import AppKit
import ApplicationServices
import AVFoundation
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

    /// What the current recording is for.
    private enum Mode {
        case dictation
        case command
    }

    private var statusItem: NSStatusItem!
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let modelMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let timingMenuItem = NSMenuItem(title: "Last: —", action: nil, keyEquivalent: "")
    private let statsMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updateMenuItem = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    private let settings = AppSettings.shared
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let cleaner = TranscriptCleaner()
    private let llmFormatter = LLMFormatter()
    private let inserter = TextInserter()
    private let pill = PillController()
    private let updater = Updater()
    private var dictationHotkey: HotkeyMonitor?
    private var commandHotkey: HotkeyMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var previewTask: Task<Void, Never>?

    private var mode: Mode = .dictation
    private var commandSelection: String?
    private var lastTranscript: String?

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        updateStatusUI()

        requestPermissions()

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

        installEscMonitor()

        updater.onProgress = { [weak self] text in
            guard let self else { return }
            if let text {
                self.statusMenuItem.title = text
                // The menu item itself shows the live phase and is disabled
                // so it can't be triggered again mid-run.
                self.updateMenuItem.title = text
                self.updateMenuItem.isEnabled = false
                self.pill.flash(text, seconds: 3)
            } else {
                self.updateMenuItem.title = "Check for Updates…"
                self.updateMenuItem.isEnabled = true
                self.updateStatusUI()
            }
        }
        updater.onNotice = { [weak self] text in
            self?.pill.flash(text, seconds: 4)
        }
        // Confirmation from the new build after a successful self-update.
        if UserDefaults.standard.bool(forKey: "JustUpdated") {
            UserDefaults.standard.set(false, forKey: "JustUpdated")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.pill.flash("George’s Words updated to the latest version ✓", seconds: 4)
            }
        }

        installHotkeys()
        observeSettings()

        Task { await loadModel() }
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
            onPress: { [weak self] in self?.beginRecording(.dictation) },
            onRelease: { [weak self] in self?.endRecording(.dictation) }
        )
        // Command mode is disabled when both features share a key.
        if settings.commandHotkey != settings.hotkey {
            commandHotkey = HotkeyMonitor(
                hotkey: settings.commandHotkey,
                onPress: { [weak self] in self?.beginRecording(.command) },
                onRelease: { [weak self] in self?.endRecording(.command) }
            )
        } else {
            commandHotkey = nil
        }
    }

    private func observeSettings() {
        settings.$hotkey
            .combineLatest(settings.$commandHotkey)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.installHotkeys() }
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
            await MainActor.run { self.state = .idle }
        } catch {
            await MainActor.run { self.state = .error("Model failed to load: \(error.localizedDescription)") }
        }
    }

    // MARK: - Recording

    private func installEscMonitor() {
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
        commandSelection = nil
        state = .idle
        pill.flash(message, seconds: 1.5)
    }

    private func beginRecording(_ mode: Mode) {
        // Second press while latched = the stop signal for toggle mode.
        if toggleLatched, case .recording = state, self.mode == mode {
            toggleLatched = false
            ignoreNextRelease = true
            finishRecording(mode)
            return
        }

        // Never swallow a press silently — explain why it can't start yet.
        switch state {
        case .idle:
            break
        case .loadingModel:
            pill.flash("Speech model is still loading — try again in a moment…", seconds: 2)
            return
        case .processing:
            pill.flash("Finishing the previous dictation…", seconds: 2)
            return
        case .error(let message):
            pill.flash(message, seconds: 4)
            return
        case .recording:
            return
        }

        if mode == .command {
            guard let selection = SelectionReader.read(), !selection.isEmpty else {
                pill.flash("Select some text first, then hold \(settings.commandHotkey.displayName)")
                return
            }
            commandSelection = selection
        }

        self.mode = mode
        pressStartedAt = Date()
        do {
            try recorder.start()
            SoundFeedback.recordingStarted()
            state = .recording
            if mode == .dictation && settings.previewEnabled {
                startPreviewLoop()
            }
            // Load the LLM / prime its prompt cache while the user speaks,
            // so the polish pass starts hot.
            if settings.llmEnabled {
                llmFormatter.warmUpIfStale(model: settings.effectiveLLMModel)
            }
        } catch {
            state = .error("Microphone error: \(error.localizedDescription)")
        }
    }

    /// Hotkey release: either finish, or — for a quick tap — latch into
    /// hands-free toggle mode (tap again to stop).
    private func endRecording(_ mode: Mode) {
        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        guard case .recording = state, self.mode == mode else { return }
        if toggleLatched { return }
        if let pressStartedAt, Date().timeIntervalSince(pressStartedAt) < 0.35 {
            toggleLatched = true
            return
        }
        finishRecording(mode)
    }

    private func finishRecording(_ mode: Mode) {
        guard case .recording = state, self.mode == mode else { return }
        previewTask?.cancel()
        let samples = AudioTrim.trimSilence(recorder.stop())
        SoundFeedback.recordingStopped()

        // Ignore accidental taps shorter than ~0.3 s of audio (16 kHz mono).
        guard samples.count > 4800 else {
            state = .idle
            return
        }

        // Capture the target app now, while it is still frontmost.
        let context = AppContext.current()
        state = .processing

        switch mode {
        case .dictation:
            Task {
                let text = await self.processDictation(samples: samples, context: context)
                await MainActor.run {
                    var outcome: TextInserter.Outcome?
                    if !text.isEmpty {
                        self.lastTranscript = text
                        HistoryStore.shared.add(text)
                        StatsStore.record(words: text.split(separator: " ").count)
                        outcome = self.inserter.insert(text)
                    }
                    // A model swap may have taken over the state meanwhile.
                    if case .processing = self.state { self.state = .idle }
                    if outcome == .copiedToClipboard { self.flashAccessibilityWarning() }
                }
            }
        case .command:
            let selection = commandSelection ?? ""
            commandSelection = nil
            Task {
                let instruction = await self.transcriber.transcribe(samples)
                var edited: String?
                if !instruction.isEmpty && !selection.isEmpty {
                    edited = await self.llmFormatter.applyCommand(instruction, to: selection, model: self.settings.effectiveLLMModel)
                }
                let result = edited
                await MainActor.run {
                    if case .processing = self.state { self.state = .idle }
                    if let result, !result.isEmpty {
                        self.lastTranscript = result
                        HistoryStore.shared.add(result)
                        if self.inserter.insert(result) == .copiedToClipboard {
                            self.flashAccessibilityWarning()
                        }
                    } else {
                        self.pill.flash(instruction.isEmpty
                            ? "Didn't catch that — try again"
                            : "Command mode needs Ollama running")
                    }
                }
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
        var cleaned = cleaner.clean(raw, dictionary: dictionary)

        let (expanded, snippetApplied) = SnippetExpander.apply(settings.snippets, to: cleaned)
        cleaned = expanded

        // Skip the LLM when a snippet fired (its expansion must be inserted
        // verbatim) and for very short utterances (nothing to restructure,
        // and skipping keeps them near-instant).
        let wordCount = cleaned.split(separator: " ").count
        guard settings.llmEnabled, !snippetApplied, wordCount >= 5 else {
            await updateTiming(transcribe: transcribeSeconds, polish: nil)
            return cleaned
        }

        let polishStart = Date()
        let polished = await llmFormatter.format(
            cleaned,
            tone: context.tone,
            dictionary: dictionary,
            model: settings.effectiveLLMModel
        )
        await updateTiming(transcribe: transcribeSeconds, polish: Date().timeIntervalSince(polishStart))
        return polished ?? cleaned
    }

    @MainActor
    private func updateTiming(transcribe: TimeInterval, polish: TimeInterval?) {
        if let polish {
            timingMenuItem.title = String(format: "Last: %.1fs transcribe + %.1fs polish", transcribe, polish)
        } else {
            timingMenuItem.title = String(format: "Last: %.1fs transcribe (no polish)", transcribe)
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

                let snapshot = self.recorder.snapshot()
                // Need at least 1 s of audio; stop previewing past 30 s to
                // keep re-transcription cost bounded.
                guard snapshot.count > 16_000, snapshot.count < 16_000 * 30 else { continue }

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

    // MARK: - Menu bar UI

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        modelMenuItem.isEnabled = false
        menu.addItem(modelMenuItem)

        timingMenuItem.isEnabled = false
        menu.addItem(timingMenuItem)

        statsMenuItem.isEnabled = false
        menu.addItem(statsMenuItem)

        menu.addItem(.separator())

        let pasteLast = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLastTranscript), keyEquivalent: "")
        pasteLast.target = self
        menu.addItem(pasteLast)

        let historyItem = NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: "y")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        updateMenuItem.action = #selector(checkForUpdates)
        updateMenuItem.target = self
        menu.addItem(updateMenuItem)

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
            text = mode == .dictation ? "Recording…" : "Recording command…"
        case .processing:
            symbol = "ellipsis.circle"
            text = mode == .dictation ? "Transcribing…" : "Applying edit…"
        case .error(let message):
            symbol = "exclamationmark.triangle"
            text = message
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        statusMenuItem.title = text
        modelMenuItem.title = "Model: \(settings.engine == .parakeet ? "parakeet-tdt-0.6b-v3" : settings.modelName)"
        statsMenuItem.title = StatsStore.summary

        switch state {
        case .recording:
            pill.show(mode == .dictation ? .listening : .commandListening)
        case .processing:
            pill.show(mode == .dictation ? .transcribing : .commandWorking)
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

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "George's Words Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        guard !updater.isUpdating else { return }
        // Instant feedback on click — the first background progress message
        // may be a beat away while git starts up.
        updateMenuItem.title = "Checking for updates…"
        updateMenuItem.isEnabled = false
        updater.checkAndInstall()
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HistoryView(store: HistoryStore.shared)))
            window.title = "History"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            historyWindow = window
        }
        historyWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }
}
