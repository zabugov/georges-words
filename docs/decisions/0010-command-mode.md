# ADR 0010: Command mode — free-form edit instructions

**Date:** 2026-07-07 · **Status:** accepted · **Backlog:** 4.4 (touches 4.5, 5.5, 3.7)

## Context

Backlog 4.4: the original command mode was retired because it shared
dictation's hotkey/latch state machine and the two kept corrupting each
other. The open question was what a rebuilt one should even parse —
a fixed grammar ("delete last word", "undo that") is brittle to speech
recognition errors and caps what users can ask for.

Owner's direction (2026-07-07): don't build a grammar at all. Commands
are **free-form instructions applied by the local LLM** — "make it more
formal", "remove the word actually", "translate to French" — the way
the commercial dictation tools' command modes behave.

## Decision

1. **A second hotkey, hold-only.** `CommandModeController` (new file)
   is its own three-state machine (idle → listening → processing),
   fully separate from dictation's hold/latch logic. No quick-tap
   latch, no preview, Esc cancels. **On by default with Right Option
   (⌥)** since 2026-07-07; a Settings dropdown offers other comfortable
   hold keys (Right ⌘, Right ⌃) and the dictation key is refused — one
   key, one job. Turning it off is remembered across launches (a
   separate flag) so the default-on doesn't re-enable it.
2. **The target is the last insertion.** Hold, speak the instruction,
   release: the instruction is transcribed and applied to the last
   inserted text via a dedicated LLM prompt (separate from polish —
   this pass *transforms* text because the user asked, which polish
   must never do on its own). The result replaces the previous text in
   place via select-and-replace on the exact field element tracked at
   insertion time (ADR 0005 amendment machinery); if the field refuses
   or the text is gone, the result lands on the clipboard with a ⌘V
   prompt instead. Never type into the unknown.
3. **Edits chain.** A successful command's output becomes the new
   "last dictation" (and a history entry), so "make it formal" …
   "now translate it" composes.
4. **Guards.** The microphone is single-owner: commands refuse to start
   while dictation is active and vice versa. Commands require AI polish
   to be enabled (they are LLM-only), refuse secure input, and no-op on
   an empty or unchanged result with a "try rephrasing" hint.
5. **Sanity bounds, not fidelity bounds.** Polish's keeps-wording check
   would reject translations by design; the edit pass only rejects
   empty output and runaway generation (> 3× input + 400 chars).

## Consequences

- Quality is bounded by the local model (qwen2.5:1.5b default):
  formality shifts and word removals are reliable; translation is
  serviceable, not professional. The prompt is few-shot seeded and easy
  to grow (3.5's example-bank idea applies here too).
- `TextInserter.replaceLastInsertion` is exactly the machinery backlog
  5.5 (Undo Last Insertion) and 3.7 ("use raw instead") need — both are
  now S-effort UI wiring.
- Backlog 4.5's fixed command list is partially superseded: deletion /
  rewording / restructuring are free-form instructions now. Still open
  from 4.5: literal mode and spoken punctuation *during* dictation.
- The old command-mode code in git history stays retired; nothing was
  salvaged because the instruction-based design shares no surface with
  a grammar parser.
