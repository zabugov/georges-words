# ADR 0011: Personal style matching from writing samples

**Date:** 2026-07-07 · **Status:** accepted · **Backlog:** 3.3

## Context

Full polish matched tone via four generic profiles (ADR 0003: casual /
professional / technical / neutral, chosen by frontmost bundle ID).
Generic adjectives make everyone sound like the same "professional".
Backlog 3.3: learn tone from the user's own writing instead.

## Decision

1. **Samples are pasted, not scraped.** A Settings section holds one
   free-text sample per tone profile — a real chat message for casual,
   a real email for professional. Explicit and visible; the app never
   reads documents or message history to "learn" style (that would
   violate the spirit of NG-2 even though it's all local).
2. **Samples ride the existing tone plumbing.** `styleSample(for:)`
   picks the sample by the dictation's tone profile and the polish
   prompt gains a `VOICE:` block — "match the tone, phrasing, and
   formality of this sample of the user's own writing (imitate its
   voice, never its content)". Same trust level as the dictionary and
   per-app notes; everything stays on-device.
3. **Full polish only.** Light mode preserves the speaker's wording by
   contract (ADR 0003/0006), so voice imitation applies only to full
   rewrites — same rule as the STYLE line and per-app notes.
4. **Bounded.** Samples are trimmed to 700 characters at prompt time so
   a long paste can't slow every dictation; the Settings copy says
   "short sample". Speculative polish (ADR 0008) includes the sample in
   its cache key, so editing a sample mid-recording can't produce a
   stale hit.

## Consequences

- A 1.5b model imitates broad voice (formality, greeting habits,
  emoji-or-not, sentence length) — not a forgery of the user. Larger
  local models sharpen it for free via the model picker.
- Four samples cover the app's whole tone surface; per-app notes remain
  the escape hatch for app-specific quirks.
- Future: 3.5's few-shot bank could turn (raw transcript → user's final
  edit) pairs into per-tone examples, feeding this same mechanism with
  zero new UI.
