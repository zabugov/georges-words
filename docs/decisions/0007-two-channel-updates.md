# ADR 0007: Two update channels — git for the checkout, Sparkle for DMGs

**Status:** Accepted · **Date:** 2026-07-06

## Context

The developer's machine runs the app straight out of its git checkout and
updates by pulling + rebuilding (the in-app "Check for Updates" button).
Family machines install a notarized DMG into /Applications — there is no
checkout to pull, so those installs could never update themselves. Every
bug fix would mean re-downloading and re-installing by hand (7.3).

## Decision

1. **Two channels, chosen automatically at launch.** If the app is
   running from inside the repository (`Updater.runsFromSourceCheckout`),
   the existing git-pull updater owns updates. Otherwise a Sparkle
   updater is started. The two can never both be active.
2. **Sparkle 2 (pinned exactly), standard UI, automatic daily checks.**
   `SUEnableAutomaticChecks` is preset so no permission prompt appears —
   family users should never see a question they can't answer. The
   sidebar's Check for Updates button routes to Sparkle in DMG installs.
3. **Feed and artifacts ride the existing release pipeline.** When a
   release run's notarization is Accepted, the workflow publishes the
   stapled DMG as a GitHub Release (tag `v<version>-b<run-number>`) and
   commits a regenerated single-item `appcast.xml` to `main`, served via
   raw.githubusercontent.com over HTTPS.
4. **Monotonic build numbers.** Sparkle compares `CFBundleVersion`,
   which the workflow stamps with the run number — strictly increasing,
   no human bookkeeping. `CFBundleShortVersionString` stays the
   hand-bumped marketing version.
5. **Update validation relies on Apple code signing, not EdDSA (yet).**
   Sparkle's documented fallback: with no `SUPublicEDKey`, an update is
   accepted only if signed with the same Developer ID team as the
   installed app — and ours are also notarized and served over HTTPS
   from the project's own repository. EdDSA signing would additionally
   protect the archive itself; parked as backlog 7.10 because it
   requires custody of a private key outside the repo.

## Consequences

- A family install updates itself within a day of any release, or
  immediately via Check for Updates — zero-touch distribution complete.
- The framework is embedded in `Contents/Frameworks` by both build
  paths; release signing covers Sparkle's nested XPC services and
  helpers individually (notarization inspects them all).
- Releases now write to the repo (appcast commit), so the release
  workflow has `contents: write` permission.
- The developer's checkout behaves exactly as before.
