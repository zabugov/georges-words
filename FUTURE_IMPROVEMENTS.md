# Future Improvements

The outstanding work to bring George's Words to commercial Flow's level of polish and functionality — everything not already shipped or actively in progress. Sourced from the [commercial Flow deep-dive](docs/research/competitive-research.md) feature inventory and observations from daily use. Effort: **S** (hours), **M** (days), **L** (a milestone).

When we start something from this list, move it out of here and into the work itself (commit/ADR); when new gaps show up in daily use, add them.

## 1. Speed & responsiveness

**Baseline as of 2026-07-03 (Parakeet + qwen2.5:3b on Zach's machine): 0.2 s transcribe + 1.4 s polish.** Transcription is solved; the LLM polish is ~90% of the remaining wait. Analysis from the 07-03 session:

- [ ] **(S)** **Ollama experiment — smaller polish model.** Run `ollama pull qwen2.5:1.5b`, set it in Settings → AI polish, and compare: should roughly halve the 1.4 s polish. If self-corrections/rewrites get worse, revert the field to `qwen2.5:3b` (30-second undo). If quality holds, consider making it the default and also try `llama3.2:1b` / `gemma3:1b`.
- [ ] **(M)** **Speculative polish — the recommended next build.** While recording, whenever the speaker goes quiet ~1 s, speculatively polish the transcript-so-far in the background; on key release, if nothing more was said, the polished result is already ready → text appears near-instantly. Keep talking → discard the speculation (local compute, costs nothing). Architecturally just a cache in front of the existing pipeline: a miss falls back to today's behavior, never worse. Gets ~90% of the "streaming" benefit for ~10% of the work.
- [ ] **(L)** **True streaming polish** — polish sentence-by-sentence *while* speaking. Parked until real usage demands it (long-form dictation): hard problems include self-corrections spanning sentence boundaries ("…Tuesday. Wait, no, Friday"), tone consistency across separately-polished fragments, and sentence segmentation on unstable ASR output. Weeks of tuning, real quality risk.
- ~~Streaming transcription~~ — **obsolete**: it existed to hide multi-second transcription, and Parakeet does full utterances in 0.2 s. Building it (FluidAudio `SlidingWindowAsrManager`, chunk stitching, word-revision handling) would be days of work to save a fifth of a second.
- [ ] **(M)** **Apple Foundation Models** (macOS 26+) as the polish engine — Apple's built-in on-device ~3B model; would remove the Ollama install entirely for users on new macOS. Needs a macOS 26 SDK build path.

## 2. Accuracy

- [ ] **(S)** **Evaluate `distil-large-v3` as the default STT model** (currently `small.en`) — measure accuracy gain vs latency cost on real dictations.
- [ ] **(M)** **Dictionary biasing in the speech model itself** — feed personal-dictionary terms to Whisper as a decoding prompt (WhisperKit `promptTokens`) so names come out right at transcription time, not just fixed afterwards. This is how commercial nails jargon on the first pass.
- [ ] **(M/L)** **Auto-learning dictionary** — learn from the user's corrections so misheard words come out right next time. Not trivial: the app inserts text into *other* apps and then loses sight of it, so noticing a correction requires re-reading the focused text field (Accessibility API) a few seconds after insertion and diffing it against what was inserted. Sketch: after each insertion, snapshot the inserted string; ~5 s later read the field's value via AX, align the two, and extract word-level substitutions (e.g. "coober netties" → "Kubernetes"); collect candidates locally and surface them in Settings as one-click "add to dictionary" suggestions (auto-adding risks learning garbage). Fallback for apps where AX reads fail: a "Correct last transcript…" menu action where the user pastes/edits the right version and the diff is learned from that. All local, per ADR 0001.
- [ ] **(S)** **Spelled-out number normalization** — "twenty five percent" → "25%", "three thirty pm" → "3:30 PM". (Digit-adjacent cases like "50 percent" → "50%" are done; the spelled-out parsing remains.)

## 3. Formatting intelligence

- [ ] **(M)** **Polish strength setting — "keep my words" mode (owner request 2026-07-03).** The current polish rewords too aggressively; the prompt asks for "polished written text," which invites paraphrasing. Add a Settings choice like **Light (default): keep my exact words** — remove ums/uhs and false starts, fix punctuation/capitalization, apply self-corrections, and nothing else — vs **Full: restructure for clarity** (today's behavior). Implementation: two prompt variants with their own few-shot examples; the Light examples must show outputs that are word-for-word identical to the input minus fillers, so the model learns that NOT changing text is the correct answer. Consider a sanity check that rejects Light-mode outputs whose word overlap with the input drops too low.
- [ ] **(M)** **Spoken punctuation & control commands** — "new line", "new paragraph", "quote … end quote" handled deterministically in the rule pass (never leave it to the LLM).
- [ ] **(M)** **Per-app custom instructions** — let the user attach their own style notes to specific apps ("in Obsidian, use markdown headings"), extending the built-in tone profiles.
- [ ] **(L)** **Personal style matching** — learn the user's tone from local samples of their writing (e.g. pasted examples) instead of generic casual/professional presets. commercial's "sounds like you" feature, done locally.
- [ ] **(M)** **Better long-dictation structure** — paragraph splitting for multi-minute rambles; the current few-shot examples only cover 1–3 sentence utterances.
- [ ] **(S)** **Grow the few-shot bank** from real-world failures — keep a small corpus of messy-transcript → ideal-output pairs and iterate on it as bad cleanups are noticed.

## 4. Feature parity with commercial Flow

- [ ] **(M)** **Multilingual dictation** — switch to a multilingual STT model with language auto-detect; commercial supports 100+ languages with mid-sentence switching.
- [ ] **(M)** **Snippets with placeholders** — "my intro ⟨name⟩" → expansion with a tab-through blank.
- [ ] **(M)** **Command-mode follow-ups** — after an edit, speak another instruction that applies to the same text ("now make it friendlier") without reselecting.

## 5. UX & fit-and-finish

- [ ] **(S)** **App icon** (menu bar + app bundle).
- [ ] **(M)** **First-run onboarding window** — walk through mic/Accessibility permissions, the 🌐-key setting, model download progress, and a "try it here" practice field. Currently the printed checklist in `build.sh` does this job poorly.
- [ ] **(M)** **Settings redesign into tabs** (General / Formatting / Dictionary / Snippets / Advanced) as the option count grows.
- [ ] **(M)** **Arbitrary hotkey capture** — record any key/combo in Settings instead of the fixed three choices.

## 6. Reliability & compatibility

- [ ] **(M)** **Secure-input awareness** — detect password fields (`IsSecureEventInputEnabled`) and refuse to record/insert, with a pill explanation.
- [ ] **(M)** **Per-app insertion quirks** — audit the AX path in Electron apps, terminals (trailing-newline behavior), Java apps, and browsers; maintain a fallback list.
- [ ] **(M)** **Graceful degradation UI** — one place that shows why something isn't working (mic permission, AX permission, model missing, Ollama down) instead of NSLog.

## 7. Distribution & maintenance

- [ ] **(M)** **Developer ID signing + notarization** — removes Gatekeeper friction for distributing to other people. (Requires a $99/yr Apple Developer account. The local "re-grant Accessibility after every rebuild" annoyance is already solved by `app/setup-signing.sh`'s self-signed identity.)
- [ ] **(S)** **DMG packaging** so it installs like a normal Mac app.
- [ ] **(M)** **Auto-updates** via Sparkle — for a binary-distributed app later. (The source checkout already self-updates: menu bar → Check for Updates… pulls, rebuilds, and relaunches.)
- [ ] **(M)** **CI on GitHub Actions** (macOS runner): build + tests on every push, so compile errors are caught without a manual `build.sh` run.
- [ ] **(M)** **Unit tests** for the pure logic: `TranscriptCleaner`, `SnippetExpander`, LLM output sanity checks, history store.
- [ ] **(S)** **Latency benchmark script** — a repeatable measurement of transcribe/polish times across models, so speed work is data-driven.

## Explicit non-goals

commercial Flow features we deliberately will not copy — they conflict with the project's reason to exist (ADR 0001):

- Cloud transcription or cloud LLMs in the dictation path
- Accounts, sync, telemetry, usage analytics that leave the device
- Screenshot/URL-based context awareness (we use the frontmost app's bundle ID only)
- iOS/Android/Windows apps (macOS-only for the foreseeable future)
