# Basic QA checklist — 2026-07-07 batch

Walk this top to bottom after building the checkout copy
(`app/build.sh` → open `app/build/GeorgesWords.app`). Every test says
what to do and exactly what you should see. Tick items off; anything
that misbehaves, note it and keep going. When a test passes, its
backlog item can be retired from `FUTURE_IMPROVEMENTS.md`.

Where a test says **debug.log**, that's
`~/Library/Application Support/GeorgesWords/debug.log` — open it with
Console or TextEdit; newest lines are at the bottom.

## Setup (2 min)

- [ ] Build and launch. The menu-bar mic icon appears; Home says "Ready".
- [ ] Settings → Hotkeys → confirm **"Hold for a voice command"** already shows **Right ⌥** (on by default). The **Presets** dropdown offers Right ⌘ / Right ⌃; **Turn Off** disables it.
- [ ] Settings → add two dictionary lines for later: a name you use
      (e.g. `Kubernetes`) and anything else ≥3 letters.

## 1. Dictation still works (the don't-break-anything test)

- [ ] Hold fn in Notes, speak a sentence, release → polished text appears at the cursor.
- [ ] Quick-tap fn → hands-free mode latches; tap again to stop → text inserts.
- [ ] Esc mid-recording cancels with a "Cancelled" flash.
- [ ] (Added 2026-07-15) Dictate "call me at five five five one two three four" → `555-1234`; "john dot smith at gmail dot com" → `john.smith@gmail.com`; "one hundred twenty three dollars" → `123`-style digits.
- [ ] (Added 2026-07-22) With just your full name as a plain dictionary line (no `->` mappings needed), dictate "hi my name is …" several times → the surname comes out spelled right every time, even though the recognizer mishears it differently each time. Also dictate a couple of name-free sentences → no name appears where you didn't say it.

## 2. Speculative polish (1.2)

- [ ] Dictate a sentence or two, **pause silently ~3 seconds**, then release.
- [ ] Home's timing line reads **"… + polish done during a pause"**.
- [ ] Now dictate, pause 3 s, then *keep talking* and release — output is complete and correct (the stale guess was discarded).

## 3. Correction learning (2.5)

- [ ] Dictate a sentence containing a made-up-sounding word into Notes.
- [ ] Within ~15 s, hand-edit one word to something similar (e.g. "quay" → "key").
- [ ] Within a minute: pill flashes **"Noticed your fix…"**.
- [ ] Open Dictionary → the suggestion row is there; Add appends a `heard -> Correct` line.
- [ ] Fix a word at the *very end* of a dictation too — that also gets noticed (was impossible before).
- [ ] debug.log shows `Correction check 6s/20s/60s` lines.

## 4. Command mode (4.4)

Do the first block in a **native** app (Notes/TextEdit), the second in an
**Electron** app (Claude Desktop) — they use different replacement paths.

- [ ] **Native (Notes):** Dictate a casual sentence. Hold Right ⌥, say **"make it more formal"**, release → pill shows "Working on it…", then the text is replaced in place.
- [ ] Hold again, say **"translate to French"** → the (already formal) text becomes French — commands chain.
- [ ] Hold Right ⌥ *before ever dictating* (fresh launch) → pill says "Dictate something first…".
- [ ] Esc while it's listening → "Cancelled".
- [ ] **Electron (Claude Desktop) — the keyboard fallback:** on a **throwaway message**, dictate a sentence, then hold Right ⌥ and say **"make it more formal"**. Expect: the old text gets selected and replaced in place (a brief flurry as it selects, then the new text). Verify **no leftover duplicate** of the old text remains. Do **not** click elsewhere between dictating and commanding — the fallback assumes the cursor is still at the end of what you dictated. If it selects the wrong thing, that's the caveat firing; note it.

## 5. Menu-bar actions (3.7, 5.5)

- [ ] Dictate something the polish visibly reworded (ramble with "um"s, Full polish style helps). Menu bar → **Undo AI Rewording** → your own wording replaces the AI's version. NOTE: "um"s stay gone — fillers are stripped by the deterministic rules, not the AI; this action undoes only what the AI changed.
- [ ] Dictate again, then menu bar → **Undo Last Insertion** → the text vanishes from the field.
- [ ] Repeat both once in **Claude Desktop** (throwaway message) to exercise the same keyboard fallback there.

## 6. Style matching (3.3) — REMOVED 2026-07-22, skip

Owner decision mid-QA: style matching and per-app style notes are
advanced features for later — both were removed from the app and parked
in `FUTURE_IMPROVEMENTS.md` (3.2/3.3). Nothing to test here; see the
§13 bullet that confirms the Settings sections are gone.

## 7. Privacy controls (8.1, 8.2, 8.3)

- [ ] Settings → Privacy → **Add Private App** → pick Notes. Dictate into Notes → works, but **no new entry in History**, and debug.log shows **no** "Correction check" lines for it. Remove Notes from the list afterwards.
- [ ] Set **Keep dictation history → Keep nothing** → History empties immediately and `history.json` is gone from Application Support. Set it back.
- [ ] Toggle **Learn corrections from your edits** off → dictate, edit a word → no pill notice, no "Correction check" log lines. Toggle back on.

## 8. Microphone (6.5)

- [ ] Settings → Microphone lists your input devices; leave on **System default**.
- [ ] Mute the mic (or set input volume to zero), hold fn ~3 s, release → pill: **"Only silence was heard — is the microphone muted…"** (not the generic "didn't catch that"). Unmute.

## 9. Insertion tester (6.6)

- [ ] Troubleshooting → **Test a Text Field…** → click into Notes within 3 s → verdict: **Direct insertion** (green).
- [ ] Repeat in an Electron app (Claude Desktop) and a browser field → usually **Direct insertion** too, and that's correct: Chromium fields accept clean at-caret insertion (what they break is in-place *replacement* — command mode/Undo — which is why those have a keyboard fallback). **Paste fallback (⌘V)** is also a fine verdict — any answer with an explanation passes; only "No Accessibility permission" or "Paste, unverified" signals a problem. (Verdicts verified on-device 2026-07-22.)

## 10. Settings backup (7.8)

- [ ] Settings → Backup → **Export Settings…** → save the file.
- [ ] Change something visible (hotkey, a dictionary line), then **Import Settings…** with the file → the change reverts. "Settings imported." appears.

## 11. Dictionary boosting — REMOVED 2026-07-22, skip (2.2)

Owner decision after live testing: it fixed the known name at the
source, but it also swapped an UNKNOWN proper name for random
dictionary terms — parked the same morning, then fully removed from
the app to simplify before sharing (see FUTURE_IMPROVEMENTS 2.2 for
restore pointers). Nothing to test today beyond the §13 bullet that
confirms the toggle is gone. If it's ever re-attempted, these are the
re-entry gates — all must pass, especially the first:

- [ ] (future) Dictate "I met Marina Cremonese today" (any full name NOT in the dictionary) three times → it must come out as spoken (possibly misspelled) and NEVER as a dictionary word or email.
- [ ] (future) Dictate a sentence with your dictionary name, half-mumbled → comes out spelled right; debug.log shows small-N "Dictionary boost: N replacement(s)".
- [ ] (future) Two long sentences with NO dictionary words → untouched; watch debug.log for "rejected — … (cap …)" lines.
- [ ] (future) Judge the added latency.

## 12. Factory reset (6.7) — OPTIONAL, destructive, do LAST if at all

Wipes everything including ~1.6 GB of models. Only if you want to test
the fresh-install path: About → click the version 5× → **Erase
Everything & Quit** → relaunch behaves like a brand-new install, and
any deletion failures appear in an alert instead of being swallowed.

## 13. Mid-QA fixes (2026-07-22) — verify these LAST, after one more update

Everything below was fixed live during today's QA session. **Check for
Updates first** (About shows a new build stamp), then run these. Keep
Polish style on "Keep my words" throughout.

Dictionary end-state for these tests: plain lines `Zach Abugov`,
`Lauralyn`, `Marina Cremonese`, the plain line `zachabugov@gmail.com`,
and the mapping `Abigail -> Abugov`. The old `Abagoff -> …` pile and
the `zacov at gmail -> …` mapping can be deleted.

- [ ] **Names by sound:** "hi my name is Zach Abugov" ×3, speaking
      naturally and releasing the key immediately after the last
      syllable → "Abugov" every time (grace capture + sound matching
      together cover the clipped-audio case).
- [ ] **Real-name snap:** same sentence once more, lazily — if it snaps
      to "Abigail," the mapping line must still rescue it → "Abugov".
- [ ] **Unknown names survive:** "I met Marina Cremonese today" ×2 →
      never a dictionary word or email; spelling variants like
      "Cremoneza" snap to "Cremonese" via the plain line.
- [ ] **Spoken email:** "email me at zachabugov at gmail dot com"
      (say your name-part naturally, even if it gets misheard) →
      `zachabugov@gmail.com` assembled correctly.
- [ ] **Email snippet:** add snippet "my email" → your address; say
      "email me at my email" → the address, letter-perfect.
- [ ] **Visible fields:** the Snippets tab now shows bordered,
      obviously-clickable text boxes with example placeholders.
- [ ] **Spoken decimals:** "that costs 126453 point 3 dollars" →
      `$126,453.3` (not "point $3"); "growth was 12 point 5 percent" →
      `12.5%`; "I want to make a point 3 times" stays plain words.
- [ ] **No email bleed in polish:** a few ordinary sentences with Full
      polish ("Rewrite for clarity") temporarily on → your email never
      appears uninvited (it's excluded from the AI's dictionary now).
      Switch back to "Keep my words" after.
- [ ] **Correction learning with repeats:** in one note, dictate the
      same sentence twice, then fix the last word of the NEWEST copy →
      pill flashes "Noticed your fix…" and the suggestion appears in
      Dictionary. (Previously the older unedited copy hijacked the
      comparison and the fix was invisible.)
- [ ] **Undo refuses when the field moved on:** in Claude Desktop,
      dictate, type a few extra characters by hand, then menu →
      Undo Last Insertion → the app refuses with "the text changed
      after it was inserted" and nothing is deleted. Then dictate
      fresh and undo immediately → exactly the dictation disappears.
- [ ] **"Undo AI Rewording" (renamed from Use Unpolished Version):**
      returns your pre-AI wording — "um"s are still stripped (that's
      the rules layer, not the AI).
- [ ] **Electron command mode, again:** in Claude Desktop on a
      throwaway message, dictate, then Right ⌥ → "make it more formal"
      → the old text visibly deletes character-by-character and the
      new version lands in its place. No copy prepended at the start
      (the old selection method broke in Chromium; it now deletes with
      plain keystrokes instead).
- [ ] **Removed features are gone:** Settings no longer shows a
      "Your writing style" or "Per-app style notes" section (both
      parked in FUTURE_IMPROVEMENTS as later features), and everything
      else in Settings still renders and saves normally. Export
      Settings once → the file saves without error.
- [ ] **No ghost microphones:** Settings → Microphone lists only real
      devices — no "CADefaultDeviceAggregate-…" entry (that was a
      temporary echo-cancelling wrapper macOS creates for
      voice-processing apps; it leaked into the picker and one was
      selected during QA). After updating, the picker should be back
      on **System default** (the ghost selection heals itself) —
      leave it there and dictate once to confirm the mic still works.
- [ ] **Silent mic shows no phantom preview:** mute the mic, hold fn
      ~3 s, release → the pill preview stays empty the whole time (no
      hallucinated "Thank you.") and the silence alert still appears.
- [ ] **Boost toggle is gone:** Settings → Speech recognition no
      longer shows "Boost my dictionary words (experimental)" — the
      feature was fully removed (FUTURE_IMPROVEMENTS 2.2). Dictate
      once with your name → still comes out right (that's the
      phonetic dictionary matching, which is unrelated and stays).

The bullets below came from the written code review (2026-07-22,
17 findings — all fixed the same day):

- [ ] **Ordinary words survive name matching:** with `Lauren` and
      `Marina Cremonese` in the dictionary, dictate "I want to learn
      something" and "good morning everyone" → "learn" and "morning"
      stay themselves. Your surname still snaps right (real English
      words are now off-limits to sound-matching; invented
      mishearings are not).
- [ ] **"look at example dot com" stays prose** — no email address
      is assembled without a real cue ("my address is bob at example
      dot com" still converts).
- [ ] **Private apps stay private through edits:** mark Notes
      private, dictate, then Right ⌥ → "make it more formal" → the
      edit works but History still shows nothing from Notes. Unmark.
- [ ] **Failed command edits don't corrupt the next one:** if a
      command ever says "Couldn't edit in place — copied", the app no
      longer pretends the edit landed; a follow-up command still
      targets the text actually in the field.
- [ ] **Learning off means off, immediately:** dictate, then within
      ~5 s toggle "Learn corrections from your edits" off → debug.log
      shows "learning disabled since scheduling — stopped" instead of
      later Correction check reads. Toggle back on.
- [ ] **System default mic reattaches:** Settings → Microphone →
      pick the MacBook mic, dictate; switch back to System default,
      dictate again → both work (the second one actively re-selects
      today's default device).
- [ ] **Menu-bar icon is George:** when idle, the menu bar shows the
      app's own icon instead of a microphone glyph (no more confusion
      with the system mic indicator). While recording it still turns
      into the dancing waveform, and it returns to George afterwards.
- [ ] **Split-name email reassembles:** dictate "email me at
      zachabugov at gmail dot com" a few times → even when the
      recognizer hears the name-part as two words ("Zach Abugov") and
      it briefly assembled as "Zach abugov@gmail.com", it now folds
      back into `zachabugov@gmail.com`. Also dictate a DIFFERENT
      address at the same domain ("sarah at gmail dot com" with an
      email cue) → it stays sarah's, never yours.
- [ ] **Numbers as words come out like numbers as digits** (the
      recognizer alternates between the two): "two million seven
      hundred fifty six thousand two hundred forty three point seven
      dollars" → `$2,756,243.7` (no stranded "point $7", commas
      included); "…times bigger" → `2,756,000 times bigger`; "twelve
      point five percent" → `12.5%`; "twenty twenty-six" → `2026`
      (years never get commas).
- [ ] **First dictation after an update works:** immediately after
      Check for Updates relaunches the app, hold fn and dictate →
      text inserts normally, no "Audio device changed — dictation
      cancelled" flash (the first capture used to die when macOS
      rebuilt the audio graph; it now rebuilds mid-recording and
      keeps going — debug.log shows "capture rebuilt, recording
      continues" when it happens).

---

## Release-day checks (after the migration release, not before)

- [ ] On a Mac running an older build: Check for Updates → the new
      release installs via Sparkle **and the update prompt shows the
      what's-new notes** (9.9). This is also the 7.10 signed-update
      sign-off.
- [ ] The DMG's install window shows the **Applications folder icon**
      (macOS 26 fix).
- [ ] Website Download button fetches `GeorgesWords.dmg` and it opens (9.2).
- [ ] After updating, the app's update feed points at the releases repo
      (ADR 0009 step 6), and the appcast commit landed in **both** repos.
