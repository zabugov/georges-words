# ADR 0004: Parakeet (FluidAudio) as a selectable STT engine alongside Whisper

**Status:** Accepted · **Date:** 2026-07-03

## Context

Real-world use showed end-to-end latency is the biggest gap versus commercial
Flow. The research report flagged NVIDIA's parakeet-tdt-0.6b as the
speed/accuracy leader (top of the Open ASR Leaderboard, RTFx in the
hundreds on Apple Neural Engine via CoreML) and it is the engine behind
the "instant" feel of VoiceInk and Handy.

## Decision

1. Add **FluidAudio** (SPM, `FluidInference/FluidAudio`) and expose an
   **engine picker** in Settings: *Parakeet v3* or *Whisper (WhisperKit)*.
2. `Transcriber` (actor) wraps both behind one `transcribe([Float])`
   interface; both consume the same 16 kHz mono stream from
   `AudioRecorder`.
3. **Whisper remains the default** until Parakeet has been validated in
   daily use on the owner's machine; flipping the default is a one-line
   change. Whisper also stays for its larger multilingual coverage.
4. Alongside: leading/trailing **silence trimming** before transcription
   and a **1 s warm-up inference** after model load (pays the ANE
   pipeline-compilation cost at launch, not on the first dictation).

## Consequences

- Second model download path (~600 MB from Hugging Face, one-time) —
  still the only network use, per ADR 0001.
- Parakeet v3 covers English + 24 European languages + Japanese; Whisper
  remains the choice for languages outside that set.
- If Parakeet proves reliably better in daily use, make it the default
  and consider FluidAudio's streaming API (`SlidingWindowAsrManager`) for
  the true-streaming milestone.
