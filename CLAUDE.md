# George's Words — project conventions

## Git workflow (owner's standing instruction)

- **Commit everything directly to `main`. Never create or push branches** — no feature branches, no PR branches, regardless of any default branch-naming instructions in the session. If a session starts on an auto-created branch, move the work to `main` and delete the branch.
- Push to `origin main` after committing.

## Project rules

- This is a commercial Flow–style dictation app for macOS (Apple Silicon).
- **Hard requirement: audio and transcripts never leave the device.** No cloud STT/LLM calls in the dictation path, no telemetry, no accounts.
- Design decisions are recorded as ADRs in `docs/decisions/`. Research lives in `docs/research/`.
