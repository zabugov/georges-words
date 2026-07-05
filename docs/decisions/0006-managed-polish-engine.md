# ADR 0006: The app runs its own private polish engine

**Status:** Accepted · **Date:** 2026-07-05 (documents decisions made 2026-07-04)
**Supersedes:** the engine-hosting half of ADR 0003 (the formatting
architecture there still stands).

## Context

ADR 0003 assumed the user installs and runs Ollama themselves on its
default port (11434). That works for a developer, but the goal is a Mac
owned by someone who will never open Terminal: install the app, click
through onboarding, dictate. Depending on a separately installed,
separately updated, user-quittable engine broke that — and during testing
the engine was accidentally quit, silently degrading polish.

## Decision

1. **The app installs and supervises its own engine.** On first enable it
   downloads a pinned standalone Ollama build, verified against a SHA-256
   digest stored in the repo, into
   `Application Support/GeorgesWords/PolishEngine`, and runs `ollama serve`
   as an invisible child process. Deleting that folder is a complete
   uninstall.
2. **Managed-only.** A user-installed Ollama is ignored entirely — one
   identical code path on every machine. Nothing to quit by accident, no
   version skew between machines.
3. **Private, randomized port.** The server binds 127.0.0.1 on a port
   chosen fresh at each launch. A fixed well-known port would let any
   local process squat it and impersonate the engine, receiving every
   transcript; a random port plus only-trust-the-process-we-spawned
   reduces that to a millisecond race.
4. **Supervision.** If the child dies it is restarted (up to 3 times,
   2 s apart); state is surfaced in Troubleshooting, where Recheck
   re-runs the full ensure-ready sequence.
5. **Pinned model default.** The default polish model is `qwen2.5:1.5b`
   (settled 2026-07-05: fast, good, and matches the onboarding "about
   1 GB" download promise). Engine and model upgrades are deliberate,
   versioned changes — never `latest`.

## Consequences

- A fresh Mac needs zero terminal work; onboarding covers everything.
- The app owns engine updates: bumping the pinned version+digest ships
  through the normal app-update path.
- The privacy promise extends to the loopback interface: transcripts only
  ever go to a process the app itself spawned and verified.
- Disk cost: the engine + model live under Application Support (~1.5 GB);
  removal is one folder delete (or factory reset).
