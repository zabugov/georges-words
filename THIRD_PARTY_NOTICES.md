# Third-party notices

George's Words is built on the following third-party software and models.
This file ships with the project as a release artifact; the About screen
carries a summary.

## Speech recognition

- **NVIDIA Parakeet** (`parakeet-tdt-0.6b-v3`) — speech-to-text model.
  License: **CC-BY-4.0** (attribution required; this file and the About
  screen provide it). © NVIDIA Corporation.
- **FluidAudio** (FluidInference) — Swift runtime for Parakeet on
  CoreML/Apple Neural Engine. License: **Apache 2.0**.
- **WhisperKit** (Argmax) — fallback speech engine. License: **MIT**.
- **OpenAI Whisper models** (via WhisperKit) — License: **MIT**.

## Text polish

- **Ollama** — local LLM engine, run privately by the app on a random
  localhost port. License: **MIT**. Pinned version and SHA-256 recorded
  in `ManagedOllama.swift`.
- **Qwen 2.5 1.5B** (Alibaba) — default polish model. License:
  **Apache 2.0**. Note: other Qwen 2.5 sizes carry different licenses
  (3B is research-only) — check before changing the default.

## App infrastructure

- **Sparkle** — software update framework for the DMG distribution.
  License: MIT-style (Sparkle license). © Sparkle Project contributors.
- **create-dmg** — DMG styling in the release pipeline (build-time
  only, not shipped). License: **MIT**.

George's Words itself is © the owner; no open-source license is granted
for this repository's own code (see README).
