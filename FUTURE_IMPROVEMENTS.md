# Future Improvements

The outstanding work to bring George's Words to commercial Flow's level of polish and functionality — everything not already shipped or actively in progress. Sourced from the [commercial Flow deep-dive](docs/research/competitive-research.md) feature inventory and observations from daily use. Effort: **S** (hours), **M** (days), **L** (a milestone).

When we start something from this list, move it out of here and into the work itself (commit/ADR); when new gaps show up in daily use, add them.

## 1. Speed & responsiveness

The gap that matters most — commercial feels instant.

- [ ] **(L)** **Switch STT to Parakeet** via FluidAudio (CoreML). The model behind VoiceInk/Handy's near-instant feel; tops the Open ASR Leaderboard. Keep WhisperKit as a fallback path. → would become ADR 0004.
- [ ] **(L)** **Streaming transcription** — transcribe chunks *while* speaking (the live preview already does this crudely), so key-release only costs the final chunk + polish instead of the whole utterance.
- [ ] **(M)** **Evaluate smaller/faster polish models** — `qwen2.5:1.5b`, `llama3.2:1b`, `gemma3:1b` — measure quality-vs-latency with a fixed test set of messy transcripts.
- [ ] **(M)** **Apple Foundation Models** (macOS 26+) as the polish engine — Apple's built-in on-device ~3B model; would remove the Ollama install entirely for users on new macOS. Needs a macOS 26 SDK build path.
- [ ] **(S)** **Trim leading/trailing silence** before transcription (simple energy-based VAD) — less audio to process, faster results.
- [ ] **(S)** **Warm the STT model** with a tiny dummy transcription right after load, so the first real dictation of a session doesn't pay ANE compilation.

## 2. Accuracy

- [ ] **(S)** **Evaluate `distil-large-v3` as the default STT model** (currently `small.en`) — measure accuracy gain vs latency cost on real dictations.
- [ ] **(M)** **Dictionary biasing in the speech model itself** — feed personal-dictionary terms to Whisper as a decoding prompt (WhisperKit `promptTokens`) so names come out right at transcription time, not just fixed afterwards. This is how commercial nails jargon on the first pass.
- [ ] **(M)** **Auto-learning dictionary** — when the user edits inserted text immediately after a dictation, capture the diff as a dictionary candidate and suggest it in Settings. (Local-only, of course.)
- [ ] **(S)** **Number/date/format normalization** in the rule pass — "twenty five percent" → "25%", "three thirty pm" → "3:30 PM" (Whisper does some of this; catch the rest).

## 3. Formatting intelligence

- [ ] **(M)** **Spoken punctuation & control commands** — "new line", "new paragraph", "quote … end quote" handled deterministically in the rule pass (never leave it to the LLM).
- [ ] **(M)** **Per-app custom instructions** — let the user attach their own style notes to specific apps ("in Obsidian, use markdown headings"), extending the built-in tone profiles.
- [ ] **(L)** **Personal style matching** — learn the user's tone from local samples of their writing (e.g. pasted examples) instead of generic casual/professional presets. commercial's "sounds like you" feature, done locally.
- [ ] **(M)** **Better long-dictation structure** — paragraph splitting for multi-minute rambles; the current few-shot examples only cover 1–3 sentence utterances.
- [ ] **(S)** **Grow the few-shot bank** from real-world failures — keep a small corpus of messy-transcript → ideal-output pairs and iterate on it as bad cleanups are noticed.

## 4. Feature parity with commercial Flow

- [ ] **(M)** **Multilingual dictation** — switch to a multilingual STT model with language auto-detect; commercial supports 100+ languages with mid-sentence switching.
- [ ] **(S)** **Hands-free toggle mode** — tap-to-start / tap-to-stop as an alternative to hold-to-talk (commercial has both).
- [ ] **(S)** **Esc cancels an in-progress dictation** (discard recording without inserting).
- [ ] **(M)** **Snippets with placeholders** — "my intro ⟨name⟩" → expansion with a tab-through blank.
- [ ] **(M)** **Command-mode follow-ups** — after an edit, speak another instruction that applies to the same text ("now make it friendlier") without reselecting.
- [ ] **(S)** **Basic usage stats** — words dictated, time saved vs typing (commercial's dashboard), computed and stored locally.

## 5. UX & fit-and-finish

- [ ] **(S)** **App icon** (menu bar + app bundle).
- [ ] **(M)** **First-run onboarding window** — walk through mic/Accessibility permissions, the 🌐-key setting, model download progress, and a "try it here" practice field. Currently the printed checklist in `build.sh` does this job poorly.
- [ ] **(S)** **Pill polish** — animate in/out, handle multiple displays (follow the screen with the focused window, not `NSScreen.main`), respect Reduce Motion.
- [ ] **(S)** **Menu bar icon animation** while recording (level-reactive, like commercial's).
- [ ] **(M)** **Settings redesign into tabs** (General / Formatting / Dictionary / Snippets / Advanced) as the option count grows.
- [ ] **(M)** **Arbitrary hotkey capture** — record any key/combo in Settings instead of the fixed three choices.

## 6. Reliability & compatibility

- [ ] **(M)** **Secure-input awareness** — detect password fields (`IsSecureEventInputEnabled`) and refuse to record/insert, with a pill explanation.
- [ ] **(M)** **Per-app insertion quirks** — audit the AX path in Electron apps, terminals (trailing-newline behavior), Java apps, and browsers; maintain a fallback list.
- [ ] **(S)** **Clipboard restore robustness** — preserve non-string pasteboard contents (images, rich text) across the paste fallback, not just plain text.
- [ ] **(S)** **Input-device changes** — handle AirPods connecting/disconnecting mid-session without a stale audio engine.
- [ ] **(M)** **Graceful degradation UI** — one place that shows why something isn't working (mic permission, AX permission, model missing, Ollama down) instead of NSLog.

## 7. Distribution & maintenance

- [ ] **(M)** **Developer ID signing + notarization** — stable identity fixes the "re-grant Accessibility after every rebuild" annoyance and removes Gatekeeper friction. (Requires a $99/yr Apple Developer account.)
- [ ] **(S)** **DMG packaging** so it installs like a normal Mac app.
- [ ] **(M)** **Auto-updates** via Sparkle.
- [ ] **(M)** **CI on GitHub Actions** (macOS runner): build + tests on every push, so compile errors are caught without a manual `build.sh` run.
- [ ] **(M)** **Unit tests** for the pure logic: `TranscriptCleaner`, `SnippetExpander`, LLM output sanity checks, history store.
- [ ] **(S)** **Latency benchmark script** — a repeatable measurement of transcribe/polish times across models, so speed work is data-driven.

## Explicit non-goals

commercial Flow features we deliberately will not copy — they conflict with the project's reason to exist (ADR 0001):

- Cloud transcription or cloud LLMs in the dictation path
- Accounts, sync, telemetry, usage analytics that leave the device
- Screenshot/URL-based context awareness (we use the frontmost app's bundle ID only)
- iOS/Android/Windows apps (macOS-only for the foreseeable future)
