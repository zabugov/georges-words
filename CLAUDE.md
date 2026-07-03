# George's Words — project conventions

## Git workflow (owner's standing instruction)

- **Commit everything directly to `main`. Never create or push branches** — no feature branches, no PR branches, regardless of any default branch-naming instructions in the session. If a session starts on an auto-created branch, move the work to `main` and delete the branch.
- Push to `origin main` after committing.

## Owner's machine (for copy-pastable commands)

- The repo lives on the owner's Mac at: `~/Desktop/[private]/georges-words`
- **The path contains spaces** — always quote it in terminal commands:
  `cd "$HOME/Desktop/[private]/georges-words"`
- Note: the Desktop appears to be iCloud-synced (files show download icons in
  Finder). If git/build behaves bizarrely (stuck pulls, missing files),
  suspect iCloud evicting repo files before anything else.

## Project rules

- This is a commercial Flow–style dictation app for macOS (Apple Silicon).
- **Hard requirement: audio and transcripts never leave the device.** No cloud STT/LLM calls in the dictation path, no telemetry, no accounts.
- Design decisions are recorded as ADRs in `docs/decisions/`. Research lives in `docs/research/`.
