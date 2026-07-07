# ADR 0012: True streaming polish — design (implementation gated on ADR 0008 verification)

**Date:** 2026-07-07 · **Status:** proposed — implement only after speculative polish (ADR 0008) is verified on-device · **Backlog:** 1.3

## Context

Speculative polish (ADR 0008) re-polishes the *whole* transcript at
every pause. That's simple and correct, but the cost grows with
dictation length — hence its 90 s cap, above which long dictations get
no speculation at all. Backlog 1.3 wants polish to keep up with speech
indefinitely: sentence-by-sentence, while speaking.

The known hard cases (from the backlog): self-corrections that span
sentence boundaries ("…on Tuesday. No wait, Friday."), tone consistency
across independently polished chunks, and segmentation on unstable ASR
output (the transcript of the same audio can change between passes).

## Decision (design)

**Streaming polish = incremental speculation.** Keep ADR 0008's
pause-triggered loop, guess/verify cache, and exact-match correctness
contract; change only what gets polished at each pause:

1. **Segment on the transcript, not the audio.** After each pause's
   full-buffer transcription, split the cleaned text into sentences
   (`NLTokenizer`, sentence granularity — on-device, language-aware).
   Audio-level segmentation was rejected: Parakeet may re-transcribe
   earlier audio differently between passes, so only text is stable
   enough to anchor cache entries.
2. **Commit lag of 2 sentences.** Sentences more than 2 boundaries
   behind the live edge are *committed*: polished once (with full
   left context in the prompt), cached by their cleaned text, never
   re-polished. The trailing window (last ≤2 sentences + partial) is
   re-polished at every pause. Self-corrections overwhelmingly target
   the immediately preceding clause; a 2-sentence repair window covers
   them while keeping per-pause cost O(window), not O(dictation).
3. **Stability check before committing.** A sentence is only committed
   when two consecutive passes transcribed it identically (the ASR
   instability defense). Unstable text stays in the re-polish window.
4. **Tone consistency by shared context.** Every window polish includes
   the last ~2 committed *polished* sentences as read-only context
   ("continue in the same voice; do not repeat or modify this part"),
   so chunk boundaries don't reset the voice. The prompt prefix stays
   byte-identical for the engine's KV cache; context rides in the user
   message like the VOICE/DICTIONARY blocks (ADR 0011/0003).
5. **Final pass = stitch + verify, with the whole-text fallback.** On
   key release: final transcription → if its committed prefix matches
   the cache and only the tail is new, polish the tail and stitch —
   latency stays flat however long the dictation ran. Any mismatch
   (ASR changed committed text, segmentation moved) falls back to
   exactly today's behavior: one whole-text polish, or the raw cleaned
   text (fail open, ADR 0003). Streaming can change latency, never
   correctness — same contract as ADR 0008.
6. **Rollout gate.** Implement only after 1.2's on-device verification
   (hit rate and CPU feel), since this design reuses its loop, cache,
   and pause detector wholesale. The 90 s speculation cap is then
   replaced by the window mechanism (commit lag makes long dictations
   cheap), and ADR 0008's cap note is superseded.

## Rejected alternatives

- **Polish-as-you-go insertion** (typing polished text into the field
  while speaking): retracting already-inserted text on self-correction
  would fight the target app's undo stack and cursor; insertion stays
  single-shot at key release.
- **Token-level streaming from the LLM**: the engine streams fine, but
  partial LLM output can't be verified by the isSane/keepsWording
  gates until complete; no benefit while insertion is single-shot.
- **Audio-anchored chunk cache**: rejected per §1 (transcript
  instability).

## Consequences

- Worst-case latency equals today's (fallback path); best case is flat
  ~1-window polish regardless of length.
- The committed-prefix cache makes polish quality *path-dependent* (an
  early sentence polished without knowing what follows) — acceptable:
  human typists also can't revise sentence 1 while saying sentence 9,
  and the 2-sentence repair window covers local self-corrections.
- Adds the first NaturalLanguage-framework dependency (NLTokenizer);
  on-device, no new privacy surface.
