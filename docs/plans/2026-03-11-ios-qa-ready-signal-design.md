# iOS QA Ready Signal Design

> Superseded on 2026-03-11 by `2026-03-11-ios-qa-readiness-signal-design.md`.
> This draft captured an earlier `UserDefaults`-based approach and is kept only as historical context.

## Goal

Replace the fixed settle delay in `Scripts/capture-ios-qa-gallery.sh` with an explicit readiness signal so snapshot capture waits for the intended QA screen state.

## Scope

- Debug-only iPhone QA routes
- Simulator screenshot capture reliability
- No product behavior changes

## Design

1. The debug QA launch path accepts an optional `--qa-ready-value <token>` argument.
2. When a QA route is actually on-screen, the app writes that token into `UserDefaults.standard` under a fixed debug-only key.
3. `capture-ios-qa-gallery.sh` clears the key before each launch, launches the app with the expected token, then polls the simulator app defaults until the token matches.
4. Screenshot capture happens only after the expected token is observed.

## Why This Approach

- It is explicit: the app tells the script when the intended QA route is ready.
- It is narrow: only debug QA flows are touched.
- It avoids simulator-host filesystem assumptions.
- It removes the fixed `sleep 3` heuristic that previously caused launch-to-launch drift.

## Risks

- `onAppear`-level readiness still means “route is on-screen”, not “every async subview side effect is complete”.
- The script now depends on `simctl spawn defaults read`, so simulator connectivity remains a prerequisite.

## Acceptance Criteria

- No fixed post-launch sleep remains in `capture-ios-qa-gallery.sh`.
- QA launch args can carry a ready token without affecting non-QA routes.
- The capture script fails clearly when the expected token never appears.
- Existing QA capture/verify flows remain unchanged from the user’s perspective.
