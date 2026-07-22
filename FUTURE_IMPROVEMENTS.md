# Future Improvements

This is the open backlog only. Finished work and historical triage notes belong in commits, ADRs, release notes, or the relevant docs — not in this file.

Effort guide: **S** = hours, **M** = days, **L** = a milestone. Item numbers are stable references; when an item ships, retire it instead of renumbering everything.

## Context and guardrails

- **Current baseline:** speed and quality are good enough for daily use. The settled default is Parakeet v3 for transcription plus `qwen2.5:1.5b` light polish through the app-managed local engine.
- **Privacy is the product:** audio and transcripts stay on-device. No cloud transcription, cloud polish, telemetry, accounts, sync, or usage analytics in the dictation path.
- **Commercial posture:** sharing free builds is unblocked once the download button is verified. Charging money has extra gates: signed updates, legal/support pages, private support intake, and privacy controls.
- **Business discipline:** do not overbuild business infrastructure until demand proves it. Prefer hosted checkout/license issuance; avoid accounts, dashboards, subscriptions, teams, or always-online DRM for v1.
- **Licensing posture:** the dependency stack is commercially usable, but model/library licenses and attributions must stay tracked in release artifacts. Do not add an open-source license for the app’s own code while a paid future is on the table.

## Owner action queue (added 2026-07-07 — clear these, then delete the section)

Everything below needs the owner's hands or judgment; agents have taken these as far as they can.

1. **Finish the two-repo split configuration (ADR 0009 steps 2 + Pages).** On github.com: create the fine-grained PAT (Developer settings → Fine-grained tokens; scope: only `georges-words-releases`; permission: Contents Read & write; 1-year expiry — set a renewal reminder), add it to the **code** repo as Actions secret `RELEASES_REPO_TOKEN`, add Actions variable `RELEASES_REPO` = `zabugov/georges-words-releases`, and on the **releases** repo enable Settings → Pages → Source: GitHub Actions. The release pipeline is blocked (by design) until this is done.
2. **Test the checkout build** (`app/build.sh`) by walking **[docs/qa-checklist.md](docs/qa-checklist.md)** top to bottom (~20 min). It's a ticked, step-by-step version of the whole 2026-07-07 batch — correction learning (2.5), speculative polish (1.2), command mode (4.4), style matching (3.3), the Privacy section (8.1/8.2/8.3), microphone picker + silence warning (6.5), the Troubleshooting field tester (6.6), settings export/import (7.8), the menu-bar Use Unpolished Version / Undo Last Insertion (3.7/5.5), and the experimental "Boost my dictionary words" toggle (2.2). Each passing test retires its backlog item.
3. **Give the go-ahead for the migration release** (ADR 0009 step 5) once 1 and 2 look good. After it ships: verify one Mac updates from an older build via Check for Updates (that's also the 7.10 sign-off), confirm the DMG's Applications icon renders (Finder fix rides this release), get every family Mac onto it, and only then flip the code repo private (step 8).

## Immediate pre-commercial work

These are the highest-leverage items before sharing broadly or charging.

- [ ] **9.2 (S)** **Verify the public download flow.** After the next release, do one fresh install through the site’s exact Download button and confirm it fetches the stable `GeorgesWords.dmg` asset. Until this passes, send users to GitHub Releases instead of the website button.
- [ ] **7.10 (S)** **Verify EdDSA-signed Sparkle updates.** The signing pieces are wired; the remaining work is proof: cut a release, confirm `sparkle:edSignature` appears in `appcast.xml`, and update from an older build successfully. Treat this as required before taking payment.
- [ ] **9.13 (M)** **Customer-facing legal pages.** Add Privacy, Terms/EULA, refund policy, warranty limits, update expectations, sold-direct disclosure, and support contact links on the website and checkout flow.
- [ ] **9.14 (S)** **Private support intake.** Add a support email or private form. GitHub Issues/Discussions are fine for public bugs, but diagnostic reports should not be pushed into public threads by default.
- [ ] **9.15 (M)** **Closed-beta support rehearsal.** Test with about 10 nontechnical Macs: site download, install, permissions, first model downloads, dictation across common app types, Sparkle update, diagnostic export, factory reset/uninstall, and one unsupported Mac. Use the results to update launch copy, FAQ, and pricing assumptions.
- [ ] **8.1 (S)** **Verify per-app privacy exclusions on-device.** Landed 2026-07-07: Settings → Privacy → Add Private App. Dictate into a marked app and confirm no history entry appears and debug.log shows no correction check for it.
- [ ] **8.2 (S)** **Verify history retention controls on-device.** Landed 2026-07-07: Settings → Privacy → Keep dictation history (nothing / until quit / 7 days / last 200). Check that "Keep nothing" erases immediately and session-only leaves no history.json behind.
- [ ] **8.3 (S)** **Verify the correction-learning off switch on-device.** Landed 2026-07-07: Settings → Privacy → Learn corrections from your edits. Off must mean zero field re-reads (debug.log shows no "Correction check" lines).
- [ ] **9.8 (M)** **Payments + license keys.** Direct sales only. Use hosted checkout and license issuance from a merchant-of-record provider. Recommended v1: one-time purchase, stated update window, no accounts, no always-online DRM. Activation should store a local entitlement and only touch the network on explicit activate/deactivate/manual refresh; normal dictation must never depend on the network.

## Reliability and support reducers

These reduce support load and make failures explainable.

- [ ] **2.5 (S)** **Verify improved correction detection on-device.** The fixes landed 2026-07-07 (widened re-read schedule, exact-element tracking, phonetic second chance, strict mode for short dictations, a pill notice on capture, debug logging — see ADR 0005 amendment). Note: the planned sidebar badge was reverted same-day — `.badge()` on the sidebar rows froze sidebar selection; re-add a cue only via a route that doesn't touch row hit-testing. Remaining work: dictate, fix a word within a minute, confirm the pill notice and a waiting Dictionary suggestion; retire when it behaves.
- [ ] **6.2 (M)** **Per-app insertion quirks.** Audit direct insertion and paste fallback across Electron apps, browsers, terminals, Java apps, and secure/private fields; keep a compatibility list.
- [ ] **6.5 (S)** **Verify the microphone picker + silent-mic warning on-device.** Landed 2026-07-07: Settings → Microphone (remembered by device UID, hard fallback to system default), and a "only silence was heard" alert when a ≥1 s recording trims to nothing.
- [ ] **6.6 (S)** **Verify the insertion compatibility tester on-device.** Landed 2026-07-07: Troubleshooting → "Test a Text Field…" (click into the target app within 3 s; read-only probe reports direct insertion vs paste fallback).
- [ ] **6.7 (S)** **Verify the completed factory reset on-device.** Landed 2026-07-07: now also removes the FluidAudio/WhisperKit model caches, unregisters launch-at-login, waits (≤5 s) for the polish engine to exit before deleting its files, and shows an alert listing anything it couldn't remove.
- [ ] **7.8 (S)** **Verify settings export/import on-device.** Landed 2026-07-07: Settings → Backup. Export, change something, import, confirm it restores (history and learned suggestions intentionally excluded).
- [ ] **7.9 (M)** **Incremental internal hardening.** Adopt `@MainActor` on UI/state owners, enable stricter concurrency checks once clean, and extract pieces of `AppDelegate` opportunistically when touching them. No big-bang refactor.
- [ ] **9.9 (S)** **Release notes as support — remainder.** CHANGELOG.md landed 2026-07-07 and the release pipeline now lifts its Unreleased section into both the GitHub release notes and the Sparkle update notes (visible in the update prompt), rolling the heading automatically. Still open: a website known-issues section once there are real recurring issues to list.

## Product improvements

Useful, but not blockers for a first commercial test.

- [ ] **1.2 (S)** **Verify speculative polish on-device.** Landed 2026-07-07 (ADR 0008): pause-triggered background polish with an exact-match cache; the timing line reads "polish done during a pause" on a hit. Remaining work: dictate with a natural pause before key release and confirm the hit; watch CPU/battery feel during long dictations; retire when it behaves.
- [ ] **1.3 (M)** **True streaming polish — implement ADR 0012.** Design settled 2026-07-07 (incremental speculation: sentence commit-lag window over ADR 0008's loop, stability-checked commits, stitch-or-fallback final pass). Deliberately gated on 1.2's on-device verification; effort drops to M because the loop/cache/pause plumbing already shipped.
- [ ] **1.5 (M)** **Apple Foundation Models polish engine.** Explore macOS 26+ on-device models as a way to remove the managed Ollama dependency for newer Macs.
- [ ] **2.2 (S)** **Re-verify dictionary boosting on-device.** First on-device test (2026-07-22, short name terms) showed severe over-firing: dictionary words replaced unrelated words across whole sentences at similarity floor 0.52. Fixed same day: floor raised to 0.70 plus a hard cap (≤ ~1 replacement per 8 words, else the whole rescore is discarded — QA checklist §11 has the regression test). Re-verify with the same terms; if it still over-fires under the cap, the next lever is dropping short (<5-char) terms from the boost vocabulary. Later: learned corrections as aliases, and WhisperKit prompt tokens for the fallback (bug-check WhisperKit #372 first).
- [ ] **3.3 (S)** **Verify personal style matching on-device.** Landed 2026-07-07 (ADR 0011): paste a writing sample per app type under Settings → Your writing style; full polish imitates its voice. Remaining: paste real samples, dictate in a matching app with Full polish, judge the imitation; retire when it behaves.
- [ ] **3.5 (S)** **Grow the few-shot bank.** Keep a small local corpus of messy transcript → ideal output examples from real failures.
- [ ] **3.7 (S)** **Verify “Use Unpolished Version” on-device.** Landed 2026-07-07: when polish reworded the last dictation, the menu-bar action swaps the pre-polish text back in place (clipboard fallback otherwise).
- [ ] **4.1 (M)** **Multilingual dictation.** Add language auto-detect and multilingual model support, including mid-sentence language changes if practical.
- [ ] **4.2 (M)** **Snippets with placeholders.** Support expansions like “my intro [name]” with tab-through blanks.
- [ ] **4.4 (S)** **Verify command mode on-device.** Rebuilt 2026-07-07 as free-form LLM edit instructions with its own state machine (ADR 0010); on by default with Right Option (⌥), with a presets dropdown for other keys. Remaining: dictate, then hold Right ⌥ and say "make it more formal" / "remove the word X" / "translate to French"; confirm in-place replacement and the clipboard fallback; also check that spurious Right-⌥ taps aren't annoying in daily use (if they are, that's the signal to gate activation harder or reconsider the default). Retire when it behaves.
- [ ] **4.5 (M)** **Voice editing pack — remainder.** Free-form commands (4.4, ADR 0010) now cover deletions/rewording/restructuring. Still open: literal mode for code/URLs/identifiers and spoken punctuation *during* dictation, plus a no-polish escape word.
- [ ] **5.5 (S)** **Verify “Undo Last Insertion” on-device.** Landed 2026-07-07 as a menu-bar action on the replaceLastInsertion machinery (ADR 0010).

## Distribution and scale-later work

Do these when scale or code-privacy pressure justifies them.

- [ ] **9.6 (S)** **Homebrew cask.** Add the cask to the existing tap repo and wire the release workflow to bump version + sha256 after each release. Keep using a self-tap until the app has enough notability for the main cask repo.
- [ ] **9.7 (M)** **Two-repo split — execute the runbook.** Design + machinery landed 2026-07-07 (ADR 0009): the release workflow publishes to a public releases repo once `RELEASES_REPO`/`RELEASES_REPO_TOKEN` are configured, and updates both feeds during the transition. Remaining work is the ADR 0009 runbook: create the releases repo, seed it, flip `SUFeedURL`, cut the migration release (owner-gated, doubles as the 7.10 sign-off), wait for every install to migrate, then flip the code repo private.
- [ ] **9.10 (M)** **Opt-in crash reporting.** Opt-in only, with the no-telemetry promise preserved. Prefer compatibility tooling and diagnostic reports first.
- [ ] **9.11 (L)** **Localization.** Localize UI strings first; dictation language support is a separate model/runtime concern.
- [ ] **9.12 (S)** **Own domain for downloads + feed.** Move download page and appcast to a controlled domain. Requires the same careful feed migration as 9.7.

## Explicit non-goals

- **NG-1:** Cloud transcription or cloud LLMs in the dictation path.
- **NG-2:** Accounts, sync, telemetry, or usage analytics that leave the device.
- **NG-3:** Screenshot/URL-based context awareness; the app may use frontmost bundle ID only.
- **NG-4:** iOS, Android, or Windows apps for the foreseeable future.
