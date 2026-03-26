# VoiceInput iPhone Expansion Architecture

Date: 2026-03-03  
Status: Accepted (Phase 0 complete)

## Context
VoiceInput currently ships as a macOS-only menu bar app (`AppKit` + Accessibility insertion). The target is to support iPhone workflows inspired by Monologue while preserving local-first transcription and minimizing regression risk for macOS.

## Decision Summary
1. Introduce a new cross-platform core module (`VoiceInputCore`) with Foundation-only types.
2. Keep macOS-specific orchestration in the existing `VoiceInput` executable target.
3. Add iOS host app and keyboard extension in a dedicated Xcode target set in a later phase, both depending on `VoiceInputCore`.
4. Use App Group `UserDefaults` as the first shared-state channel between iOS host app and keyboard extension.
5. Keep transcription engine abstraction in shared code, but allow different runtime strategies by target (host app direct model vs extension fallback strategy).

## Boundaries
- `VoiceInputCore` (shared):
  - Recording/session state model
  - Language and recording mode enums
  - Shared settings schema and App Group persistence
  - Target-neutral contracts for dictation session behavior
- `VoiceInput` (macOS app):
  - Menu bar UI, overlay, hotkeys, Accessibility insertion, AppKit integrations
  - Existing WhisperKit loading path
- iOS Host App (future target):
  - Onboarding, permission UX, settings, quick-note transcription screen
- iOS Keyboard Extension (future target):
  - Record/stop UI and insertion via `textDocumentProxy`

## Why This Approach
1. Lowest regression risk: existing macOS behavior remains intact while new iOS work lands on shared contracts.
2. Incremental delivery: shared module can be tested now before adding app/extension targets.
3. iOS constraints compatibility: keyboard extension lifecycle and permission model are explicitly separated from macOS assumptions.

## Alternatives Considered
1. Monolithic cross-platform target (rejected): mixes `AppKit`/`UIKit` concerns, high compile and maintenance risk.
2. Full rewrite for multiplatform app (rejected): too costly and delays iPhone MVP.
3. Cloud-only iOS path (rejected for MVP): violates privacy-first product direction.

## Key Risks
1. Keyboard extension resource limits can constrain on-device model runtime.
2. Some apps restrict custom keyboard behavior.
3. Shared refactor can still produce subtle macOS regression if contracts diverge.

## Mitigations
1. Keep extension logic lightweight and allow host-assisted fallback design.
2. Explicit compatibility messaging in onboarding and settings.
3. Add focused tests in `VoiceInputCore` and preserve existing macOS verification (`swift build` + Xcode tests).

## Immediate Implementation Scope (This Iteration)
1. Create `VoiceInputCore` target and baseline shared types.
2. Add tests for shared settings persistence and session state transitions.
3. Keep existing macOS executable target green.
4. Enforce explicit App Group validation policy in shared settings store to prevent silent host/keyboard desync.
5. Preserve migration safety by mirroring legacy `hotkeyMode` key during transition.

## Phase 1 Adoption Path (to avoid model divergence)
1. Keep app-local enums temporarily, but introduce adapters at target boundaries.
2. Migrate settings read/write first (`AppSettings` -> `AppGroupSettingsStore` bridge).
3. Migrate session state usage next (`AppViewModel` state transitions through shared machine).
4. Remove duplicate local enums only after both macOS and iOS compile against `VoiceInputCore`.

## Deferred to Next Iterations
1. iOS host app target scaffolding and onboarding flows.
2. Keyboard extension target scaffolding and insertion pipeline.
3. End-to-end iPhone device validation.
