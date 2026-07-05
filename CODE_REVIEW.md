# George's Words — Full Code Review

Reviewed the complete repository: application code, tests, build/signing scripts, CI/release workflows, ADRs, README, and backlog.

At the time of review, all 38 tests passed. The build emitted one Swift 6 concurrency warning.

## Executive summary

The application has a strong local-first architecture and a well-designed core workflow. The most important work is reliability and security hardening around:

1. Ensuring processed text returns to the field where dictation began.
2. Verifying the downloaded Ollama executable before running it.
3. Making updater failures transactional.
4. Preventing clipboard data loss.
5. Bounding recording memory and live-preview work.
6. Formalizing Swift concurrency isolation.

These should be addressed before expanding the feature set.

## High-priority findings

### 1. Text can be inserted into the wrong application or field

**Severity: High**

The app records the frontmost application's bundle ID when recording ends, but `TextInserter` later asks macOS for whichever field is focused after transcription and polishing finish.

Relevant code:

- `AppDelegate.swift:457`
- `AppDelegate.swift:472`
- `TextInserter.swift:45`

If the user changes applications or fields during processing, the transcript may be inserted into an unrelated location. Command mode is riskier because it can replace an unrelated selection.

**Recommendation:** Capture a target object when recording starts or stops:

- Target PID and bundle ID.
- Focused `AXUIElement`.
- Original selection/range.
- A session identifier.

Before insertion, revalidate that the same process and field remain focused. If validation fails, leave the result on the clipboard and show a clear message instead of inserting automatically.

### 2. An unpinned, unverified executable is downloaded and run

**Severity: High**

The managed engine downloads the current `latest` Ollama archive, extracts it, marks it executable, and launches it without verifying its version, checksum, signing identity, or archive contents.

Relevant code:

- `ManagedOllama.swift:22`
- `ManagedOllama.swift:102`

A compromised upstream release or redirect would become code execution on the user's Mac.

**Recommendation:**

- Pin an explicit Ollama version.
- Store an expected SHA-256 digest in the repository.
- Verify its Apple signing requirement or Team ID where available.
- Extract into a temporary directory and validate paths before installation.
- Move the verified installation into place atomically.
- Make engine upgrades explicit and separately versioned.

### 3. Another local process can impersonate the polish engine

**Severity: High for the stated privacy guarantee**

The app assumes that anything answering `/api/version` on port `11499` is its managed Ollama process. A different process can bind that port before George's Words starts and receive every transcript and command-mode selection.

Relevant code:

- `ManagedOllama.swift:82`
- `LLMFormatter.swift:25`

**Recommendation:** Use a launch-owned random port or Unix socket, verify the child process identity, and add an authentication token through a small local proxy if Ollama itself cannot authenticate requests. Do not treat an existing server as the managed engine.

### 4. A failed update leaves source and installed app out of sync

**Severity: High**

The updater pulls `main` before building. If the build fails, the old application remains installed, but the checkout stays at the new commit. On the next update check, `HEAD` has not changed, so the updater reports "up to date" and does not retry the failed build.

Relevant code:

- `Updater.swift:81`
- `Updater.swift:88`

**Recommendation:** Record the commit used to build the installed application and compare against that value, not only `HEAD`. Better still, fetch and build in a temporary worktree, then install and advance the primary checkout only after success.

### 5. Clipboard restoration can overwrite new clipboard content

**Severity: High because it can destroy user data**

`TextInserter` restores the old clipboard after 0.5 seconds unconditionally. If the user copies something during that interval, George's Words replaces the newly copied content.

`SelectionReader` is worse: its copy fallback saves only the plain-text representation, discarding rich text, files, images, and multiple pasteboard items.

Relevant code:

- `TextInserter.swift:77`
- `TextInserter.swift:99`
- `SelectionReader.swift:171`

**Recommendation:**

- Preserve all pasteboard items and types in both paths.
- Record the pasteboard change count immediately after writing.
- Restore only if the change count still matches.
- Treat simulated paste as unverified rather than automatically returning `.inserted`.

### 6. Long recordings perform unbounded work and allocations

**Severity: High for reliability**

Audio samples grow without a maximum duration. The live-preview loop calls `snapshot()`, which copies the entire recording every 1.2 seconds. Although preview transcription stops after 30 seconds, the full copy happens before the length check, so a long hands-free recording keeps copying an increasingly large buffer.

Relevant code:

- `AudioRecorder.swift:38`
- `AppDelegate.swift:633`

**Recommendation:**

- Add a configurable maximum recording duration.
- Stop the preview task permanently after its preview limit.
- Check a cheap sample count before copying.
- Use chunked storage or a ring buffer for preview.
- Warn before automatically ending a very long recording.

### 7. Recorder startup failure can leave an installed audio tap

**Severity: High**

The tap is installed before `engine.start()`. If `start()` throws, the tap is not removed. A later call may attempt to install another tap on the same bus, which can crash.

Relevant code:

- `AudioRecorder.swift:74`
- `AudioRecorder.swift:78`

**Recommendation:** Roll back the tap and converter in a `catch` block and make `start()`/`stop()` explicitly idempotent.

## Medium-priority findings

### 8. Quick-tap mode can leave the microphone recording indefinitely

Any press shorter than 0.35 seconds enables hands-free recording. An accidental tap can therefore start an unlimited recording.

**Recommendation:** Make quick-tap mode optional, add a maximum duration, and provide a persistent visual/menu-bar indication. Consider requiring a double-tap instead.

### 9. LLM output validation does not support the "never worse" claim

Full polish accepts almost any nonempty result that is not excessively long. It can delete most of a transcript or substantially change its meaning and still pass. Light mode checks word-set novelty but not missing content, repetition, or word multiplicity.

Relevant code:

- `LLMFormatter.swift:167`

**Recommendation:**

- Retain both raw and polished text until insertion succeeds.
- Add minimum content-retention and repetition checks.
- Add a one-click "replace with raw transcript" or "undo polish."
- Build a regression corpus from real dictations.
- Soften README language claiming polish is "never worse."

### 10. Swift concurrency ownership is unclear

The test build reports a warning at `AppDelegate.swift:553` that becomes an error in Swift 6 mode.

More broadly:

- `AppDelegate`, shared observable stores, settings, and AppKit state should be main-actor isolated.
- `LLMFormatter` has mutable state accessed from asynchronous tasks but is neither an actor nor `@MainActor`.
- `Transcriber.modelName` is `nonisolated` but reaches into shared mutable settings.
- Multiple concurrent model-load tasks can serialize through the actor while still producing confusing state transitions.

**Recommendation:** Mark UI/state owners `@MainActor`, make the formatter an actor, and pass immutable configuration snapshots into background work rather than reading shared settings from worker tasks.

### 11. The updater timeout is not guaranteed to stop a hung update

The timeout only terminates the immediate process. Descendant processes can retain the output pipe, leaving `readDataToEndOfFile()` blocked. The `timedOut` variable is also shared across queues without synchronization.

**Recommendation:** Run each update step in its own process group, terminate the group, close pipes, and coordinate completion through one serial owner.

### 12. Automatic signing setup modifies the user's trust store

`build.sh` automatically runs `setup-signing.sh` when the identity is absent. That script creates and trusts a self-signed code-signing root certificate.

Relevant code:

- `build.sh:48`
- `setup-signing.sh:39`

This should not happen implicitly from a normal build command.

**Recommendation:** Keep setup explicit and opt-in. Default to ad-hoc signing unless an environment variable or command-line option expressly requests certificate creation.

### 13. Correction learning does not identify the original field

The delayed correction check validates only the frontmost bundle ID. It may read a different field in the same app and create incorrect suggestions.

**Recommendation:** Retain and revalidate the exact AX element and its original value/range. Add structured diagnostic reasons for every rejection, matching backlog item 2.5.

### 14. Persistence errors are silently ignored

History, corrections, settings, and factory-reset deletion use `try?`. The UI can claim data was stored or erased when the operation failed.

**Recommendation:** Surface local persistence health, use structured logging, and show actionable failures for destructive operations.

### 15. Factory reset is not actually complete

Factory reset removes `Application Support/GeorgesWords` and defaults, but:

- Speech-model caches managed by WhisperKit/FluidAudio may live elsewhere.
- Launch-at-login registration is not removed.
- The managed process is terminated but not awaited before deletion.
- It claims approximately 1.6 GB will be redownloaded even though speech caches may survive.

Relevant code:

- `MainWindowView.swift:483`

**Recommendation:** Enumerate all cache locations, unregister login launch, await engine termination, report deletion failures, and rename the operation if a truly complete reset is not possible.

### 16. Modifier hotkeys can become stuck

Modifier state is determined from the shared modifier flag. If both left and right Option are down and the configured side is released first, the Option flag remains set, so release may not be detected.

Global-monitor event loss during secure input, sleep, or app lifecycle changes can also leave `keyIsDown` set.

**Recommendation:** Reset state on wake, resign-active, secure-input changes, and device changes. Test left/right modifier combinations explicitly.

### 17. Dependency ranges are broader than the comments imply

FluidAudio is narrowly constrained, but WhisperKit uses `.upToNextMajor(from: "0.9.0")`, currently resolving to 0.18.0. For a pre-1.0 dependency, minor versions may contain breaking changes.

**Recommendation:** Pin WhisperKit exactly or constrain it to a tested minor range, then update deliberately.

### 18. Documentation and current behavior have drifted

Examples:

- Code defaults to `qwen2.5:3b`, while the backlog says the settled configuration is `qwen2.5:1.5b`.
- Onboarding describes an approximately 1 GB polish download, which matches 1.5B better than 3B.
- ADR 0003 describes user-installed Ollama on port 11434; the application now downloads and runs a private managed engine on 11499.
- An AppDelegate comment says user-installed Ollama is used when present, contradicting `ManagedOllama`'s stated design.

**Recommendation:** Add a new ADR for the managed engine and define model/version defaults in one source of truth.

## Architecture and maintainability

### Split the application coordinator

`AppDelegate.swift` is 861 lines and owns recording state, model loading, command mode, insertion, correction learning, updater UI, menus, windows, and onboarding.

A practical decomposition:

- `DictationCoordinator`
- `RecordingSession`
- `ModelController`
- `InsertionCoordinator`
- `CommandCoordinator`
- `CorrectionLearningCoordinator`
- `Window/MenuCoordinator`

Each recording should be represented by an immutable session containing its ID, mode, target, settings snapshot, start time, and active tasks. Stale task results should be discarded by session ID.

### Introduce interfaces around system dependencies

Define protocols for:

- Accessibility field access.
- Pasteboard operations.
- Audio capture.
- Process execution.
- HTTP transport.
- Clock/sleep.
- File persistence.

This would make the most dangerous behavior testable without controlling another real application.

### Use structured private logging

Use `Logger`/OSLog categories for audio, model, insertion, updater, and correction learning. Never include transcript contents; mark any sensitive values private. This would directly improve backlog item 2.5.

## Testing review

Current result: **38 tests passed**.

Coverage is good for deterministic transformations but weak around system integration and lifecycle behavior. Missing high-value tests include:

- Focus changes before insertion.
- Command selection changes before completion.
- Clipboard changes during delayed restoration.
- Rich/multi-item clipboard preservation.
- Audio engine startup failure cleanup.
- Long recordings and preview memory use.
- Concurrent model reloads.
- Updater build failure followed by retry.
- Port already occupied by a non-Ollama process.
- Full/light LLM output rejection.
- Factory-reset completeness.
- Modifier combinations and lost release events.
- History/correction write failures.

CI should also:

- Build both Parakeet and `GW_PARAKEET=0` configurations.
- Run tests in the release workflow before packaging.
- Add strict-concurrency checking.
- Add Swift formatting/linting.
- Pin GitHub Actions by commit SHA for stronger supply-chain protection.

## Features not currently listed in `FUTURE_IMPROVEMENTS.md`

### Privacy controls

- Disable transcript history entirely.
- Configurable retention: session-only, 24 hours, 7 days, or 200 entries.
- Per-app exclusion list for banking, password managers, medical apps, and private browsers.
- "Private dictation" hotkey that never stores history or correction-learning data.
- Optional correction-learning disable switch.

### Safer insertion and recovery

- Undo Last Insertion from the menu bar.
- Replace the polished result with the raw transcript.
- Show raw-versus-polished differences for the last dictation.
- Queue completed text when the original field loses focus instead of inserting elsewhere.
- Per-app insertion strategy settings.

### Voice editing controls

- "Delete last word/sentence."
- "Undo that."
- "Literal mode" for code, URLs, identifiers, and punctuation.
- Spoken punctuation commands such as "open parenthesis," "dash," and "semicolon."
- A temporary "no polish" spoken command.

### Audio controls

- Microphone/input-device picker.
- Input level and noise-floor calibration.
- Automatic warning for muted, disconnected, or extremely quiet microphones.
- Configurable maximum hands-free recording duration.
- Pause/resume during long dictation.

### Local data portability

- Export/import settings, dictionary, snippets, and app instructions.
- Encrypted local backup.
- Export history to Markdown or plain text.
- Dictionary profiles for different projects or clients.

### Workflow improvements

- Allow recording the next dictation while the previous one is polishing.
- Local keyboard shortcut for pausing/resuming George's Words globally.
- Shortcuts/URL-scheme integration for enabling modes or starting commands.
- Optional menu-bar-only mode with the Dock icon hidden.

### Diagnostics

- Privacy-safe diagnostic bundle containing versions, permissions, model state, and recent error categories—but never audio or transcript text.
- Built-in insertion compatibility test for the currently focused app.
- Model integrity/version display.
- Storage-usage screen for downloaded engines, models, history, and caches.

## Recommended implementation order

1. Bind every session to its original target field.
2. Pin and verify the managed engine download.
3. Make updater builds transactional.
4. Fix clipboard restoration races.
5. Bound recording duration and preview memory.
6. Formalize actor isolation and enable strict concurrency in CI.
7. Add integration tests for insertion, clipboard, updater, and engine ownership.
8. Correct factory reset and documentation drift.
9. Add privacy controls before expanding history or learning behavior.
10. Proceed with new user-facing features.

Overall, the core product direction is sound and the deterministic text-processing code is clean and well tested. The next engineering milestone should be a hardening pass focused on target identity, executable trust, transactional updates, and lifecycle bounds.
