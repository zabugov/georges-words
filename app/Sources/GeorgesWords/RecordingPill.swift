import AppKit
import SwiftUI

/// The floating "pill" shown near the bottom of the screen while dictating —
/// a non-activating panel so it never steals focus from the app being
/// dictated into.
final class PillController {

    enum Phase: Equatable {
        case listening
        case transcribing
        case message(String)
        /// High-visibility variant for "your text did NOT land where you
        /// were typing" — the one message that must not be missed.
        case alert(String)
    }

    final class Model: ObservableObject {
        @Published var phase: Phase = .listening
        @Published var level: Float = 0
        @Published var previewText: String = ""
    }

    private let panel: NSPanel
    private let model = Model()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PillView(model: model))
    }

    func show(_ phase: Phase) {
        model.phase = phase
        if phase != .listening {
            model.level = 0
        }
        if phase == .listening {
            model.previewText = ""
        }
        position()

        if panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        model.level = 0
        model.previewText = ""
        guard panel.isVisible else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            })
        }
    }

    /// A message/alert flash is on screen. Status updates must not hide
    /// the pill while this is true — the flash's own timer will.
    var isFlashing: Bool {
        guard panel.isVisible else { return false }
        switch model.phase {
        case .message, .alert: return true
        default: return false
        }
    }

    func updateLevel(_ level: Float) {
        model.level = level
    }

    /// Live partial transcript while recording.
    func updatePreview(_ text: String) {
        model.previewText = text
    }

    /// Show a short informational message, then hide.
    func flash(_ text: String, seconds: TimeInterval = 2.5) {
        show(.message(text))
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, case .message = self.model.phase else { return }
            self.hide()
        }
    }

    /// Can't-miss warning: orange, larger, longer, with a sound. Used when
    /// the dictation went to the clipboard instead of the app — the user
    /// is mid-flow and easily misses the ordinary pill.
    func flashAlert(_ text: String, seconds: TimeInterval = 7) {
        if AppSettings.shared.soundsEnabled {
            NSSound(named: "Glass")?.play()
        }
        show(.alert(text))
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, case .alert = self.model.phase else { return }
            self.hide()
        }
    }

    private func position() {
        // Follow the display the user is working on (where the mouse is),
        // not just the primary screen.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 60
        ))
    }
}

private struct PillView: View {
    @ObservedObject var model: PillController.Model

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .listening:
                LevelBars(level: model.level, color: .red)
                if model.previewText.isEmpty {
                    Text("Listening…")
                } else {
                    Text(model.previewText)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: 280)
                }
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Polishing…")
            case .message(let text):
                Image(systemName: "info.circle")
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .frame(maxWidth: 360)
            case .alert(let text):
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: 380)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, isAlert ? 14 : 10)
        .background(Capsule().fill(isAlert ? Color.orange.opacity(0.95) : Color.black.opacity(0.82)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isAlert: Bool {
        if case .alert = model.phase { return true }
        return false
    }
}

/// Five bars that dance with the microphone level.
private struct LevelBars: View {
    let level: Float
    var color: Color = .red

    // Each bar responds to the level a little differently so the meter
    // looks alive rather than mechanical.
    private let sensitivities: [CGFloat] = [0.6, 1.0, 1.4, 1.0, 0.6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: barHeight(index))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
        .frame(height: 18)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let base: CGFloat = 4
        let range: CGFloat = 14
        return base + min(range, CGFloat(level) * range * sensitivities[index])
    }
}
