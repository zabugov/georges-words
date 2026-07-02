import AppKit
import ApplicationServices
import AVFoundation

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

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let inserter = TextInserter()
    private var hotkey: HotkeyMonitor?

    private var lastTranscript: String?

    private var state: State = .loadingModel {
        didSet { updateStatusUI() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        updateStatusUI()

        requestPermissions()

        hotkey = HotkeyMonitor(
            onPress: { [weak self] in self?.startDictation() },
            onRelease: { [weak self] in self?.stopDictation() }
        )

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
        // Accessibility: needed to observe the global hotkey and to paste into other apps.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Model

    private func loadModel() async {
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
        state = .transcribing
        Task {
            let text = await transcriber.transcribe(samples)
            await MainActor.run {
                if !text.isEmpty {
                    self.lastTranscript = text
                    self.inserter.insert(text)
                }
                self.state = .idle
            }
        }
    }

    // MARK: - Menu bar UI

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let modelItem = NSMenuItem(title: "Model: \(transcriber.modelName)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        menu.addItem(.separator())

        let pasteLast = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLastTranscript), keyEquivalent: "")
        pasteLast.target = self
        menu.addItem(pasteLast)

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
            text = "Ready — hold Fn and speak"
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
    }

    @objc private func pasteLastTranscript() {
        guard let lastTranscript else { return }
        inserter.insert(lastTranscript)
    }
}
