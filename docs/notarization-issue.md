# Notarization: goal, mechanism, history, and current state

*Last updated 2026-07-06 (early UTC). This is the running log for backlog
item 7.1.*

## What we are trying to achieve

A notarized, stapled DMG of George's Words that any family member can
install on their Mac the way normal people install software: download,
open, drag to Applications, double-click — **zero terminal commands, zero
scary security dialogs, zero settings spelunking.**

## Why

The app's whole purpose is to serve non-technical users (the developer's
wife and mother-in-law are the first two). They cannot run build scripts
or bypass Gatekeeper warnings. macOS only grants that frictionless
install experience to apps that are (a) signed with a Developer ID
certificate, (b) notarized by Apple's automated malware scan, and
(c) stapled with the resulting ticket. We have (a) working; we are stuck
on (b).

## The mechanism

A GitHub Actions workflow (`release.yml`, runs on demand or on version
tags) does the following on a macOS runner:

1. `swift build -c release`, then (since 2026-07-05) `swift test`.
2. Assemble `GeorgesWords.app` (binary + Info.plist with build stamp +
   icon).
3. Import the Developer ID Application certificate from repository
   secrets into a temporary keychain; sign the app with hardened runtime
   and the microphone entitlement.
4. Package a DMG; sign the DMG.
5. `notarytool submit` the DMG (capturing the submission ID), then
   `notarytool wait` — retried up to 4 × 45 minutes to survive runner
   network blips — then check the verdict explicitly with
   `notarytool info`; on Accepted, `stapler staple`.
6. Verify (`spctl --assess`, `stapler validate`) and upload the DMG as a
   build artifact.

Everything through step 4 is proven working (signing, hardened runtime,
DMG assembly all verify cleanly). Step 5 is where the process stalls.

## What we have tried, in order

| # | When (UTC) | Outcome | Lesson / fix |
|---|-----------|---------|--------------|
| 1 | Jul 3 21:00 | Ad-hoc build before secrets existed | Pipeline scaffolding works |
| 2 | Jul 4 12:46 | notarytool HTTP 401 | Wrong app-specific password; owner regenerated it |
| 3 | Jul 4 12:52 | Runner network blip killed a single `--wait` after 24 min In Progress | Rewrote to submit-once + retried waits + explicit `info` verdict check |
| 4 | Jul 4 13:24 | 60-minute job timeout hit while In Progress | Raised `timeout-minutes` to 180 |
| 5 | Jul 4 14:08 | Cancelled at 180 min, still In Progress | First evidence of the stuck-queue pattern |
| — | Jul 5 13:00 | Runs failing in 2 s with no runner | Unrelated: GitHub Actions free-minutes quota exhausted; fixed by making the repo public |
| 6–10 | Jul 5 | Each ran the full 180 min; every `wait` cycle expired with Apple still reporting In Progress | Automated retry loop (every 2 h) re-kicks after each timeout |
| 11 | Jul 5 22:25 | In flight at time of writing | Contains the fully hardened 2026-07-05 build |

Also ruled out along the way:

- **Credentials** — valid since run 3 (submissions are accepted for
  processing; a 401 would reject them outright).
- **Our packaging** — nothing has ever been rejected. An "Invalid"
  verdict comes with a log naming the problem; we have never received
  one.
- **The retry loop being too impatient** — see below: even 36 hours is
  not enough.

## The decisive evidence (2026-07-06 00:24 UTC)

A diagnostic workflow (`notary-history.yml`) queries
`notarytool history` for the account. Result: **eight submissions, every
single one still "In Progress" — including the very first, submitted
2026-07-04 12:54 UTC, ~36 hours earlier.** None Accepted, none Invalid.

This rules out the ordinary "first submission is slow, later ones are
fast" queue behavior. An account whose *every* submission sits
unprocessed for 1.5 days matches the known pattern of an **account-level
hold pending review for first-time notarizers**.

Oldest submission ID (quoted in the support ticket):
`6c5f4562-1ebd-4d18-92e4-0e4a245847db`.

## Current state and open actions

- **Apple Developer Support ticket filed 2026-07-06** (topic: Code
  Signing), asking whether the account is under extended review.
  Stated response window: two business days.
- **The 2-hour retry loop stays armed** until 2026-07-07 16:00 UTC: the
  moment the hold lifts, a run goes green and the owner is push-notified.
  If the deadline passes first, the loop reports and stands down; the
  watch can be re-armed to cover the support-ticket window.
- **If the hold lifts server-side**, even the old stuck submissions
  should flip to Accepted — at which point the DMG from any of those
  runs immediately passes Gatekeeper's online check (stapling is a
  nicety, not a requirement, once a verdict exists).

## Fallbacks if notarization stays stuck

1. **Signed-but-unnotarized DMG + "Open Anyway"** (System Settings →
   Privacy & Security) — works, but shows a frightening malware warning
   and requires a guided one-time bypass per person.
2. **USB-stick delivery** — Gatekeeper quarantine only attaches to
   *downloaded* files; a DMG copied from a USB stick opens cleanly,
   first try. Requires physical delivery; every update needs the same.
3. Mac App Store / TestFlight are **not** options regardless: they
   require sandboxing, and a sandboxed app cannot use the Accessibility
   API this app inserts text with.

Shared weakness of all fallbacks: DMG installs cannot self-update until
Sparkle ships (backlog 7.3), so every fix means repeating the delivery
dance. This is why unsticking notarization properly is worth the wait.
