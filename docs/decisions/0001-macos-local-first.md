# ADR 0001: Target macOS, fully on-device processing

**Status:** Accepted · **Date:** 2026-07-02

## Context

We are building a commercial Flow–style dictation app. The owner's machine is a MacBook, and the non-negotiable requirement is that **no audio leaves the device** — commercial Flow itself transcribes in the cloud, which is exactly what we want to avoid.

## Decision

1. **macOS only** (for now). System-wide dictation requires deep OS hooks — global hotkeys, microphone capture, and injecting text into the focused app — which are inherently platform-specific. Targeting one OS keeps the first version tractable.
2. **All processing on-device.** Speech-to-text and any formatting/cleanup pass run locally on Apple Silicon. No cloud APIs in the audio/text path, no accounts, no telemetry.
3. **Apple Silicon assumed.** Local speech models get their speed from the Neural Engine / Metal GPU; Intel Macs are out of scope.

## Consequences

- We can use macOS-native frameworks (AVAudioEngine, CGEvent taps, Accessibility API, pasteboard) directly.
- Model choice is constrained to what runs well locally (Whisper-family via whisper.cpp/WhisperKit, NVIDIA Parakeet via CoreML ports, Apple Speech APIs, etc.) — evaluated in the research report.
- Some commercial Flow features that depend on server-side LLMs (heavy tone rewriting, cross-device sync) will be reimplemented with small local models or rules, or dropped.

## Open (decided later, informed by research)

- App language/stack (native Swift vs Tauri/Rust) — ADR 0002.
- Which STT model and runtime — ADR 0003.
