# Future Improvements

This is the open backlog only. Finished work and historical triage notes belong in commits, ADRs, release notes, or the relevant docs — not in this file.

Effort guide: **S** = hours, **M** = days, **L** = a milestone. Item numbers are stable references; when an item ships, retire it instead of renumbering everything.

## Context and guardrails

- **Current baseline:** speed and quality are good enough for daily use. The settled default is Parakeet v3 for transcription plus `qwen2.5:1.5b` light polish through the app-managed local engine.
- **Privacy is the product:** audio and transcripts stay on-device. No cloud transcription, cloud polish, telemetry, accounts, sync, or usage analytics in the dictation path.
- **Commercial posture:** sharing free builds is unblocked once the download button is verified. Charging money has extra gates: signed updates, legal/support pages, private support intake, and privacy controls.
- **Business discipline:** do not overbuild business infrastructure until demand proves it. Prefer hosted checkout/license issuance; avoid accounts, dashboards, subscriptions, teams, or always-online DRM for v1.
- **Licensing posture:** the dependency stack is commercially usable, but model/library licenses and attributions must stay tracked in release artifacts. Do not add an open-source license for the app’s own code while a paid future is on the table.

## Immediate pre-commercial work

These are the highest-leverage items before sharing broadly or charging.

- [ ] **9.2 (S)** **Verify the public download flow.** After the next release, do one fresh install through the site’s exact Download button and confirm it fetches the stable `GeorgesWords.dmg` asset. Until this passes, send users to GitHub Releases instead of the website button.
- [ ] **7.10 (S)** **Verify EdDSA-signed Sparkle updates.** The signing pieces are wired; the remaining work is proof: cut a release, confirm `sparkle:edSignature` appears in `appcast.xml`, and update from an older build successfully. Treat this as required before taking payment.
- [ ] **9.13 (M)** **Customer-facing legal pages.** Add Privacy, Terms/EULA, refund policy, warranty limits, update expectations, sold-direct disclosure, and support contact links on the website and checkout flow.
- [ ] **9.14 (S)** **Private support intake.** Add a support email or private form. GitHub Issues/Discussions are fine for public bugs, but diagnostic reports should not be pushed into public threads by default.
- [ ] **9.15 (M)** **Closed-beta support rehearsal.** Test with about 10 nontechnical Macs: site download, install, permissions, first model downloads, dictation across common app types, Sparkle update, diagnostic export, factory reset/uninstall, and one unsupported Mac. Use the results to update launch copy, FAQ, and pricing assumptions.
- [ ] **8.1 (M)** **Per-app privacy exclusions.** Let users choose apps where history and correction learning are disabled.
- [ ] **8.2 (S)** **History retention controls.** Add options for off, session-only, time-boxed, or capped history instead of always keeping the last 200 entries.
- [ ] **8.3 (S)** **Correction-learning off switch.** One global toggle to stop watching post-dictation edits for learned corrections.
- [ ] **9.8 (M)** **Payments + license keys.** Direct sales only. Use hosted checkout and license issuance from a merchant-of-record provider. Recommended v1: one-time purchase, stated update window, no accounts, no always-online DRM. Activation should store a local entitlement and only touch the network on explicit activate/deactivate/manual refresh; normal dictation must never depend on the network.

## Reliability and support reducers

These reduce support load and make failures explainable.

- [ ] **2.5 (M)** **Improve auto-learning correction detection.** Main suspects: fixed re-read window, AX reads failing or waking late, strict similarity filters, learned suggestions not being visible enough, and validating only the frontmost app instead of the exact edited field. Keep ADR 0005 as the design reference.
- [ ] **6.2 (M)** **Per-app insertion quirks.** Audit direct insertion and paste fallback across Electron apps, browsers, terminals, Java apps, and secure/private fields; keep a compatibility list.
- [ ] **6.5 (S)** **Input-device picker + silent-mic warning.** Let users choose the microphone and warn when input is muted, disconnected, or suspiciously quiet.
- [ ] **6.6 (S)** **Insertion compatibility tester.** Add a Troubleshooting button that checks the focused app: can the field be read, can direct insertion be verified, or will paste fallback be used?
- [ ] **6.7 (S)** **Complete factory reset.** Delete all model caches, unregister launch-at-login, await engine shutdown before deletion, and surface deletion failures instead of silently ignoring them.
- [ ] **7.8 (S)** **Export/import.** Export and import settings, dictionary, snippets, and per-app notes as one JSON file.
- [ ] **7.9 (M)** **Incremental internal hardening.** Adopt `@MainActor` on UI/state owners, enable stricter concurrency checks once clean, and extract pieces of `AppDelegate` opportunistically when touching them. No big-bang refactor.
- [ ] **9.9 (S)** **Release notes as support.** Maintain a changelog, Sparkle update notes, website notes, and a short known-issues section for common compatibility problems.

## Product improvements

Useful, but not blockers for a first commercial test.

- [ ] **1.2 (M)** **Speculative polish.** While recording, polish transcript-so-far after a short pause; on key release, use the cached result if nothing changed. Discard speculation if the user keeps talking.
- [ ] **1.3 (L)** **True streaming polish.** Polish sentence-by-sentence while speaking. Hard cases: self-corrections across sentence boundaries, tone consistency, and segmentation on unstable ASR output.
- [ ] **1.5 (M)** **Apple Foundation Models polish engine.** Explore macOS 26+ on-device models as a way to remove the managed Ollama dependency for newer Macs.
- [ ] **2.2 (M)** **Dictionary biasing inside speech recognition.** Research whether the Parakeet/FluidAudio path supports biasing; WhisperKit prompt tokens only help the fallback engine.
- [ ] **3.3 (L)** **Personal style matching.** Learn tone from local user-provided writing samples instead of generic style presets.
- [ ] **3.5 (S)** **Grow the few-shot bank.** Keep a small local corpus of messy transcript → ideal output examples from real failures.
- [ ] **3.7 (S)** **Keep raw transcript + “use raw instead.”** Store the raw transcript alongside polished text and allow replacing the last insertion with the raw version.
- [ ] **4.1 (M)** **Multilingual dictation.** Add language auto-detect and multilingual model support, including mid-sentence language changes if practical.
- [ ] **4.2 (M)** **Snippets with placeholders.** Support expansions like “my intro [name]” with tab-through blanks.
- [ ] **4.4 (M)** **Rebuild command mode with its own state machine.** Salvage the useful edit-command pieces from history, but do not reuse dictation’s hotkey/latch state machine.
- [ ] **4.5 (M)** **Voice editing pack.** Add commands like delete last word/sentence, undo that, spoken punctuation, no-polish escape, and literal mode for code/URLs/identifiers.
- [ ] **5.5 (S)** **Undo Last Insertion.** Menu/home action that removes the most recent insertion using the same select-and-replace machinery; pairs well with 3.7.

## Distribution and scale-later work

Do these when scale or code-privacy pressure justifies them.

- [ ] **9.6 (S)** **Homebrew cask.** Add the cask to the existing tap repo and wire the release workflow to bump version + sha256 after each release. Keep using a self-tap until the app has enough notability for the main cask repo.
- [ ] **9.7 (M)** **Two-repo split if code privacy matters.** Private code repo plus public releases repo for DMGs, appcast, and website. Sequence carefully: ship a release pointing installed apps at the new public feed first, wait for adoption, then make code private.
- [ ] **9.10 (M)** **Opt-in crash reporting.** Opt-in only, with the no-telemetry promise preserved. Prefer compatibility tooling and diagnostic reports first.
- [ ] **9.11 (L)** **Localization.** Localize UI strings first; dictation language support is a separate model/runtime concern.
- [ ] **9.12 (S)** **Own domain for downloads + feed.** Move download page and appcast to a controlled domain. Requires the same careful feed migration as 9.7.

## Explicit non-goals

- **NG-1:** Cloud transcription or cloud LLMs in the dictation path.
- **NG-2:** Accounts, sync, telemetry, or usage analytics that leave the device.
- **NG-3:** Screenshot/URL-based context awareness; the app may use frontmost bundle ID only.
- **NG-4:** iOS, Android, or Windows apps for the foreseeable future.
