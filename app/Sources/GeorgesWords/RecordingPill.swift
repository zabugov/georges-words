import AppKit
import SwiftUI

/// The floating "pill" shown near the bottom of the screen while dictating —
/// a non-activating panel so it never steals focus from the app being
/// dictated into.
final class PillController {

    enum Phase: Equatable {
        case listening
        case commandListening
        case transcribing
        case commandWorking
        case message(String)
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
        if phase != .listening && phase != .commandListening {
            model.level = 0
        }
        if phase == .listening || phase == .commandListening {
            model.previewText = ""
        }
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        model.level = 0
        model.previewText = ""
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

    private func position() {
        guard let screen = NSScreen.main else { return }
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
            case .listening, .commandListening:
                LevelBars(level: model.level, color: model.phase == .listening ? .red : .purple)
                if model.previewText.isEmpty {
                    Text(model.phase == .listening ? "Listening…" : "Command…")
                } else {
                    Text(model.previewText)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: 280)
                }
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Polishing…")
            case .commandWorking:
                ProgressView().controlSize(.small)
                Text("Editing…")
            case .message(let text):
                Image(systemName: "info.circle")
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .frame(maxWidth: 360)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
