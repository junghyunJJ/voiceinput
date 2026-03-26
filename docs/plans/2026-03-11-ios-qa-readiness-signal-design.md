# iOS QA Readiness Signal Design

## Goal
Replace the fixed settle delay in `Scripts/capture-ios-qa-gallery.sh` with an explicit readiness signal so snapshot capture waits for the intended QA screen instead of an arbitrary timeout.

## Recommended Approach
Use a `DEBUG`-only launch contract:

1. The capture script generates a unique `--qa-ready-token` per launch.
2. The app resolves the existing QA launch route plus the optional ready token.
3. The rendered QA root view writes the token and a deterministic screen identifier into a marker file under the app data container caches directory.
4. The capture script resolves that app data container and polls the marker file for the exact token and screen identifier before taking the screenshot.

## Why This Approach
- No production behavior change. The reporter exists only in `DEBUG` QA launch paths.
- No fixed timing dependency. Readiness is tied to the actual QA screen route.
- Stale data is rejected because each launch uses a new token and clears the previous marker file before launch.
- The script stays simple and local; it does not need accessibility scraping or simulator log parsing.

## Trade-offs
- The signal is still app-cooperative. If the QA screen stops reporting readiness, capture fails fast.
- File-based polling is slightly more plumbing than a raw sleep, but it is explicit and decoupled from simulator defaults state.
- The ready write should happen only after the QA view has been attached to a window and laid out so the screenshot is not captured mid-transition.

## Acceptance Criteria
- `capture-ios-qa-gallery.sh` no longer uses `sleep 3` as the readiness gate.
- The app can emit a deterministic `token + screenIdentifier` pair for `--qa-gallery`, `--qa-keyboard-gallery`, and `--qa-host-state <state>`.
- The script fails with a clear timeout message if readiness never appears.
- A fresh QA capture succeeds using the readiness gate.
- Existing iOS QA snapshot verification still passes.
