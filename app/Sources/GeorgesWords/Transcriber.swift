import Foundation
import FluidAudio
import WhisperKit

/// On-device speech-to-text with a choice of engines:
///
/// - **Parakeet** (NVIDIA parakeet-tdt-0.6b-v3 via FluidAudio, CoreML/ANE):
///   dramatically faster, top of the Open ASR Leaderboard; English + 24
///   European languages + Japanese.
/// - **Whisper** (via WhisperKit, CoreML/ANE): the battle-tested fallback,
///   with model-size choices.
///
/// Models are downloaded once from Hugging Face on first use and cached
/// locally; transcription itself is always fully offline.
///
/// An actor so calls serialize: the live-preview loop and the final
/// transcription can never run through the model concurrently.
actor Transcriber {

    private enum Backend {
        case whisper(WhisperKit)
        case parakeet(AsrManager)
    }

    private var backend: Backend?

    nonisolated var modelName: String { AppSettings.shared.modelName }

    func load() async throws {
        backend = nil
        switch AppSettings.shared.engine {
        case .parakeet:
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            backend = .parakeet(manager)
        case .whisper:
            backend = .whisper(try await WhisperKit(WhisperKitConfig(model: modelName)))
        }
        await warmUp()
    }

    func transcribe(_ samples: [Float]) async -> String {
        guard let backend else { return "" }
        do {
            switch backend {
            case .whisper(let whisperKit):
                let results = try await whisperKit.transcribe(audioArray: samples)
                return tidy(results.map(\.text).joined(separator: " "))
            case .parakeet(let manager):
                let result = try await manager.transcribe(samples)
                return tidy(result.text)
            }
        } catch {
            NSLog("Transcription failed: \(error.localizedDescription)")
            return ""
        }
    }

    /// Run one second of silence through the model right after loading, so
    /// the first real dictation doesn't pay the Neural Engine's one-time
    /// pipeline-compilation cost.
    private func warmUp() async {
        _ = await transcribe([Float](repeating: 0, count: 16_000))
    }

    /// Strip Whisper artifacts: special tokens like <|startoftranscript|> and
    /// non-speech markers like [BLANK_AUDIO] or (music).
    private func tidy(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[[A-Za-z_ ]+\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\([A-Za-z_ ]+\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
