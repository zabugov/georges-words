# ADR 0005: Auto-learning dictionary

**Date:** 2026-07-03 · **Status:** accepted · **Amended:** 2026-07-07 (backlog 2.5, see below)

## Context

Backlog item 2.3: misheard words ("coober netties") should come out right
("Kubernetes") the next time. The hard part is that the app inserts text
into *other* apps and then loses sight of it — there is no callback when
the user fixes a word. Commercial apps solve this class of problem with cloud
context; we can't and won't (ADR 0001).

A second gap surfaced during design: the personal dictionary only
*enforced spelling* of words the STT already got right-ish. Adding
"Kubernetes" to it could never fix "coober netties" — a mishearing needs
a **replacement mapping**, not a spelling.

## Decision

1. **Dictionary syntax grows mappings.** A dictionary line can now be
   `heard -> Correct` (also `→`). Mappings are applied case-insensitively
   on word boundaries in the rule-based pass (stage 1, deterministic,
   before LLM polish). Plain lines behave exactly as before; the correct
   side of each mapping also joins the spelling-enforcement/LLM term list.

2. **Corrections are observed by re-reading the field.** After a
   successful insertion, wait ~6 s, then — only if the same app is still
   frontmost and no new dictation is running — read the focused element's
   `AXValue` and word-align it (LCS) against what was inserted.
   Replaced word runs become candidates when they pass filters:
   - 1–3 words on each side, not case-only, correction contains a letter;
   - correction isn't made only of stopwords (wording edits aren't mishearings);
   - normalized Levenshtein similarity ≥ 0.35 (mishearings *resemble*
     the fix; rewrites don't);
   - ≥ 60% of inserted words still present, else learn nothing at all.

3. **Suggestions, never auto-add.** Candidates go to a local queue
   (Application Support, capped at 50) shown in the Dictionary tab:
   one click accepts (appends the `heard -> Correct` line), one click
   dismisses (remembered, never re-suggested). Auto-adding risks
   learning garbage from ordinary editing.

4. **Manual fallback.** Where AX reads fail (some Electron apps, secure
   fields), a "Correct Last Transcript…" action opens the Dictionary tab
   with the last transcript in an editor; the user fixes it and the same
   diff/filter pipeline learns from that.

Everything is local: field reads use the Accessibility permission the
app already holds for insertion, and nothing observed ever leaves the
device (ADR 0001).

## Consequences

- The field re-read sees whatever is around the insertion (e.g. the rest
  of a draft email). It is used transiently for the diff and discarded —
  same trust level as the insertion path itself — but it is a read we
  didn't do before; worth stating plainly here.
- Case-only fixes ("george" → "George") are skipped in v1 to avoid
  learning sentence-start capitalization noise; add via a plain
  dictionary line instead.
- The 6 s window misses corrections made later; the manual fallback and
  repeat occurrences (a `×N` counter on suggestions) cover the gap.
- Backlog 2.2 (feeding dictionary terms to the STT model as a decoding
  prompt) remains open and complements this: 2.3 fixes text after the
  fact, 2.2 would prevent the mishearing at the source.

## Amendment — 2026-07-07 (backlog 2.5)

Detection missed too many real corrections in daily use. Five changes,
same design shape (observe → suggest → human click; nothing auto-added):

1. **Widening re-read schedule.** The single fixed 6 s peek missed every
   fix made after it (mouse round-trip, re-reading the sentence). The
   check now peeks at ~6 s, ~20 s and ~60 s; a newer dictation's check
   retires any still-pending attempts, and the same fix seen by two
   peeks counts once.
2. **Exact-element tracking.** AX insertions remember the precise
   `AXUIElement` written into and later re-read *it* — the 2.5 suspect
   "validating only the frontmost app instead of the exact edited field."
   Paste-fallback insertions capture the focused element ~1 s after the
   paste lands. Reading the tracked element no longer requires the app
   to be frontmost (it targets the exact field we wrote — a stronger
   check than bundle ID); the focus-based fallback still does.
3. **Phonetic second chance.** Sound-alike fixes spelled differently
   ("quay" → "key") failed the 0.35 letter-similarity gate. Candidates
   that fail it are re-scored on crude consonant skeletons (≥ 0.5 to
   pass). Cost of a wrong grant is one dismissable suggestion.
4. **Strict mode for short dictations.** Fixing two words of four fails
   the 60% survival gate by arithmetic, not by intent. Texts ≤ 12 words
   under the gate now learn — but only a single candidate at ≥ 0.55
   similarity; several "fixes" in barely-surviving text is a rewrite.
5. **Captures are no longer silent.** The pill flashes a 3 s notice
   right after a fix is noticed. Every skipped/failed re-read now writes
   a stage-and-lengths-only line to debug.log (transcript text stays
   out, per DebugLog policy), so "it never learns" reports become
   diagnosable. (A sidebar badge was tried too, but `.badge()` on the
   sidebar rows froze sidebar selection on macOS and was reverted the
   same day — re-add a cue only off the row hit-testing path.)
