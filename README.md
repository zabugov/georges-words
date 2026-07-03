# George's Words

A system-wide dictation app for macOS, in the spirit of [commercial Flow](https://example.com) — hold a key, speak anywhere, get clean formatted text — with one hard rule:

> **Audio never leaves the laptop.** Transcription and formatting run 100% on-device.

## Status

🚧 **M4 — power features.** The full loop: hold a hotkey → speak → release → *polished* text appears at your cursor, fully on-device — filler words stripped, self-corrections applied ("Tuesday — no wait, Friday" → "Friday"), personal-dictionary spellings enforced, tone matched to the app you're dictating into. Plus:

- **Live preview** — a rolling transcript appears in the pill *while* you speak.
- **Command mode** — select text anywhere, hold the command key (default Right ⌥), and speak an instruction: "make this shorter", "make it a bulleted list", "translate to French". The selection is replaced with the edit (requires Ollama).
- **Snippets** — say a trigger phrase ("my sign off"), get your exact boilerplate inserted.
- **History** — the last 200 transcripts, stored only on this Mac, one click to copy, one click to clear.

Formatting is two-stage: instant rule-based cleanup always, plus an optional rewrite by a local LLM via [Ollama](https://ollama.com) — see below. See [`docs/research/`](docs/research/) for the commercial Flow deep-dive, [`docs/decisions/`](docs/decisions/) for the ADRs, and [`FUTURE_IMPROVEMENTS.md`](FUTURE_IMPROVEMENTS.md) for the backlog to full commercial Flow parity.

## Quick start (on your Mac)

```sh
git clone https://github.com/zabugov/georges-words.git
cd georges-words
./app/build.sh
```

Requires macOS 14+ on Apple Silicon and the Xcode Command Line Tools (`xcode-select --install` if `swift` isn't found; if the build complains about missing SDKs, install full Xcode from the App Store).

First run:

1. Grant **Microphone** and **Accessibility** permissions when prompted.
2. Set **System Settings → Keyboard → "Press 🌐 key" → Do Nothing** so holding Fn doesn't open the emoji picker.
3. Wait for the menu-bar hourglass to become a mic — the first launch downloads the speech model (one-time, ~500 MB; the only network use this app will ever make).
4. Click into any text field, **hold Fn, speak, release.**

The speech model, hotkey (Fn, Right ⌘, or Right ⌥), AI polish, and personal dictionary live in **Settings…** under the menu-bar icon.

**Updating:** menu bar → **Check for Updates…** pulls the latest from GitHub, rebuilds, and relaunches — no terminal needed after the first install.

### Recommended: stable signing (do this once)

By default each rebuild is ad-hoc signed, and macOS treats every rebuild as a *new* app — silently invalidating the Accessibility grant, which breaks text insertion until you re-toggle it. Fix it permanently:

```sh
./app/setup-signing.sh    # creates a "GeorgesWords Dev" certificate in your keychain
./app/build.sh            # from now on, builds are signed with it
```

After the *first* signed build, re-grant Accessibility one last time (System Settings → Privacy & Security → Accessibility → toggle GeorgesWords) and click "Always Allow" if macOS asks about keychain access during the build. Every rebuild after that keeps its permissions.

### Optional: full AI polish via a local LLM

Dictation works out of the box with rule-based cleanup. For commercial-Flow-class rewriting (self-corrections, sentence restructuring, per-app tone), install [Ollama](https://ollama.com) and pull the default polish model:

```sh
brew install ollama        # or download from ollama.com
ollama pull qwen2.5:3b
```

George's Words talks to Ollama at `localhost:11434` — an app-to-app call inside your Mac; no text goes to any network. If Ollama isn't running, the app silently falls back to rule-based cleanup. Never worse, sometimes much better.

## What it will do

- **Push-to-talk anywhere** — hold a global hotkey (e.g. Fn or a chosen key), speak, release; polished text appears in whatever app has focus (Slack, mail, editor, browser).
- **On-device transcription** — local speech-to-text on Apple Silicon (Neural Engine / Metal), no cloud STT.
- **Auto-formatting** — punctuation, capitalization, paragraph breaks, and cleanup of "uh", restarts, and self-corrections ("send it Monday— no, Tuesday" → "send it Tuesday").
- **Custom dictionary** — names, jargon, and product terms transcribed correctly.
- **Recording indicator** — a small floating pill/window showing live status while you speak.

## Architecture

```
georges-words/
├── app/                 # macOS app (Swift Package + build.sh → .app bundle)
│   └── Sources/GeorgesWords/
│       ├── main.swift            # entry point (menu-bar accessory app)
│       ├── AppDelegate.swift     # state machine + menu bar UI + wiring
│       ├── AppSettings.swift     # user prefs (model, hotkey, login item)
│       ├── HotkeyMonitor.swift   # hold-key detection (global event monitor)
│       ├── AudioRecorder.swift   # AVAudioEngine → 16 kHz mono + level meter
│       ├── Transcriber.swift     # WhisperKit (CoreML / Neural Engine)
│       ├── TextInserter.swift    # AX-API insertion → clipboard ⌘V fallback
│       ├── SelectionReader.swift # read selected text (AX → ⌘C fallback)
│       ├── TranscriptCleaner.swift # stage 1: rule-based cleanup + dictionary
│       ├── LLMFormatter.swift    # stage 2: local LLM rewrite + command mode
│       ├── AppContext.swift      # frontmost-app bundle ID → tone profile
│       ├── Snippets.swift        # voice shortcuts (trigger → expansion)
│       ├── HistoryStore.swift    # local-only transcript history
│       ├── HistoryView.swift     # history window
│       ├── RecordingPill.swift   # floating pill + live preview
│       └── SettingsView.swift    # SwiftUI settings window
└── docs/
    ├── research/        # commercial Flow + local STT deep-dive
    └── decisions/       # Architecture decision records (ADRs)
```

Core pipeline:

```
global hotkey → mic capture → local STT model → local formatting pass → insert text into focused app
   (event tap)   (AVAudioEngine)  (Apple Silicon)     (rules / small LLM)     (pasteboard or key events + AX API)
```

## Principles

1. **Local-first, always.** No audio or transcript leaves the machine. No accounts, no telemetry.
2. **Latency is the product.** Target: text appears well under ~1s after you stop speaking.
3. **Invisible until needed.** A menu-bar app with a hotkey — no windows to manage.
