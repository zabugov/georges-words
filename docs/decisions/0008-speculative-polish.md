# ADR 0008: Speculative polish during pauses

**Date:** 2026-07-07 · **Status:** accepted · **Backlog:** 1.2

## Context

LLM polish adds ~0.5–2 s after key release (ADR 0003). Most dictations
end with the speaker pausing before releasing the key — dead time the
polish could already be using. True streaming polish (backlog 1.3) is a
milestone with hard correctness problems; speculation is the cheap
four-fifths of the win: guess that the pause is the end, polish now,
verify at release.

## Decision

1. **Pause-triggered.** While recording (and LLM polish is on), a loop
   ticks every 0.8 s; when the last ~0.7 s of audio is near-silent (same
   threshold `AudioTrim.trimSilence` uses), transcribe the *full* buffer,
   run it through the identical clean/snippet/eligibility path as the
   final pass, and polish it with identical knobs.
2. **Exact-match cache, never a shortcut.** The guess stores the cleaned
   text plus every polish input (tone, dictionary, model, strength,
   per-app instruction). At key release the final pass recomputes all of
   them; only a field-for-field match uses the cached polish. Keep
   talking after the pause and the guess dies on the equality check —
   speculation can change latency, never output.
3. **Join a near-finished guess.** If the key is released while a
   speculation is still in flight and the final audio is barely longer
   than the speculation's snapshot (≤0.5 s — i.e. the user said nothing
   more), the final pass waits for it instead of duplicating the work.
4. **Bounded cost.** At most one speculation in flight; a pause is only
   re-speculated when its cleaned transcript actually changed; buffers
   over 90 s don't speculate (marathon dictations keep preview only).
   The `Transcriber` actor serializes speculative, preview, and final
   transcriptions, so passes can never interleave inside the model.
5. **No setting for v1.** It rides the existing "AI polish" toggle. If
   the extra mid-recording compute bothers real hardware, add an off
   switch then, not preemptively.

## Consequences

- The win shows in the timing line as "polish done during a pause";
  `debug.log` records guesses and hits (lengths only, per DebugLog
  policy).
- Concurrent LLM requests are safe (the managed engine queues them) but
  a speculative request cannot be aborted once sent (no cancellation in
  `LLMFormatter.chat`); a wasted guess costs some tokens of local
  compute and nothing else.
- A speculation in flight at key release can delay the final transcribe
  behind it on the actor (typically well under a second; bounded by the
  90 s cap).
- Groundwork for 1.3 (true streaming polish): the pause detector,
  full-buffer speculative transcription, and guess/verify plumbing are
  the pieces streaming would build on.
