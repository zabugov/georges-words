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

## Project rules

- This is a hold-to-dictate app for macOS (Apple Silicon), rivaling the commercial dictation tools.
- **Hard requirement: audio and transcripts never leave the device.** No cloud STT/LLM calls in the dictation path, no telemetry, no accounts.
- **This repo is public.** Keep competitor product names, the owner's local
  folder paths, and personal machine details out of every file, commit
  message, and diff (owner's scrub directive, 2026-07-05).
- Design decisions are recorded as ADRs in `docs/decisions/`. Research lives in `docs/research/`.
