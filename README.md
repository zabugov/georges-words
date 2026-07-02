# George's Words

A system-wide dictation app for macOS, in the spirit of [Wispr Flow](https://wisprflow.ai) — hold a key, speak anywhere, get clean formatted text — with one hard rule:

> **Audio never leaves the laptop.** Transcription and formatting run 100% on-device.

## Status

🚧 **Pre-build.** Research and scaffolding phase. See [`docs/research/`](docs/research/) for the deep-dive on Wispr Flow, local speech-to-text models, and the competitive landscape that informs the design.

## What it will do

- **Push-to-talk anywhere** — hold a global hotkey (e.g. Fn or a chosen key), speak, release; polished text appears in whatever app has focus (Slack, mail, editor, browser).
- **On-device transcription** — local speech-to-text on Apple Silicon (Neural Engine / Metal), no cloud STT.
- **Auto-formatting** — punctuation, capitalization, paragraph breaks, and cleanup of "uh", restarts, and self-corrections ("send it Monday— no, Tuesday" → "send it Tuesday").
- **Custom dictionary** — names, jargon, and product terms transcribed correctly.
- **Recording indicator** — a small floating pill/window showing live status while you speak.

## Planned architecture (preliminary — finalized after research)

```
georges-words/
├── docs/
│   ├── research/        # Wispr Flow + local STT deep-dive (generated report)
│   └── decisions/       # Architecture decision records (ADRs)
├── app/                 # macOS app source (created at first build milestone)
└── models/              # Local model download location (gitignored)
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
