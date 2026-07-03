import AppKit
import SwiftUI

/// The floating "pill" shown near the bottom of the screen while dictating —
/// a non-activating panel so it never steals focus from the app being
/// dictated into.
final class PillController {

    enum Phase {
        case listening
        case transcribing
    }

    final class Model: ObservableObject {
        @Published var phase: Phase = .listening
        @Published var level: Float = 0
    }

    private let panel: NSPanel
    private let model = Model()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
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
        if phase == .transcribing { model.level = 0 }
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        model.level = 0
    }

    func updateLevel(_ level: Float) {
        model.level = level
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
            case .listening:
                LevelBars(level: model.level)
                Text("Listening…")
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                Text("Polishing…")
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

    // Each bar responds to the level a little differently so the meter
    // looks alive rather than mechanical.
    private let sensitivities: [CGFloat] = [0.6, 1.0, 1.4, 1.0, 0.6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
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
