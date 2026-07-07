# ADR 0009: Two-repo split — private code, public releases

**Date:** 2026-07-07 · **Status:** accepted, migration in progress · **Backlog:** 9.7 (relates: 9.12, 7.10)

## Context

The code repo is public today and does four public jobs at once: source
hosting, the Sparkle update feed (`raw.githubusercontent.com/…/main/appcast.xml`),
DMG hosting (GitHub Releases), and the website (Pages). Making the code
private with everything in one repo would instantly break updates,
downloads, and the site for every installed copy.

The exit is a **second, public "releases" repo** that owns the
customer-facing artifacts — appcast, DMGs, website — so the code repo
can go private without breaking anyone. There is no telemetry (ADR
0001), so "did everyone migrate?" cannot be measured remotely; with the
current family-sized install base, adoption is confirmed by checking
each Mac.

## Decision

1. **A public releases repo** holds: `appcast.xml` (the new feed), the
   GitHub Releases with DMG assets (including the stable-named
   `GeorgesWords.dmg`), and `site/` served via GitHub Pages. No app
   source. Issues stay enabled there — it becomes the public
   bug-report door once the code repo is private.
2. **The release workflow stays in the code repo** (it needs the source
   to build) and *publishes across*: when the repo variable
   `RELEASES_REPO` (e.g. `zabugov/georges-words-releases`) and the
   secret `RELEASES_REPO_TOKEN` (fine-grained PAT, Contents read/write
   on the releases repo only) are configured, the release, DMG, and
   appcast land in the releases repo. **During the transition the old
   feed on code-repo `main` is updated too**, so not-yet-migrated
   installs keep seeing new releases. Unconfigured, the workflow
   behaves exactly as before — the machinery ships inert.
3. **One migration release ("R") repoints installed apps.** R is the
   first release built with `SUFeedURL` set to the releases-repo feed.
   Old installs learn about R from the *old* feed and update; from then
   on they read the *new* feed. The DMG enclosure URL in both feeds
   points at the releases repo.
4. **Only after every install runs R or later** does the code repo go
   private (owner flips it in Settings). The old feed URL then 404s —
   harmless, because nothing reads it anymore.
5. **EdDSA signing is a hard prerequisite** (backlog 7.10): R must
   install via a *signed, verified* Sparkle update from an older build
   before the private flip — a botched feed migration with unsigned
   updates would strand every install.

## Feed URL choice (ties to 9.12)

The new feed lives at
`https://raw.githubusercontent.com/<RELEASES_REPO>/main/appcast.xml`
unless the owner puts a custom domain on the releases repo's Pages
site, in which case the feed should live at the domain
(`https://<domain>/appcast.xml`, served from `site/`) — then any future
hosting move never requires another feed migration. Feed migrations are
the riskiest routine operation this app has; do as few as possible.

## Runbook (owner + agent steps, in order)

1. ☐ Create the public releases repo (empty, public, Issues on).
2. ☐ Owner: create a fine-grained PAT — github.com → Settings →
   Developer settings → Fine-grained tokens → scope: only the releases
   repo, permission: Contents Read & write. Add it to the **code**
   repo: Settings → Secrets and variables → Actions → New secret
   `RELEASES_REPO_TOKEN`. Add a variable `RELEASES_REPO` with the repo
   full name under the Variables tab.
3. ☐ Seed the releases repo: `site/` (with the download button pointed
   at the releases repo's `releases/latest/download/GeorgesWords.dmg`),
   the Pages deploy workflow, a copy of the current `appcast.xml`, and
   a README saying what the repo is. Enable Pages (Settings → Pages →
   Source: GitHub Actions).
4. ☐ Flip `SUFeedURL` in `app/Info.plist` to the new feed URL (one
   commit, code repo).
5. ☐ Owner tests the checkout build (`app/build.sh`) — the standing
   pre-release gate — then cuts release R (Actions → Release DMG →
   Run workflow).
6. ☐ Verify on one Mac running an older build: Check for Updates →
   R installs (this is also the 7.10 sign-off) → after updating,
   `defaults read` …/GeorgesWords.app/Contents/Info SUFeedURL shows the
   new feed.
7. ☐ Wait until **every** installed Mac runs R or later (ask the
   family; Sparkle checks daily). No rush — nothing breaks while both
   feeds are live.
8. ☐ Owner: flip the code repo private (Settings → General → Danger
   Zone). Update the site/README links that pointed at the code repo
   (the workflow's transition warning lists them).
9. ☐ Retire backlog 9.7; fold remaining website work into 9.13.

**Rollback:** any time before step 8, revert the `SUFeedURL` commit and
cut another release — both feeds are being updated throughout, so
installs on either feed see it. After step 8 there is nothing to roll
back; the old feed is simply unused.

## Consequences

- Sessions/agents keep full access to the private code repo through the
  GitHub app; the releases repo is public plumbing.
- The Homebrew cask (9.6) and own-domain move (9.12) should target the
  releases repo when they happen.
- README/site "Source on GitHub" links die at step 8 — the releases
  repo becomes the public face; support intake (9.14) should point
  there or at the support email.
- The appcast keeps only the latest item (existing behavior), so the
  new feed works for every installed version from day one.
