# Future Improvements

The outstanding work to bring George's Words to commercial Flow's level of polish and functionality — everything not already shipped or actively in progress. Sourced from the [commercial Flow deep-dive](docs/research/competitive-research.md) feature inventory and observations from daily use. Effort: **S** (hours), **M** (days), **L** (a milestone).

When we start something from this list, move it out of here and into the work itself (commit/ADR); when new gaps show up in daily use, add them. Items carry stable numbers (e.g. **5.1**) so we can refer to them — when an item leaves the list, retire its number rather than renumbering the rest.

## 1. Speed & responsiveness — lower priority as of 2026-07-05

**Verdict recorded 2026-07-05: Zach is happy with both speed and quality.** Settled configuration: Parakeet v3 for transcription (~0.1–0.2 s) + `qwen2.5:1.5b` light polish via the app's built-in engine (~1.3 s warm; 1.1's smaller-model experiment is thereby closed). Everything below is next-level speed work for whenever the appetite returns:

- [ ] **1.2 (M)** **Speculative polish.** While recording, whenever the speaker goes quiet ~1 s, speculatively polish the transcript-so-far in the background; on key release, if nothing more was said, the polished result is already ready → text appears near-instantly. Keep talking → discard the speculation (local compute, costs nothing). Architecturally just a cache in front of the existing pipeline: a miss falls back to today's behavior, never worse. Gets ~90% of the "streaming" benefit for ~10% of the work.
- [ ] **1.3 (L)** **True streaming polish** — polish sentence-by-sentence *while* speaking. Parked until real usage demands it (long-form dictation): hard problems include self-corrections spanning sentence boundaries ("…Tuesday. Wait, no, Friday"), tone consistency across separately-polished fragments, and sentence segmentation on unstable ASR output. Weeks of tuning, real quality risk.
- [ ] **1.5 (M)** **Apple Foundation Models** (macOS 26+) as the polish engine — Apple's built-in on-device ~3B model; would remove the Ollama install entirely for users on new macOS. Needs a macOS 26 SDK build path.

## 2. Accuracy

- [ ] **2.2 (M, lower priority)** **Dictionary biasing in the speech model itself** — feed personal-dictionary terms to the recognizer so names come out right at transcription time, not just fixed afterwards (commercial's trick for jargon). Note: the known mechanism (WhisperKit `promptTokens`) only applies to the Whisper fallback engine; whether FluidAudio/Parakeet supports biasing needs research first. Deprioritized 2026-07-05 — transcription accuracy is already "doing really well", and learned `heard -> Correct` mappings cover the misses. (2.1, the Whisper model-size evaluation, retired for the same reason: Whisper is only the fallback engine now.)
- [ ] **2.5 (M)** **Auto-learning dictionary isn't catching corrections well** (Zach, 2026-07-03, same day it shipped — details TBD from real use). Debugging leads, roughly in order of suspicion: (a) the fixed ~6 s re-read window — corrections made later are invisible; (b) the AX field re-read returning nothing in the apps he dictates into (Electron apps often fail `AXValue` reads — log the failure reason); (c) filters too strict — similarity ≥ 0.35, stopword-only rejection, or the ≥60% LCS gate discarding legit fixes; (d) suggestions being learned but not noticed in the Dictionary tab (surface a subtle badge/notification when one arrives?). First step: add a debug log line per stage (read ok? aligned? filtered why?) so a failing dictation can be diagnosed from Console instead of guesswork. See ADR 0005 for the design.

## 3. Formatting intelligence — next-level polish, lower priority as of 2026-07-05

- [ ] **3.3 (L)** **Personal style matching** — learn the user's tone from local samples of their writing (e.g. pasted examples) instead of generic casual/professional presets. commercial's "sounds like you" feature, done locally.
- [ ] **3.5 (S)** **Grow the few-shot bank** from real-world failures — keep a small corpus of messy-transcript → ideal-output pairs and iterate on it as bad cleanups are noticed.

## 4. Feature parity with commercial Flow

- [ ] **4.1 (M)** **Multilingual dictation** — switch to a multilingual STT model with language auto-detect; commercial supports 100+ languages with mid-sentence switching.
- [ ] **4.2 (M)** **Snippets with placeholders** — "my intro ⟨name⟩" → expansion with a tab-through blank.

*(4.3, command-mode follow-ups, shipped 2026-07-05: with nothing selected, the command key re-targets the last text the app inserted — same app, within 3 minutes, caret still in place — so "now make it friendlier" works without reselecting.)*

## 5. UX & fit-and-finish

*(Nothing open — the 5.x items all shipped with the Dock-app redesign and onboarding. 5.3, tabbed Settings, is retired for good: shipped 2026-07-05, reverted the same day — Zach prefers the single scrolling list.)*

## 6. Reliability & compatibility

- [ ] **6.2 (M)** **Per-app insertion quirks** — audit the AX path in Electron apps, terminals (trailing-newline behavior), Java apps, and browsers; maintain a fallback list.
- [ ] **6.4 (S)** **Escape the iCloud repo trap** — second incident 2026-07-04: iCloud's file provider wedged mid-session, blocking all local git reads; the self-updater's pull hung to its 120 s timeout and even `git status` froze until a reboot (first incident was the codesign xattr race that forced temp-dir staging). Two-part fix: (a) move the checkout out of iCloud-synced Desktop (e.g. `~/georges-words` — permissions survive via the stable signing identity; update CLAUDE.md paths after); (b) updater polish: when the pull times out, say "this usually means iCloud has wedged the repo — see Troubleshooting" instead of a generic failure, and consider a pre-flight `git status` probe with a 5 s timeout so the spinner never runs long on a dead filesystem.

## 7. Distribution & maintenance

- [ ] **7.1 (M→S)** **Developer ID signing + notarization — nearly done (2026-07-04).** Secrets are in, CI signs with hardened runtime + entitlements, DMGs build and submit cleanly; the only outstanding piece is Apple's notary queue clearing the first submission (sat "In Progress" for hours — a documented first-submission pattern; credentials verified good, no Invalid verdict). A retry loop re-runs `release.yml` every ~2 h until 2026-07-07 and push-notifies Zach on any terminal outcome. Close this item when the first Accepted verdict lands.
- [ ] **7.3 (M)** **Auto-updates** via Sparkle — becomes real the moment the DMG lands on the first non-developer Mac (Zach's wife's): DMG installs can't self-update via git like the source checkout does. (7.6, the latency benchmark script, retired 2026-07-05 — speed is settled and the Home timing caption covers day-to-day monitoring.)

## Explicit non-goals

commercial Flow features we deliberately will not copy — they conflict with the project's reason to exist (ADR 0001):

- **NG-1** Cloud transcription or cloud LLMs in the dictation path
- **NG-2** Accounts, sync, telemetry, usage analytics that leave the device
- **NG-3** Screenshot/URL-based context awareness (we use the frontmost app's bundle ID only)
- **NG-4** iOS/Android/Windows apps (macOS-only for the foreseeable future)
