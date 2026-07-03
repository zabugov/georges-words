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
        case transcribing
        case error(String)
    }

    private var statusItem: NSStatusItem!
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let modelMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var settingsWindow: NSWindow?

    private let settings = AppSettings.shared
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let cleaner = TranscriptCleaner()
    private let llmFormatter = LLMFormatter()
    private let inserter = TextInserter()
    private let pill = PillController()
    private var hotkey: HotkeyMonitor?
    private var cancellables = Set<AnyCancellable>()

    private var lastTranscript: String?

    private var state: State = .loadingModel {
        didSet { updateStatusUI() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        updateStatusUI()

        requestPermissions()

        recorder.onLevel = { [weak self] level in
            self?.pill.updateLevel(level)
        }

        installHotkey()
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
        // Accessibility: needed to observe the global hotkey and insert text.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Settings wiring

    private func installHotkey() {
        hotkey = HotkeyMonitor(
            hotkey: settings.hotkey,
            onPress: { [weak self] in self?.startDictation() },
            onRelease: { [weak self] in self?.stopDictation() }
        )
    }

    private func observeSettings() {
        settings.$hotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installHotkey() }
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
    }

    // MARK: - Model

    private func loadModel() async {
        await MainActor.run {
            // A model swap can land mid-recording; don't leave the mic running.
            if case .recording = self.state { _ = self.recorder.stop() }
            self.state = .loadingModel
        }
        do {
            try await transcriber.load()
            await MainActor.run { self.state = .idle }
        } catch {
            await MainActor.run { self.state = .error("Model failed to load: \(error.localizedDescription)") }
        }
    }

    // MARK: - Dictation flow

    private func startDictation() {
        guard case .idle = state else { return }
        do {
            try recorder.start()
            state = .recording
        } catch {
            state = .error("Microphone error: \(error.localizedDescription)")
        }
    }

    private func stopDictation() {
        guard case .recording = state else { return }
        let samples = recorder.stop()
        // Ignore accidental taps shorter than ~0.3 s of audio (16 kHz mono).
        guard samples.count > 4800 else {
            state = .idle
            return
        }
        // Capture the target app now, while it is still frontmost.
        let context = AppContext.current()
        state = .transcribing
        Task {
            let text = await self.processTranscript(samples: samples, context: context)
            await MainActor.run {
                if !text.isEmpty {
                    self.lastTranscript = text
                    self.inserter.insert(text)
                }
                // A model swap may have taken over the state meanwhile.
                if case .transcribing = self.state { self.state = .idle }
            }
        }
    }

    /// transcribe → rule cleanup → (optional) local-LLM polish.
    private func processTranscript(samples: [Float], context: AppContext) async -> String {
        let raw = await transcriber.transcribe(samples)
        guard !raw.isEmpty else { return "" }

        let dictionary = settings.dictionaryTerms
        let cleaned = cleaner.clean(raw, dictionary: dictionary)

        // Very short utterances don't need a rewrite, and skipping the LLM
        // keeps them near-instant.
        let wordCount = cleaned.split(separator: " ").count
        guard settings.llmEnabled, wordCount >= 5 else { return cleaned }

        if let polished = await llmFormatter.format(
            cleaned,
            tone: context.tone,
            dictionary: dictionary,
            model: settings.llmModel
        ) {
            return polished
        }
        return cleaned
    }

    // MARK: - Menu bar UI

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        modelMenuItem.isEnabled = false
        menu.addItem(modelMenuItem)

        menu.addItem(.separator())

        let pasteLast = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLastTranscript), keyEquivalent: "")
        pasteLast.target = self
        menu.addItem(pasteLast)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
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
        case .transcribing:
            symbol = "ellipsis.circle"
            text = "Transcribing…"
        case .error(let message):
            symbol = "exclamationmark.triangle"
            text = message
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        statusMenuItem.title = text
        modelMenuItem.title = "Model: \(settings.modelName)"

        switch state {
        case .recording: pill.show(.listening)
        case .transcribing: pill.show(.transcribing)
        default: pill.hide()
        }
    }

    // MARK: - Actions

    @objc private func pasteLastTranscript() {
        guard let lastTranscript else { return }
        inserter.insert(lastTranscript)
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
}
