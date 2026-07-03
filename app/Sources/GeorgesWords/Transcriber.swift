import Foundation
import WhisperKit

/// On-device speech-to-text via WhisperKit (CoreML / Neural Engine).
///
/// The model is downloaded once from Hugging Face on first launch and cached
/// locally; transcription itself is always fully offline.
///
/// An actor so calls serialize: the live-preview loop and the final
/// transcription can never run through the model concurrently.
actor Transcriber {

    private var whisperKit: WhisperKit?

    nonisolated var modelName: String { AppSettings.shared.modelName }

    func load() async throws {
        whisperKit = nil
        whisperKit = try await WhisperKit(WhisperKitConfig(model: modelName))
    }

    func transcribe(_ samples: [Float]) async -> String {
        guard let whisperKit else { return "" }
        do {
            let results = try await whisperKit.transcribe(audioArray: samples)
            let text = results.map(\.text).joined(separator: " ")
            return tidy(text)
        } catch {
            NSLog("Transcription failed: \(error.localizedDescription)")
            return ""
        }
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
