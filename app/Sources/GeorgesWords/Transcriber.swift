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

    /// `boost` opts this pass into dictionary boosting (2.2) — the final
    /// and speculative passes use it; the live preview never does (it
    /// would pay the CTC cost every 1.2 s for throwaway text).
    func transcribe(_ samples: [Float], boost: Bool = false) async -> String {
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
                var text = result.text
                if boost, AppSettings.shared.dictionaryBoostEnabled,
                   let boosted = await boostAgainstDictionary(result: result, samples: samples) {
                    text = boosted
                }
                return tidy(text)
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

    #if PARAKEET
    // MARK: - Dictionary boosting (backlog 2.2, opt-in)
    //
    // A second, small Parakeet CTC model scores each dictionary term
    // against the AUDIO, and the transcript is rescored only where a
    // term has stronger acoustic evidence than what was decoded —
    // NVIDIA's CTC word-spotter method, shipped inside FluidAudio.
    // Every failure path returns nil: boosting can improve a transcript
    // but can never lose a dictation (same contract as LLM polish).

    private var boostSpotter: CtcKeywordSpotter?
    private var boostRescorer: VocabularyRescorer?
    private var boostVocabulary: CustomVocabularyContext?
    /// Which dictionary the loaded pipeline was built for.
    private var boostKey: String?

    private func boostAgainstDictionary(result: ASRResult, samples: [Float]) async -> String? {
        // Docs guidance: boost works best on a modest list of real
        // words — 3+ characters, at most ~100 terms.
        let terms = AppSettings.shared.dictionaryTerms
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 }
        guard !terms.isEmpty, terms.count <= 100 else { return nil }
        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else { return nil }

        do {
            let key = terms.joined(separator: "\u{1F}")
            if key != boostKey || boostSpotter == nil || boostRescorer == nil || boostVocabulary == nil {
                // loadWithCtcTokens reads one term per line and fetches
                // the CTC model on first use (~100 MB, cached locally).
                let vocabFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("gw-boost-vocab.txt")
                try terms.joined(separator: "\n").write(to: vocabFile, atomically: true, encoding: .utf8)
                let (vocabulary, models) = try await CustomVocabularyContext.loadWithCtcTokens(from: vocabFile.path)
                let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
                let rescorer = try await VocabularyRescorer.create(
                    spotter: spotter,
                    vocabulary: vocabulary,
                    config: .default,
                    ctcModelDirectory: CtcModels.defaultCacheDirectory(for: models.variant)
                )
                boostVocabulary = vocabulary
                boostSpotter = spotter
                boostRescorer = rescorer
                boostKey = key
                DebugLog.log("Dictionary boost: pipeline ready (\(terms.count) terms)")
            }
            guard let boostSpotter, let boostRescorer, let boostVocabulary else { return nil }

            let spot = try await boostSpotter.spotKeywordsWithLogProbs(
                audioSamples: samples,
                customVocabulary: boostVocabulary,
                minScore: nil
            )
            guard !spot.logProbs.isEmpty else { return nil }
            let output = boostRescorer.ctcTokenRescore(
                transcript: result.text,
                tokenTimings: tokenTimings,
                logProbs: spot.logProbs,
                frameDuration: spot.frameDuration,
                // cbw 3.0 = weight of the dictionary's vote. The
                // similarity floor was raised 0.52 → 0.70 after on-device
                // testing (2026-07-22): at 0.52, short name terms were
                // swapped into words that sounded nothing like them.
                cbw: 3.0,
                marginSeconds: ContextBiasingConstants.defaultMarginSeconds,
                minSimilarity: 0.70
            )
            guard output.wasModified else { return nil }
            // The hard guarantee: boosting exists to fix the OCCASIONAL
            // misheard name. A rescore that touches more than ~1 word in 8
            // (min 2) is misfiring — seen live: "Zachary" sprayed across a
            // whole sentence — so distrust the entire rescore, not just
            // the excess.
            let wordCount = result.text.split(separator: " ").count
            let cap = max(2, wordCount / 8)
            guard output.replacements.count <= cap else {
                DebugLog.log("Dictionary boost: rejected — \(output.replacements.count) replacement(s) on \(wordCount) words (cap \(cap))")
                return nil
            }
            DebugLog.log("Dictionary boost: \(output.replacements.count) replacement(s)")
            return output.text
        } catch {
            DebugLog.log("Dictionary boost failed (transcript kept as-is): \(error.localizedDescription)")
            // Clear so the next dictation rebuilds from scratch — a
            // transient failure (e.g. the first model download without
            // network) shouldn't wedge boosting forever.
            boostKey = nil
            boostSpotter = nil
            boostRescorer = nil
            boostVocabulary = nil
            return nil
        }
    }
    #endif

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
