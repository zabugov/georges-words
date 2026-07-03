# Future Improvements

The outstanding work to bring George's Words to commercial Flow's level of polish and functionality — everything not already shipped or actively in progress. Sourced from the [commercial Flow deep-dive](docs/research/competitive-research.md) feature inventory and observations from daily use. Effort: **S** (hours), **M** (days), **L** (a milestone).

> **⏭️ Next session — testing pass (added late 2026-07-03):** two things shipped
> at the end of the session with only a quick smoke test; exercise them properly
> in daily use before building more:
> 1. **"Keep my words" light polish (new default)** — verify ums/false starts are
>    removed, self-corrections applied, and wording otherwise untouched across
>    real dictations (Slack, email, longer rambles). Watch for the fidelity gate
>    rejecting too often (polish silently falling back to rule-cleaned text —
>    if suspicious, check Console for "Light polish rejected").
> 2. **`qwen2.5:1.5b` as the polish model** — initial impression good; confirm
>    speed ("Last: … polish" in the menu) and quality hold up vs `qwen2.5:3b`,
>    then record the verdict here.

When we start something from this list, move it out of here and into the work itself (commit/ADR); when new gaps show up in daily use, add them. Items carry stable numbers (e.g. **5.1**) so we can refer to them — when an item leaves the list, retire its number rather than renumbering the rest.

## 1. Speed & responsiveness

**Baseline as of 2026-07-03 (Parakeet + qwen2.5:3b on Zach's machine): 0.2 s transcribe + 1.4 s polish.** Transcription is solved; the LLM polish is ~90% of the remaining wait. Analysis from the 07-03 session:

- [ ] **1.1 (S)** **Smaller polish model — in progress.** `qwen2.5:1.5b` is pulled and selected (2026-07-03, "seems to be working well"); confirm over a few days of use (see testing note above), then consider trying `llama3.2:1b` / `gemma3:1b` for another speed step. Revert = pick `qwen2.5:3b` in the Settings dropdown.
- [ ] **1.2 (M)** **Speculative polish — the recommended next build.** While recording, whenever the speaker goes quiet ~1 s, speculatively polish the transcript-so-far in the background; on key release, if nothing more was said, the polished result is already ready → text appears near-instantly. Keep talking → discard the speculation (local compute, costs nothing). Architecturally just a cache in front of the existing pipeline: a miss falls back to today's behavior, never worse. Gets ~90% of the "streaming" benefit for ~10% of the work.
- [ ] **1.3 (L)** **True streaming polish** — polish sentence-by-sentence *while* speaking. Parked until real usage demands it (long-form dictation): hard problems include self-corrections spanning sentence boundaries ("…Tuesday. Wait, no, Friday"), tone consistency across separately-polished fragments, and sentence segmentation on unstable ASR output. Weeks of tuning, real quality risk.
- [ ] **1.5 (M)** **Apple Foundation Models** (macOS 26+) as the polish engine — Apple's built-in on-device ~3B model; would remove the Ollama install entirely for users on new macOS. Needs a macOS 26 SDK build path.

## 2. Accuracy

- [ ] **2.1 (S)** **Evaluate `distil-large-v3` as the default STT model** (currently `small.en`) — measure accuracy gain vs latency cost on real dictations.
- [ ] **2.2 (M)** **Dictionary biasing in the speech model itself** — feed personal-dictionary terms to Whisper as a decoding prompt (WhisperKit `promptTokens`) so names come out right at transcription time, not just fixed afterwards. This is how commercial nails jargon on the first pass.

## 3. Formatting intelligence

- [ ] **3.3 (L)** **Personal style matching** — learn the user's tone from local samples of their writing (e.g. pasted examples) instead of generic casual/professional presets. commercial's "sounds like you" feature, done locally.
- [ ] **3.4 (M)** **Better long-dictation structure** — paragraph splitting for multi-minute rambles; the current few-shot examples only cover 1–3 sentence utterances.
- [ ] **3.5 (S)** **Grow the few-shot bank** from real-world failures — keep a small corpus of messy-transcript → ideal-output pairs and iterate on it as bad cleanups are noticed.

## 4. Feature parity with commercial Flow

- [ ] **4.1 (M)** **Multilingual dictation** — switch to a multilingual STT model with language auto-detect; commercial supports 100+ languages with mid-sentence switching.
- [ ] **4.2 (M)** **Snippets with placeholders** — "my intro ⟨name⟩" → expansion with a tab-through blank.
- [ ] **4.3 (M)** **Command-mode follow-ups** — after an edit, speak another instruction that applies to the same text ("now make it friendlier") without reselecting.

## 5. UX & fit-and-finish

- [ ] **5.2 (M)** **First-run onboarding window** — walk through mic/Accessibility permissions, the 🌐-key setting, model download progress, and a "try it here" practice field. Currently the printed checklist in `build.sh` does this job poorly.
- [ ] **5.3 (M)** **Settings redesign into tabs** (General / Formatting / Dictionary / Snippets / Advanced) as the option count grows.
- [ ] **5.4 (M)** **Arbitrary hotkey capture** — record any key/combo in Settings instead of the fixed three choices.

## 6. Reliability & compatibility

- [ ] **6.2 (M)** **Per-app insertion quirks** — audit the AX path in Electron apps, terminals (trailing-newline behavior), Java apps, and browsers; maintain a fallback list.

## 7. Distribution & maintenance

- [ ] **7.1 (M)** **Developer ID signing + notarization** — removes Gatekeeper friction for distributing to other people. (Requires a $99/yr Apple Developer account. The local "re-grant Accessibility after every rebuild" annoyance is already solved by `app/setup-signing.sh`'s self-signed identity.)
- [ ] **7.2 (S)** **DMG packaging** so it installs like a normal Mac app.
- [ ] **7.3 (M)** **Auto-updates** via Sparkle — for a binary-distributed app later. (The source checkout already self-updates: menu bar → Check for Updates… pulls, rebuilds, and relaunches.)
- [ ] **7.6 (S)** **Latency benchmark script** — a repeatable measurement of transcribe/polish times across models, so speed work is data-driven.

## Explicit non-goals

commercial Flow features we deliberately will not copy — they conflict with the project's reason to exist (ADR 0001):

- **NG-1** Cloud transcription or cloud LLMs in the dictation path
- **NG-2** Accounts, sync, telemetry, usage analytics that leave the device
- **NG-3** Screenshot/URL-based context awareness (we use the frontmost app's bundle ID only)
- **NG-4** iOS/Android/Windows apps (macOS-only for the foreseeable future)
