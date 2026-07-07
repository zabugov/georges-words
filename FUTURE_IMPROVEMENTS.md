# Future Improvements

The outstanding work to bring George's Words to the level of polish and functionality of the best commercial dictation apps — everything not already shipped or actively in progress. Sourced from the competitive research notes (kept outside the repo) and observations from daily use. Effort: **S** (hours), **M** (days), **L** (a milestone).

When we start something from this list, move it out of here and into the work itself (commit/ADR); when new gaps show up in daily use, add them. Items carry stable numbers (e.g. **5.1**) so we can refer to them — when an item leaves the list, retire its number rather than renumbering the rest.

## 1. Speed & responsiveness — lower priority as of 2026-07-05

**Verdict recorded 2026-07-05: Zach is happy with both speed and quality.** Settled configuration: Parakeet v3 for transcription (~0.1–0.2 s) + `qwen2.5:1.5b` light polish via the app's built-in engine (~1.3 s warm; 1.1's smaller-model experiment is thereby closed). Everything below is next-level speed work for whenever the appetite returns:

- [ ] **1.2 (M)** **Speculative polish.** While recording, whenever the speaker goes quiet ~1 s, speculatively polish the transcript-so-far in the background; on key release, if nothing more was said, the polished result is already ready → text appears near-instantly. Keep talking → discard the speculation (local compute, costs nothing). Architecturally just a cache in front of the existing pipeline: a miss falls back to today's behavior, never worse. Gets ~90% of the "streaming" benefit for ~10% of the work.
- [ ] **1.3 (L)** **True streaming polish** — polish sentence-by-sentence *while* speaking. Parked until real usage demands it (long-form dictation): hard problems include self-corrections spanning sentence boundaries ("…Tuesday. Wait, no, Friday"), tone consistency across separately-polished fragments, and sentence segmentation on unstable ASR output. Weeks of tuning, real quality risk.
- [ ] **1.5 (M)** **Apple Foundation Models** (macOS 26+) as the polish engine — Apple's built-in on-device ~3B model; would remove the Ollama install entirely for users on new macOS. Needs a macOS 26 SDK build path.

## 2. Accuracy

- [ ] **2.2 (M, lower priority)** **Dictionary biasing in the speech model itself** — feed personal-dictionary terms to the recognizer so names come out right at transcription time, not just fixed afterwards (the commercial apps' trick for jargon). Note: the known mechanism (WhisperKit `promptTokens`) only applies to the Whisper fallback engine; whether FluidAudio/Parakeet supports biasing needs research first. Deprioritized 2026-07-05 — transcription accuracy is already "doing really well", and learned `heard -> Correct` mappings cover the misses. (2.1, the Whisper model-size evaluation, retired for the same reason: Whisper is only the fallback engine now.)
- [ ] **2.5 (M)** **Auto-learning dictionary isn't catching corrections well** (Zach, 2026-07-03, same day it shipped — details TBD from real use). Debugging leads, roughly in order of suspicion: (a) the fixed ~6 s re-read window — corrections made later are invisible; (b) the AX field re-read returning nothing in the apps he dictates into (Electron trees sleep until woken — partially addressed 2026-07-05 by AXFocus, which now wakes them and logs to debug.log); (c) filters too strict — similarity ≥ 0.35, stopword-only rejection, or the ≥60% LCS gate discarding legit fixes; (d) suggestions being learned but not noticed in the Dictionary tab (surface a subtle badge/notification when one arrives?); (e) from the 2026-07-05 code review: the re-read only validates the frontmost bundle ID — it may diff against a *different field* in the same app and learn junk; retain and revalidate the exact AX element. See ADR 0005 for the design.

## 3. Formatting intelligence — next-level polish, lower priority as of 2026-07-05

- [ ] **3.3 (L)** **Personal style matching** — learn the user's tone from local samples of their writing (e.g. pasted examples) instead of generic casual/professional presets. the commercial "sounds like you" feature, done locally.
- [ ] **3.5 (S)** **Grow the few-shot bank** from real-world failures — keep a small corpus of messy-transcript → ideal-output pairs and iterate on it as bad cleanups are noticed.
- [ ] **3.7 (S)** **Keep the raw transcript, offer "use raw instead"** (from the 2026-07-05 code review) — retain the pre-polish transcript alongside the polished one; a click on Home/History swaps the last insertion to the raw version. Makes the "polish can't lose your words" promise true by construction instead of by validation heuristics.

## 4. Feature parity with commercial dictation apps

- [ ] **4.1 (M)** **Multilingual dictation** — switch to a multilingual STT model with language auto-detect; the commercial apps support 100+ languages with mid-sentence switching.
- [ ] **4.2 (M)** **Snippets with placeholders** — "my intro ⟨name⟩" → expansion with a tab-through blank.
- [ ] **4.4 (M)** **Re-add command mode, properly this time.** Removed entirely 2026-07-05 (along with 4.3, its follow-up extension): after a command-mode use, normal dictation broke completely, and the feature was barely used — not worth debugging in place. Salvage from git history (pre-removal): the edit prompt + few-shots (`LLMFormatter.applyCommand`), and `SelectionReader` (AX read with ⌘C fallback, plus reselect-by-value-search for no-selection follow-ups — the reselect *worked*, even in Electron apps once `AXFocus` woke their accessibility tree). Prime suspect for the breakage: the press/latch state machine (`mode`/`toggleLatched`/`ignoreNextRelease`) was shared between the two hotkeys and wasn't designed for it — a quick command tap likely latches toggle mode and eats the next dictation press. If rebuilt: give command mode its own state machine instead of sharing dictation's.
- [ ] **4.5 (M)** **Voice editing pack** (from the 2026-07-05 code review) — "delete last word/sentence", "undo that", spoken punctuation ("open parenthesis", "semicolon"), a spoken "no polish" escape, and a literal mode for code/URLs/identifiers. Builds on the existing spoken-commands layer in TranscriptCleaner.

## 5. UX & fit-and-finish

*(Nothing open — the 5.x items all shipped with the Dock-app redesign and onboarding. 5.3, tabbed Settings, is retired for good: shipped 2026-07-05, reverted the same day — Zach prefers the single scrolling list.)*

- [ ] **5.5 (S)** **Undo Last Insertion** (from the 2026-07-05 code review — its best product idea): a menu-bar item / Home button that removes the text the last dictation inserted, via the same AX select-and-replace machinery. Pairs with 3.7 (swap to raw).


## 6. Reliability & compatibility

- [ ] **6.2 (M)** **Per-app insertion quirks** — audit the AX path in Electron apps, terminals (trailing-newline behavior), Java apps, and browsers; maintain a fallback list.
- [ ] **6.4 (S)** **Escape the iCloud repo trap** — second incident 2026-07-04: iCloud's file provider wedged mid-session, blocking all local git reads; the self-updater's pull hung to its 120 s timeout and even `git status` froze until a reboot (first incident was the codesign xattr race that forced temp-dir staging). Two-part fix: (a) move the checkout out of iCloud-synced Desktop (e.g. `~/georges-words` — permissions survive via the stable signing identity; update CLAUDE.md paths after); (b) updater polish: when the pull times out, say "this usually means iCloud has wedged the repo — see Troubleshooting" instead of a generic failure, and consider a pre-flight `git status` probe with a 5 s timeout so the spinner never runs long on a dead filesystem.
- [ ] **6.5 (S)** **Input-device picker + silent-mic warning** (code review) — choose which microphone the app records from, and warn when the input is muted, disconnected, or suspiciously quiet instead of producing empty transcripts.
- [ ] **6.6 (S)** **Insertion compatibility tester** (code review) — a Troubleshooting button that checks the currently focused app: can we read the field, is direct insertion verified, or will paste be used? Turns "it doesn't type into app X" reports into one click of diagnosis. Pairs with 6.2.
- [ ] **6.7 (S)** **Truly complete factory reset** (code review) — also delete the WhisperKit/FluidAudio model caches (they live outside Application Support/GeorgesWords), unregister launch-at-login, await engine shutdown before deleting, and surface deletion failures instead of `try?`-swallowing them.

## 7. Distribution & maintenance

*(7.1 closed 2026-07-06: Apple's first-notarizer hold lifted, the preserved DMG was stapled and validated — see docs/notarization-issue.md. 7.3 shipped 2026-07-06: Sparkle auto-updates for DMG installs, git-pull updater kept for the source checkout — see ADR 0007. 7.6 retired 2026-07-05.)*
- [ ] **7.10 (S)** **EdDSA-sign the Sparkle feed** — updates are currently validated by Apple Developer ID + notarization + HTTPS (ADR 0007's documented fallback). Adding a `SUPublicEDKey` + signing each release archive closes the remaining gap (a compromised GitHub account or expired cert scenario). Needs a private key held outside the repo (local keychain or a repo secret generated on a trusted machine).
- [ ] **7.8 (S)** **Export/import** settings, dictionary, snippets, and per-app notes (code review) — one JSON file out, one file in. The practical path for seeding a family member's Mac with a tuned dictionary.
- [ ] **7.9 (M)** **Internal hardening, incrementally** (code review, accepted in spirit): adopt @MainActor on the UI/state owners and enable strict concurrency in CI once clean; extract pieces of AppDelegate (recording session, insertion) opportunistically when touching them — no big-bang refactor.

## 8. Privacy controls (new section, from the 2026-07-05 code review)

The app already keeps everything on-device; these give the user control over what it keeps at all — they matter once family members are dictating.

- [ ] **8.1 (M)** **Per-app exclusion list** — never store history or learn corrections from chosen apps (password managers, banking, private browsing).
- [ ] **8.2 (S)** **History retention controls** — off entirely, session-only, or time-boxed, instead of always-keep-200.
- [ ] **8.3 (S)** **Correction-learning off switch** — one toggle to stop the auto-learning dictionary from watching post-dictation edits.

## 9. Going commercial (roadmap recorded 2026-07-06 — Zach wants to try it)

The stack is already commercially clean: Ollama (MIT), Qwen 2.5 **1.5B** (Apache 2.0 — the 3B variant is research-only, so check the license of any model size before switching defaults), Parakeet (CC-BY-4.0, attribution required), WhisperKit/Sparkle (MIT), FluidAudio (Apache 2.0), no GPL anywhere. The app's own code has **no license file on purpose**: visible is not reusable — do NOT add an open-source license while a paid future is on the table (one-way door). Distribution infrastructure (GitHub Releases + Hugging Face + Ollama registry) costs nothing and scales to tens of thousands of users as-is; the work below is trust, edge cases, and support capacity, ordered by the scale that demands it.

Two standing guardrails (from the 2026-07-06 external review, both adopted): **sharing the app free is unblocked today — the extra gates below apply to *charging***; and **do not overbuild business infrastructure** (no accounts, sync, dashboards, analytics, subscriptions, or license servers beyond activation until real demand exists — local-first simplicity is the product's strongest differentiator).

**Pending owner actions (updated 2026-07-07):** the code/pipeline halves of the "any scale" items are done; these are the manual clicks only Zach can do, roughly in priority order:

- [ ] **Test the download-page button** — do one fresh install through the site's exact "Download" button (`GeorgesWords.dmg`) right after the next release is cut; only then share the link (`https://zabugov.github.io/georges-words/`) with anyone non-technical. *(The stable-named asset ships from the next release onward — see 9.2.)*
- [ ] **Enable Discussions** — repo Settings → General → Features → Discussions. *(9.3)*
- [ ] **Enable private vulnerability reporting** — repo Settings → Advanced Security → Private vulnerability reporting. *(SECURITY.md already points at it.)*
- [ ] **Sparkle EdDSA keys** — PUBLIC key added to `Info.plist` 2026-07-07 (`SUPublicEDKey`). **Still must confirm before the next release:** the exported private key is set as repo secret `SPARKLE_ED_PRIVATE_KEY`. Both halves must ship together — once an app carrying `SUPublicEDKey` is installed, every *later* update it receives must be EdDSA-signed or Sparkle rejects it. *(7.10)*
- [ ] **Homebrew tap repo** — create empty public `zabugov/homebrew-georges-words`; the cask + automation follow. Lowest priority — a "when people ask for `brew install`" item, not a launch blocker. *(9.6)*

*(Done 2026-07-07: repo made public; GitHub Pages source set to "GitHub Actions" and the download page deployed live.)*

**Any scale (do first):**

- [x] **9.1** ~~Parakeet attribution line in About~~ — shipped 2026-07-06 (About → App section credits Parakeet/CC-BY-4.0, FluidAudio, WhisperKit, Ollama/Qwen, Sparkle).
- [ ] **9.2 (S)** **User-facing download page** — BUILT 2026-07-06, DEPLOYED LIVE 2026-07-07 at `https://zabugov.github.io/georges-words/` (`site/index.html` + `pages.yml`; Pages source now set to "GitHub Actions"). Releases attach a stable-named `GeorgesWords.dmg` so the page's download button survives version bumps. **One thing still open:** the stable `GeorgesWords.dmg` asset ships from the NEXT release onward — test one fresh install through the page's exact button before sharing the link with anyone non-technical. Until then the button will 404; the Releases page links work today.
- [ ] **9.3 (S)** **Issue templates + Discussions** — templates shipped 2026-07-06 (bug report asks for the 9.5 diagnostic file). **Waiting on one owner click:** repo Settings → General → Features → enable Discussions.

**Hundreds of users:**

- [x] **9.4** ~~Unsupported-Mac gating~~ — resolved 2026-07-06: `LSMinimumSystemVersion` 14.0 makes macOS itself show a clear "requires macOS 14" message, and the download page states the Apple-Silicon requirement prominently. (A friendly Intel-specific message would need a universal-binary stub — deliberately skipped as over-engineering; Intel users see macOS's standard incompatibility notice.)
- [x] **9.5** ~~Diagnostic bundle export~~ — shipped 2026-07-06: Troubleshooting → "Save Diagnostic Report…" (versions, permissions, engine state, settings flags, debug.log tail — never voice/transcripts/dictionary).
- [ ] **9.6 (S)** **Homebrew cask** — needs a tap repo named `homebrew-georges-words` under the owner's account (official homebrew/cask requires notability we don't have yet). **Owner action:** create that empty public repo (or add it to a session via add_repo) and the cask file + release automation follow.
- [ ] 7.10 (EdDSA feed signing) — **required before taking money** (review, adopted: an unsigned update feed on a paid app is an avoidable trust gap; verify one signed appcast + one real update before charging). Pipeline side DONE 2026-07-06: releases sign the DMG and stamp `sparkle:edSignature` into the appcast automatically once the `SPARKLE_ED_PRIVATE_KEY` secret exists (silent no-op until then). PUBLIC key added to `Info.plist` 2026-07-07 (`SUPublicEDKey`). **Remaining:** confirm the private key is set as the `SPARKLE_ED_PRIVATE_KEY` repo secret *before* the next release, because both must ship together — an installed app that has `SUPublicEDKey` will reject any later update lacking a valid `sparkle:edSignature`. The pipeline guards this (`test -n "$ED_SIG"` fails the build if the secret is set but signing produces nothing), but if the secret is missing entirely the release ships unsigned and the *following* update would be rejected. Verify one signed appcast entry + one successful real update right after the first signed release.

**Thousands+:**

- [ ] **9.7 (M)** **Two-repo split when code privacy matters**: private code repo + public releases repo holding only DMGs, appcast, and the download page (published across via a token). Sequencing is critical so no installed copy is stranded: ship a release whose feed URL points at the new public location FIRST, let installs update, then flip the code private. Note: a private code repo re-introduces the Actions billing limit (macOS minutes at 10×) — trim CI or budget a few dollars/month.
- [ ] **9.8 (M)** **Payments + license keys** — App Store is impossible (sandboxing vs the Accessibility API), so direct sales: Paddle / Lemon Squeezy **hosted** checkout and license issuance (never build billing), an in-app activation that stores a local entitlement and touches the network only on explicit activate/deactivate — **dictation must never depend on a network call**. Decide the model first; recommended v1 (review, adopted): one-time purchase with updates for a stated period, no accounts, no always-online DRM.
- [ ] **9.9 (S)** **Release notes as support** (expanded per review) — CHANGELOG, notes in the Sparkle update dialog, notes on the download page, and a short **known-issues** list for compatibility problems: every duplicate support report a note prevents is support capacity earned.
- [ ] **9.10 (M)** **Opt-in crash reporting** — opt-in only; the no-telemetry stance is the product's best marketing, and it must survive commercialization. 6.2/6.6 (insertion quirks + compatibility tester) become the main support-load reducers at this tier.

**Before taking a single payment (review additions, all adopted):**

- [ ] **9.13 (M)** **Customer-facing legal pages** — Privacy, Terms/EULA, refund policy, warranty limits, update expectations, sold-direct disclosure, and a support contact, linked from the site and the checkout. The one-paragraph privacy line is marketing copy, not commercial plumbing. Draft with a template service or lawyer-reviewed boilerplate when 9.8 starts.
- [ ] **9.14 (S)** **Private support intake** — a support email or private form for customers, because diagnostic reports (even redacted) describe someone's machine and don't belong on public issues by default. Bug template already warns about the public page (shipped 2026-07-06); this item is the private channel itself.
- [ ] **9.15 (M)** **Closed-beta support rehearsal** — before pricing: ~10 non-technical Macs end-to-end (fresh install from the site button, permissions, first downloads, dictation across Mail/browser/chat/docs, a Sparkle update, diagnostic export, factory reset, plus one deliberately unsupported Mac). Track install failure rate and the top support questions; they set the launch copy and the FAQ.
- [ ] Privacy controls **8.1–8.3 graduate to pre-payment requirements** (review, adopted): once strangers dictate work, legal, medical, or banking text, history retention controls, the learning off-switch, and per-app exclusions are part of the privacy promise, not polish.

**Tens of thousands and beyond:**

- [ ] **9.11 (L)** **Localization** — UI strings first (the dictation engines already handle 25 languages).
- [ ] **9.12 (S)** **Own domain for downloads + feed** — independence from raw.githubusercontent as a serving host, plus branding. Requires the same careful feed-URL migration as 9.7.

## Commercialization review triage (2026-07-06)

Codex's independent review of section 9 was integrated the same day. Adopted and already shipped: THIRD_PARTY_NOTICES.md as a release artifact, SECURITY.md with private vulnerability reporting, diagnostic-report path redaction, and the bug-template public-page warning. Adopted into the roadmap above: EdDSA reordered to before-money (7.10), paid-model guardrails folded into 9.8, release-notes-as-support into 9.9, legal pages (9.13), private support intake (9.14), closed-beta rehearsal (9.15), 8.1–8.3 promoted to pre-payment, the download-button test caveat on 9.2, and both standing guardrails in the section intro. Nothing was rejected outright — the one calibration applied: these gates block *charging*, not free sharing, which is unblocked as soon as the 9.2 button is tested.

## Code-review triage (2026-07-05)

CODE_REVIEW.md was triaged the same day it landed. Addressed immediately in code: wrong-app insertion guard, transactional updater, clipboard-restore race, audio-tap rollback, hands-free cap + preview bounds, wake-time hotkey reset, Swift 6 warning, pinned+verified engine download, random engine port, model-default/doc drift, WhisperKit pin, release-workflow tests, Whisper-only CI leg. Declined (deliberate choices, not oversights): updater process groups, opt-in signing setup, big-bang coordinator split, protocol seams everywhere, engine auth proxy, double-tap hands-free, menu-bar-only mode, encrypted backups, storage-usage screen.

## Explicit non-goals

Commercial-app features we deliberately will not copy — they conflict with the project's reason to exist (ADR 0001):

- **NG-1** Cloud transcription or cloud LLMs in the dictation path
- **NG-2** Accounts, sync, telemetry, usage analytics that leave the device
- **NG-3** Screenshot/URL-based context awareness (we use the frontmost app's bundle ID only)
- **NG-4** iOS/Android/Windows apps (macOS-only for the foreseeable future)
