# Agent conventions

All instructions for coding agents working in this repo live in
[CLAUDE.md](CLAUDE.md) — the same conventions apply regardless of which
agent or tool you are. Read it before making changes.

Highlights that agents keep getting wrong:

- Commit directly to `main`; never create or push branches.
- This repo is public. Keep competitor product names, the owner's local
  folder paths, and personal machine details out of every file, commit
  message, and diff.
- Audio and transcripts never leave the device — no cloud calls in the
  dictation path, no telemetry.
