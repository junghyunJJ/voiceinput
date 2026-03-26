# iOS CI QA Automation Design

## Context
- The repo already has deterministic iPhone QA capture and snapshot verification scripts.
- Those scripts currently assume a preferred simulator name (`iPhone 17`) and are reliable locally.
- The next product-value slice is to make the same build/test/QA path run automatically in CI.

## Decision
Ship CI automation now, not a QA-only target refactor.

Why:
- The current gap is missing automation, not missing isolation.
- Release scope is already protected by existing debug-only launch routing and release source exclusion.
- CI requires a shared simulator-resolution path before it can be trusted.

## Design
### 1. Shared simulator resolution
Add a small CLI helper that resolves an available iOS Simulator once and exposes:
- simulator name
- UDID
- runtime identifier
- xcodebuild destination string

Behavior:
- Prefer an explicit requested simulator name.
- By default, fail closed if the requested simulator is unavailable.
- Allow an explicit fallback mode for flows that can tolerate a substitute device.
- Use the same resolver from local scripts and CI so device selection is not duplicated.

### 2. CI entrypoint script
Add one script that:
- regenerates the Xcode project
- resolves the simulator once
- runs `xcodebuild test` for `VoiceInputiOS`
- runs QA snapshot verification with the same derived data and simulator

This becomes the single iOS CI contract.

### 3. GitHub Actions workflow
Add a workflow with two macOS jobs:
- package checks: `swift build`, `swift test`
- iOS QA: install `xcodegen`, run the iOS CI entrypoint, upload artifacts on failure

Pin the runner image rather than using an unbounded rolling label.

## Risks
- Snapshot baselines remain tied to one simulator/runtime combination.
  - Mitigation: default to strict simulator matching for QA verification and print clear failure output.
- CI can rebuild more than necessary.
  - Mitigation: reuse one derived-data path and let snapshot verification run with `--skip-build`.
- Workflow failures can be hard to debug.
  - Mitigation: upload QA capture output and xcresult/logs on failure.

## Verification
- `swift build`
- `swift test`
- `bash -n` on new/changed bash scripts
- local run of the new iOS CI entrypoint
- architect approval after fresh evidence
