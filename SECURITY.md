# Security policy

George's Words runs entirely on-device: no accounts, no telemetry, and
no audio or text ever leaves the Mac. It does, however, download and run
code and models (a pinned, SHA-256-verified Ollama build; speech models
from Hugging Face), uses the Accessibility API to insert text, and
self-updates — so security reports are taken seriously.

## Reporting a vulnerability

Please report privately via GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on this repository
(https://github.com/zabugov/georges-words/security/advisories/new).

Please do not open public issues for security problems.

## Scope notes for researchers

- The update feed is served over HTTPS; updates must be signed with the
  same Apple Developer ID as the installed app (EdDSA feed signing is
  being added on top).
- The polish engine binds 127.0.0.1 on a random per-launch port and the
  app only trusts the server process it spawned itself.
- The engine download is version-pinned and SHA-256-verified before
  anything is executed.
