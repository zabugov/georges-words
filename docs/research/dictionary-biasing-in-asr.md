# Dictionary biasing inside speech recognition (backlog 2.2)

**Date:** 2026-07-07 · **Question:** can personal-dictionary terms (names,
jargon) be boosted *inside* the Parakeet/FluidAudio engine, so mishearings
are prevented at transcription time instead of patched afterwards?

## TL;DR verdict

**Yes — and the capability already ships in the exact FluidAudio version
the app pins (0.15.4). No dependency bump needed, only wiring.**

FluidAudio includes NVIDIA's published "CTC-based Word Spotter"
context-biasing method (arXiv:2406.07096) ported to Swift/CoreML: a
second, small Parakeet CTC 110M encoder (~97.5 MB one-time download,
~64 MB extra RAM while loaded) scores each dictionary term against the
*audio*, and a rescorer replaces words in the transcript only when the
dictionary term has stronger acoustic evidence than what was decoded.
That is materially better than the app's current text-only fixes
(TranscriptCleaner regex + LLM DICTIONARY hint), which never consult the
audio. FluidAudio's docs claim 99.4% dictionary recall at ~26× real time
for this configuration.

The catch: at 0.15.4 it is not a one-line `AsrManager` config flag — it
is a three-call recipe (transcribe → CTC keyword spot → rescore) the app
must wire itself. FluidAudio's own CLI does exactly this and serves as a
copy-adaptable reference (`Sources/FluidAudioCLI/.../TranscribeCommand.swift`,
~lines 464–527 at tag v0.15.4).

## What the app does today

- FluidAudio pinned `0.15.4..<0.16.0` (`app/Package.swift`), resolved to
  v0.15.4 — which is also the latest release as of this writing.
- `Transcriber.swift` calls `manager.transcribe(samples, decoderState:)`
  with no vocabulary options and consumes only `result.text`; the
  `tokenTimings` the rescorer needs are currently discarded.
- **Correction to the backlog premise:** WhisperKit prompt-token biasing
  is *not* actually implemented for the fallback engine either —
  `whisperKit.transcribe(audioArray:)` passes no `DecodingOptions`. It's
  a known capability, not wired code.
- All current mitigation is post-ASR and text-only: learned
  `heard -> Correct` regex replacements and dictionary spelling
  enforcement in `TranscriptCleaner`, plus a DICTIONARY hint line in the
  LLM polish prompt.

## How FluidAudio's custom vocabulary works (confirmed from source, tag v0.15.4)

Landed in v0.11.0 ("Custom vocabulary support", #251), refined through
v0.15.4. Lives under `Sources/FluidAudio/ASR/.../CustomVocabulary/`,
documented in `Documentation/ASR/CustomVocabulary.md`.

- `CustomVocabularyTerm { text, weight?, aliases?, ctcTokenIds? }` —
  `aliases` maps one-to-one onto our learned `heard -> Correct` pairs
  (ADR 0005): a matched alias emits the canonical spelling, now gated by
  acoustic evidence instead of blind regex.
- `CustomVocabularyContext.loadWithCtcTokens(from:)` builds the vocab and
  downloads/loads the CTC models (HF repo
  `FluidInference/parakeet-ctc-110m-coreml` — same Hugging Face source as
  our existing models, consistent with ADR 0001's local-only posture:
  a model download, never audio/text upload).
- Pipeline: TDT transcribes as usual → `CtcKeywordSpotter` scores every
  term against per-frame CTC log-probs (dynamic programming, the NeMo
  CTC-WS algorithm) → `VocabularyRescorer.ctcTokenRescore` substitutes a
  term only when its acoustic score beats the decoded words, with
  similarity/stopword/short-word guards and vocab-size-aware defaults
  (`ContextBiasingConstants.rescorerConfig(forVocabSize:)`).
- Guidance from the docs: keep the boosted vocab ≤ ~100 terms, terms
  ≥ 3–4 characters, don't boost common words.
- For the future streaming milestone there is a first-class API:
  `SlidingWindowAsrManager.configureVocabularyBoosting(...)`, with
  documented multi-word-term limitations at chunk boundaries.
- **Not decode-loop biasing:** the TDT decode loop has no logit/hotword
  boosting at 0.15.4. True decode-time re-ranking exists only on an
  unmerged upstream branch (`feat/asr-context-boosting-v3`) — watch
  releases.

## Upstream landscape (for context)

1. **CTC-WS context biasing** (arXiv:2406.07096; NeMo
   `scripts/asr_context_biasing/`) — runs *outside* the decoder loop on
   log-prob matrices → fully portable to CoreML, and FluidAudio has
   literally ported it. This is the one that matters.
2. **GPU-PB / TurboBias** (arXiv:2508.07014) — shallow-fusion boosting
   inside the decode loop; conceptually portable (FluidAudio owns its
   Swift decode loop) but today requires the NeMo Python/GPU runtime.
3. **Flashlight/WFST beam-search boosting** — tied to NeMo's Python beam
   decoders; not portable. FluidAudio's TDT decode is greedy — there are
   no n-best lists to rescore, so n-best approaches are out.

## Practical options, ranked (all on-device)

1. **Wire FluidAudio's CTC vocabulary rescoring into the batch path (M)**
   — build terms from `dictionaryTerms` with `dictionaryReplacements` as
   aliases; lazy-download CTC models only when the dictionary is
   non-empty; run spot+rescore after `transcribe`; keep TranscriptCleaner
   as the backstop; log `RescoreOutput.replacements` (counts only) for
   tuning. Cost: one-time 97.5 MB download, ~64 MB RAM while loaded,
   roughly +0.4 s per 10 s of audio.
2. **Post-ASR phonetic correction against the lexicon (S)** — engine-
   agnostic and cheap, but no acoustic evidence → false-positive risk.
   A crude consonant-skeleton version of this now exists in the
   correction *learner* (ADR 0005 amendment); promoting it to silent
   auto-replacement in the dictation path is not recommended while
   option 1 is available.
3. **WhisperKit `DecodingOptions.promptTokens` for the fallback engine
   (S)** — exists in 0.18.0; soft biasing only, disables the prefill KV
   cache (small latency hit), and has a history of empty-result bugs
   (WhisperKit #372) — test before shipping.
4. **Decode-loop TDT boosting** — no action; watch upstream.
5. **Per-user fine-tuning (L)** — rejected: impractical, forgetting risk.

## Recommendation

Implement option 1 behind a "Boost my dictionary words" toggle
(default on when a dictionary exists), with lazy CTC model download and
idle unload to respect memory. Do option 3 alongside for the Whisper
fallback, gated on a local test. Revisit decode-loop boosting if
FluidAudio merges its context-boosting branch.

## Sources (accessed 2026-07-07)

- FluidAudio v0.15.4 source + `Documentation/ASR/CustomVocabulary.md` —
  github.com/FluidInference/FluidAudio (commits `8d3ce44a`, `b9d43724`)
- FluidAudio releases — v0.15.4 (2026-06-16, latest); v0.14.8 "word
  boost improvements"
- Andrusenko et al., *Fast Context-Biasing for CTC and Transducer ASR
  models with CTC-based Word Spotter* — arxiv.org/abs/2406.07096
- NVIDIA NeMo "Word Boosting" user guide — docs.nvidia.com (ASR
  customization)
- *TurboBias: Universal ASR Context-Biasing powered by GPU-accelerated
  Phrase-Boosting Tree* — arxiv.org/abs/2508.07014
- WhisperKit `DecodingOptions` source; issue #372 (promptTokens empty
  results) — github.com/argmaxinc/WhisperKit
