# ADR 0002: Native Swift app with WhisperKit for on-device STT

**Status:** Accepted · **Date:** 2026-07-02

## Context

ADR 0001 fixed the platform (macOS, Apple Silicon, fully local). A research
pass (competitive notes kept outside the repo) surveyed the stacks used by
comparable dictation apps — Tauri/Rust, Electron, and native Swift builds.

## Decision

1. **Native Swift (AppKit menu-bar app), built with Swift Package Manager.**
   Deepest access to the OS hooks this app lives on — Accessibility API,
   event monitors, AVAudioEngine, pasteboard — plus CoreML/Neural Engine for
   models, with no Electron/Tauri runtime overhead. A comparable native-Swift
   app validates the shape (architecture referenced only; its GPL code is
   not copied). SPM + a small `build.sh` that assembles the `.app` bundle
   keeps the build one command and Xcode-project-free.
2. **WhisperKit as the STT runtime**, default model `small.en` (configurable
   via `defaults write com.georges.words ModelName …`). Swift-native,
   CoreML/ANE-optimized, well-maintained, one-line model swapping across the
   whole Whisper family (`distil-large-v3`, `large-v3`, multilingual).
3. **Insertion chain (M1):** clipboard + simulated ⌘V with clipboard
   save/restore. Direct AX insertion is planned for M2 with paste as the
   fallback — the same chain the polished commercial apps use.
4. **Hotkey:** hold-Fn via `NSEvent` global flags-changed monitor (keyCode 63).

## Consequences

- Model weights download once from Hugging Face on first launch (the only
  network use; audio/transcripts never leave the device per ADR 0001).
- Ad-hoc code signing means Accessibility permission may need re-granting
  after rebuilds; a stable signing identity can fix this later.
- **Parakeet TDT v3 via FluidAudio (CoreML)** is the flagged speed/accuracy
  upgrade path if Whisper latency disappoints — revisit after M1 is in
  daily use (would become ADR 0003).
