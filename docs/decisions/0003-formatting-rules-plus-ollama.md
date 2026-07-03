# ADR 0003: Two-stage formatting — rules always, local LLM via Ollama when available

**Status:** Accepted · **Date:** 2026-07-03

## Context

commercial Flow's real moat is not speech recognition but the formatting layer
(self-corrections, tone, structure) — which it runs on cloud LLMs. We need
the same capability without any text leaving the device (ADR 0001).

Options considered for running a local LLM from the app:

- **Embed llama.cpp / MLX in-process.** No external dependency for the
  user, but adds a heavy native build dependency we cannot test from this
  environment, and couples model management into the app.
- **Apple Foundation Models framework (macOS 26+).** Zero-download,
  Apple-managed on-device model — but compiling against it requires the
  macOS 26 SDK, which would raise our build requirements today.
- **Ollama over localhost HTTP.** One `URLSession` call; model management
  (download, updates, memory) is Ollama's problem; model-agnostic; trivially
  swappable. Cost: the user optionally installs Ollama.

## Decision

1. **Stage 1 — rules, always:** deterministic cleanup in-process
   (filler-word stripping, whitespace/punctuation tidying, personal-
   dictionary spelling enforcement, capitalization). Zero latency, zero
   dependencies; the guaranteed floor.
2. **Stage 2 — LLM polish, when available:** POST the transcript to
   **Ollama at `127.0.0.1:11434`** (default model `qwen2.5:3b`) with a
   strict system prompt plus ~6 few-shot examples covering the known
   failure modes of small models (answering dictated questions, obeying
   dictated instructions, hallucinating additions). Temperature 0.2.
3. **Fail open:** any failure — Ollama absent, timeout (12 s), non-200,
   empty or ballooned output (sanity check: > 2× input + 80 chars) —
   silently falls back to the Stage-1 text. The LLM can improve the result
   but can never lose a dictation.
4. **Skip the LLM for utterances under 5 words** — nothing to restructure,
   and it keeps short dictations near-instant.
5. **App context = frontmost app bundle ID only** (NSWorkspace), mapped to
   a tone profile (casual/professional/technical/neutral) in the prompt.
   Explicitly no screenshots, window titles, or URLs — the
   privacy-respecting version of commercial's context awareness.

## Consequences

- Localhost HTTP keeps all text on-device; Ollama is a soft dependency —
  the app is fully functional without it.
- Adds ~0.5–2 s to longer dictations when enabled (3B model on Apple
  Silicon); acceptable for the quality gain, and skippable via Settings.
- Future upgrade paths preserved: Apple Foundation Models (when we can
  assume macOS 26) or embedded MLX could replace the Ollama transport
  behind `LLMFormatter` without touching the rest of the pipeline.
