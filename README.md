# George's Words

A system-wide dictation app for macOS, in the spirit of [commercial Flow](https://example.com) — hold a key, speak anywhere, get clean formatted text — with one hard rule:

> **Audio never leaves the laptop.** Transcription and formatting run 100% on-device.

## Status

🚧 **M1 — walking skeleton.** Hold Fn → speak → release → transcribed text is pasted at your cursor, fully on-device. See [`docs/research/`](docs/research/) for the commercial Flow deep-dive that informs the design, and [`docs/decisions/`](docs/decisions/) for the ADRs.

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

To use a bigger/better model: `defaults write com.georges.words ModelName "distil-large-v3"` and relaunch. If the hotkey stops responding after a rebuild, toggle the Accessibility permission off and on (ad-hoc signing quirk).

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
│       ├── AppDelegate.swift     # state machine + menu bar UI
│       ├── HotkeyMonitor.swift   # hold-Fn detection (global event monitor)
│       ├── AudioRecorder.swift   # AVAudioEngine → 16 kHz mono Float32
│       ├── Transcriber.swift     # WhisperKit (CoreML / Neural Engine)
│       └── TextInserter.swift    # clipboard + simulated ⌘V (AX API in M2)
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
