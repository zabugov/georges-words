import Foundation
import WhisperKit
#if PARAKEET
import FluidAudio
#endif

/// On-device speech-to-text with a choice of engines:
///
/// - **Parakeet** (NVIDIA parakeet-tdt-0.6b-v3 via FluidAudio, CoreML/ANE):
///   dramatically faster, top of the Open ASR Leaderboard; English + 24
///   European languages + Japanese. Compiled in only when the app is built
///   with `GW_PARAKEET=1` (its C/C++ deps don't build on every SDK).
/// - **Whisper** (via WhisperKit, CoreML/ANE): the battle-tested default,
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
        #if PARAKEET
        case parakeet(AsrManager)
        #endif
    }

    private var backend: Backend?
    private var loadTask: Task<Void, Error>?

    nonisolated var modelName: String { AppSettings.shared.modelName }

    func load() async throws {
        backend = nil
        let task = Task { try await self.performLoad() }
        loadTask = task
        try await task.value
    }

    private func performLoad() async throws {
        let start = Date()
        #if PARAKEET
        if AppSettings.shared.engine == .parakeet {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            backend = .parakeet(manager)
            await warmUp()
            DebugLog.log(String(format: "Model load: parakeet ready in %.1fs (incl. warm-up)", -start.timeIntervalSinceNow))
            return
        }
        #endif
        backend = .whisper(try await WhisperKit(WhisperKitConfig(model: modelName)))
        await warmUp()
        DebugLog.log(String(format: "Model load: whisper ready in %.1fs (incl. warm-up)", -start.timeIntervalSinceNow))
    }

    func transcribe(_ samples: [Float]) async -> String {
        // Actors are REENTRANT at await points: while load() is suspended
        // (downloading/compiling the model), a call used to slip in here,
        // see a nil backend, and silently return "" — the "first fn press
        // after launch does nothing" bug. Wait for the load instead; the
        // recording that queued during it then transcribes normally.
        if backend == nil, let loadTask {
            DebugLog.log("Transcribe requested mid-load — waiting for the model")
            try? await loadTask.value
        }
        guard let backend else {
            DebugLog.log("Transcribe: no backend after load — returning empty")
            return ""
        }
        do {
            switch backend {
            case .whisper(let whisperKit):
                let results = try await whisperKit.transcribe(audioArray: samples)
                return tidy(results.map(\.text).joined(separator: " "))
            #if PARAKEET
            case .parakeet(let manager):
                // Fresh decoder state per utterance (state persistence
                // across calls is only for streaming chunk mode).
                var decoderState = TdtDecoderState.make()
                let result = try await manager.transcribe(samples, decoderState: &decoderState)
                return tidy(result.text)
            #endif
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

    // Dictionary boosting (2.2) — the CTC word-spotter rescore — was
    // removed 2026-07-22 (owner decision: it swapped unknown proper
    // names for dictionary terms; simplify before sharing). Restore
    // from git history if re-attempted; the research doc and the QA
    // §11 re-entry gate still stand.

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
