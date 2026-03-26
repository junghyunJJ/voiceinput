# iOS QA Environment Baseline Design

## Goal

Make iOS QA snapshot failures fail early and explicitly when the active Xcode, simulator, or iOS runtime drifts from the checked-in baseline contract.

## Problem

The snapshot baseline already existed, but the environment it depended on was implicit:

- the workflow pinned `macos-15`
- scripts preferred `iPhone 17`
- the simulator resolver picked the newest runtime for that device

That meant toolchain drift showed up late as a snapshot mismatch instead of an explicit environment mismatch.

## Decision

Add a checked-in shell-style contract at `docs/qa-baselines/ios/environment.env` with:

- Xcode version
- Xcode build
- simulator name
- exact runtime identifier
- fallback policy

Then:

- add exact runtime support to `resolve-ios-simulator.sh`
- add `describe-ios-qa-environment.sh` for reproducible current-environment capture
- add `preflight-ios-qa-environment.sh` for fail-closed validation
- run preflight in `ci-verify-ios.sh`
- run preflight in `verify-ios-qa-gallery.sh` before capture when the baseline contract is present
- update `--record` to rewrite both PNG baselines and the environment contract

## Non-Goals

- pinning GitHub Actions to an exact Xcode selection action in this slice
- introducing a QA-only Xcode target
- relaxing snapshot strictness

## Acceptance

- baseline verification fails before capture/test when Xcode/runtime/simulator drift
- the failure output prints expected vs observed environment values
- the CI artifact directory contains preflight logs
- intentional baseline refresh updates both the PNG files and `environment.env`
