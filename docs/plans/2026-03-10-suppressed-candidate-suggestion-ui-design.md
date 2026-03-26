# Suppressed Candidate Suggestion UI

## Goal

Expose low-confidence candidate corrections that the core already computes, and let users apply them manually in macOS and iPhone host UI.

## Why This Slice

- `suppressedCandidates` already exist in `VoiceInputCore`.
- Current app/host UIs throw that signal away.
- This is the smallest change that turns existing mixed-language accuracy work into visible user value.

## Scope

1. Extend `TranscriptionCandidateCorrection` with the actual replacement text to apply locally.
2. Store suppressed candidate suggestions in:
   - `AppViewModel`
   - `IOSDictationViewModel`
3. Add safe manual apply:
   - only apply if the suggestion `sourceText` still exists in the current visible text
   - replace with the precomputed resolved replacement text
   - refresh suggestion list after apply
4. Render suggestion lists in:
   - macOS menu bar UI
   - iPhone host app below the latest transcription

## Non-Goals

- No keyboard helper suggestion UI in this slice.
- No new reranking engine.
- No automatic application beyond existing confidence policy.

## Risks

- Stale suggestions could rewrite the wrong text if the transcript changed.
- Mitigation: manual apply is guarded by `sourceText` presence in the current text, and suggestions are recomputed after apply.
