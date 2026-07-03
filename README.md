# George's Words

A system-wide dictation app for macOS, in the spirit of [commercial Flow](https://example.com) — hold a key, speak anywhere, get clean formatted text — with one hard rule:

> **Audio never leaves the laptop.** Transcription and formatting run 100% on-device.

## Status

🚧 **M3 — the formatting layer.** Hold a hotkey → speak → release → *polished* text appears at your cursor, fully on-device: filler words stripped, self-corrections applied ("Tuesday — no wait, Friday" → "Friday"), personal-dictionary spellings enforced, and tone matched to the app you're dictating into (casual in Slack, professional in Mail, literal in editors/terminals). Formatting is two-stage: instant rule-based cleanup always, plus an optional rewrite by a local LLM via [Ollama](https://ollama.com) — see below. See [`docs/research/`](docs/research/) for the commercial Flow deep-dive and [`docs/decisions/`](docs/decisions/) for the ADRs.

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

The speech model, hotkey (Fn, Right ⌘, or Right ⌥), AI polish, and personal dictionary live in **Settings…** under the menu-bar icon. If the hotkey stops responding after a rebuild, toggle the Accessibility permission off and on (ad-hoc signing quirk).

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
│       ├── TranscriptCleaner.swift # stage 1: rule-based cleanup + dictionary
│       ├── LLMFormatter.swift    # stage 2: local LLM rewrite via Ollama
│       ├── AppContext.swift      # frontmost-app bundle ID → tone profile
│       ├── RecordingPill.swift   # floating non-activating status pill
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
