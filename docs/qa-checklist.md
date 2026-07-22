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

- [ ] Dictate something the polish visibly reworded (ramble with "um"s, Full polish style helps). Menu bar → **Use Unpolished Version** → your exact words replace the polished text in the field.
- [ ] Dictate again, then menu bar → **Undo Last Insertion** → the text vanishes from the field.
- [ ] Repeat both once in **Claude Desktop** (throwaway message) to exercise the same keyboard fallback there.

## 6. Style matching (3.3)

- [ ] Settings → Your writing style → "Casual (chat apps)" → paste a real chat message of yours.
- [ ] Set polish style to **Rewrite for clarity**, dictate into a chat app (or set Neutral's sample and use Notes) → the output should lean toward your sample's tone (greeting habits, formality). Judgment call — "does this sound more like me?"

## 7. Privacy controls (8.1, 8.2, 8.3)

- [ ] Settings → Privacy → **Add Private App** → pick Notes. Dictate into Notes → works, but **no new entry in History**, and debug.log shows **no** "Correction check" lines for it. Remove Notes from the list afterwards.
- [ ] Set **Keep dictation history → Keep nothing** → History empties immediately and `history.json` is gone from Application Support. Set it back.
- [ ] Toggle **Learn corrections from your edits** off → dictate, edit a word → no pill notice, no "Correction check" log lines. Toggle back on.

## 8. Microphone (6.5)

- [ ] Settings → Microphone lists your input devices; leave on **System default**.
- [ ] Mute the mic (or set input volume to zero), hold fn ~3 s, release → pill: **"Only silence was heard — is the microphone muted…"** (not the generic "didn't catch that"). Unmute.

## 9. Insertion tester (6.6)

- [ ] Troubleshooting → **Test a Text Field…** → click into Notes within 3 s → verdict: **Direct insertion** (green).
- [ ] Repeat clicking into a browser URL bar or an Electron app → **Paste fallback (⌘V)** with an explanation.

## 10. Settings backup (7.8)

- [ ] Settings → Backup → **Export Settings…** → save the file.
- [ ] Change something visible (hotkey, a dictionary line), then **Import Settings…** with the file → the change reverts. "Settings imported." appears.

## 11. Dictionary boosting — experimental (2.2)

Known incident (2026-07-22, fixed same day): with short name terms, the
boost sprayed dictionary words across whole sentences. It now has a hard
cap — it may change at most ~1 word in 8 (min 2) or the entire rescore
is discarded. This test verifies the cap holds.

- [ ] Settings → Speech recognition → enable **Boost my dictionary words**.
- [ ] Dictate a sentence containing your dictionary name; expect a pause on the first use (~100 MB one-time download; watch debug.log for "Dictionary boost: pipeline ready").
- [ ] Deliberately half-mumble the name → it should still come out spelled right when the audio supports it; debug.log logs any "Dictionary boost: N replacement(s)".
- [ ] **The regression check:** dictate two long sentences that DON'T contain any dictionary word → the transcript must come out untouched. If names appear where you didn't say them, turn the toggle off and report it — debug.log will show either "rejected — N replacement(s) … (cap …)" (cap working, threshold still too loose) or small-N replacement lines (swaps sneaking under the cap).
- [ ] Judge the added latency. If it annoys, turn the toggle off — everything else is unaffected.

## 12. Factory reset (6.7) — OPTIONAL, destructive, do LAST if at all

Wipes everything including ~1.6 GB of models. Only if you want to test
the fresh-install path: About → click the version 5× → **Erase
Everything & Quit** → relaunch behaves like a brand-new install, and
any deletion failures appear in an alert instead of being swallowed.

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
