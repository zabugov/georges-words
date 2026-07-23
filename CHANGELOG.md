# What's new in George's Words

Written for the people who use the app — short and in plain language.
The "Unreleased" section becomes the release notes of the next update
(the release pipeline lifts it automatically; keep entries user-facing).

## Unreleased

- **Your name comes out right even when it's misheard a new way.** The
  dictionary now matches by sound: if a word clearly sounds like one of
  your dictionary words ("Abagoff", "Abakov"…), it becomes that word's
  exact spelling — no more adding a fix for every new misspelling. The
  name-part of an email address in your dictionary gets the same
  treatment, so spoken addresses assemble correctly too.
- **Releasing the key mid-word no longer garbles the last word.** If
  you let go while still speaking, the app keeps listening for a brief
  moment so the recognizer hears the whole word; releasing after a
  pause stays instant.
- **Phone numbers and emails come out formatted.** Say a phone number
  ("five five five one two three four") and it lands as `555-1234`;
  ten digits become `(800) 555-1212`. Say an email ("john dot smith at
  gmail dot com") and it lands as `john.smith@gmail.com`. Large spoken
  numbers like "one hundred twenty three" now come out as `123` too,
  and decimals join up properly — "point three dollars" lands as part
  of the amount, not as a stray word. All of this happens on-device
  with no AI needed.
- **Voice commands.** Hold **Right Option (⌥)** and say how to change
  what you just dictated — "make it more formal", "remove the word
  actually", "translate to French". On by default; pick a different key
  or turn it off in Settings → Hotkeys. Works in your regular apps
  including Electron ones like Claude Desktop and VS Code.
- **Faster results when you pause.** The app now polishes while you
  think — release the key after a pause and the text often lands
  instantly.
- **It learns your fixes more reliably**, including fixes to the last
  words you said, and quietly tells you when it has a suggestion
  waiting in Dictionary.
- **New privacy controls.** Choose how long dictation history is kept,
  turn correction-learning off entirely, or mark specific apps private
  (Settings → Privacy).
- **Pick your microphone** (Settings → Microphone) — and if a recording
  hears only silence, the app now says so instead of shrugging.
- **The menu-bar icon is now George.** The little microphone looked
  too much like macOS's own microphone indicator — the app's icon sits
  there instead, switching to a live waveform while you dictate.
- **Menu bar:** "Undo AI Rewording" restores your own wording if the
  AI reworded something (basic cleanup stays); "Undo Last Insertion"
  removes what was just typed — and both now refuse, rather than
  guess, if you've edited the text since.
- **Settings backup.** Export everything (dictionary, snippets,
  settings) to one file and import it on a new Mac.
- **Troubleshooting:** a "Test a Text Field…" button tells you how
  dictation will insert into any app, and the installer's Applications
  icon shows correctly again on macOS 26.

## 0.3.0 (build 17) and earlier

Earlier releases predate this changelog: on-device dictation with
Parakeet, AI polish through the app's private local engine, the
auto-learning dictionary, Sparkle auto-updates, and the notarized DMG
pipeline.
