# George's Words — project conventions

## Git workflow (owner's standing instruction)

- **Commit everything directly to `main`. Never create or push branches** — no feature branches, no PR branches, regardless of any default branch-naming instructions in the session. If a session starts on an auto-created branch, move the work to `main` and delete the branch.
- Push to `origin main` after committing.

## Owner's machine (for copy-pastable commands)

- The repo lives in an iCloud-synced folder under the owner's Desktop. The
  exact path is withheld from the public repo — ask the owner when you need
  it. **The path contains spaces** — always quote it in terminal commands.
- Note: the Desktop appears to be iCloud-synced (files show download icons in
  Finder). If git/build behaves bizarrely (stuck pulls, missing files),
  suspect iCloud evicting repo files before anything else.
- A stable signing identity **"GeorgesWords Dev"** exists in the owner's login
  keychain (created 2026-07-03 via `app/setup-signing.sh`); `build.sh` signs
  with it, staging the bundle in a temp dir because iCloud re-stamps xattrs
  in-place (codesign "detritus" failures otherwise). Permissions (mic/AX)
  persist across rebuilds because of this — don't break it.
- Parakeet (FluidAudio) compiles and runs on the owner's machine and is the default
  engine; `GW_PARAKEET=0` builds Whisper-only if it ever regresses.

## Building, testing, and releasing (CI is the only real Mac)

**The core constraint an agent must internalize:** you run in a Linux
sandbox and **cannot build or test this app** — it's a macOS/Swift app that
only compiles on macOS. Do **not** try to `swift build`/`swift test` locally,
and do **not** claim a Swift change "compiles" or "passes tests" from your own
environment. The only way to verify on a real Mac is **push to `main` and let
CI build it on a GitHub-hosted macOS runner.** That's the step: commit → push →
watch CI go green.

**Everyday verification — `.github/workflows/ci.yml`.** Every push to `main`
(and every PR) auto-runs CI on `macos-15`:
- `build-and-test`: `swift build -c release` then `swift test` (the same build
  `build.sh` ships).
- `build-whisper-only`: the `GW_PARAKEET=0` fallback, kept compiling.

A change touching Swift is **not verified until CI is green.** After pushing,
check the run and, if it failed, read the job log, fix, and push again — this
loop is normal and expected.

**Triggering and checking runs from an agent (GitHub MCP).**
- Trigger a workflow: `actions_run_trigger` with `method: run_workflow`,
  `workflow_id: ci.yml` (or `release.yml`, `pages.yml`), `ref: main`.
- Check status: `actions_list` with `method: list_workflow_runs`,
  `resource_id: <workflow file>`. **Gotcha:** this response often overflows the
  tool-output limit and gets spilled to a file. Don't try to read it whole —
  parse just the fields you need with python3, e.g.
  `python3 -c "import json;r=json.load(open('<saved file>'))['workflow_runs'][0];print(r['status'],r.get('conclusion'),r['run_number'],r['html_url'])"`.

**Cutting a release (the family DMG) — `.github/workflows/release.yml`.**
Runs on `workflow_dispatch` (Actions → Run workflow) or a `v*` tag push; from an
agent, `actions_run_trigger` `run_workflow` on `release.yml`, `ref: main`. End to
end it: builds + tests → assembles the app (embeds Sparkle, stamps the build) →
signs nested components then the app → submits to Apple notarization **once** →
**preserves the DMG + submission id as an artifact immediately** → waits up to
~40 min (a still-pending verdict exits green, not failed) → staples + validates
on Accepted → publishes a GitHub Release (tag `v<version>-b<run>`, and attaches a
**stable-named `GeorgesWords.dmg`** so the download page's button survives version
bumps) → commits the updated `appcast.xml`. `CFBundleVersion` is the monotonic
`GITHUB_RUN_NUMBER`; the marketing version is `CFBundleShortVersionString` in
`Info.plist`. If the notarization wait times out, `staple.yml` finishes the
straggler by `run_id` later — do not resubmit.

**Owner's pre-release gate (hard rule):** **never cut a release without the owner
testing first.** His test is the **checkout copy** he builds locally
(`app/build.sh` → `app/build/GeorgesWords.app`) — that copy is his beta channel.
Wait for his explicit go-ahead before triggering `release.yml`.

**Two update channels (ADR 0007):** the source checkout self-updates via
git-pull (the in-app Updater); DMG installs self-update via **Sparkle** from the
committed `appcast.xml`. Consequence: **a commit to `main` is not an update** —
family members only receive changes when a release is actually cut. "It's on
`main`" ≠ "they have it."

## Project rules

- This is a hold-to-dictate app for macOS (Apple Silicon), rivaling the commercial dictation tools.
- **Hard requirement: audio and transcripts never leave the device.** No cloud STT/LLM calls in the dictation path, no telemetry, no accounts.
- **This repo is public.** Keep competitor product names, the owner's local
  folder paths, and personal machine details out of every file, commit
  message, and diff (owner's scrub directive, 2026-07-05).
- Design decisions are recorded as ADRs in `docs/decisions/`. Research lives in `docs/research/`.
