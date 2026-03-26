# Full Dotted Label Regression Design

## Goal
Harden regression coverage for additional exact full dotted labels such as `Opus`, `Haiku`, `Vision`, and `Turbo` on the existing `brand + major.minor + label` path.

## In Scope
- Test coverage for exact attached / spaced / hyphenated variants on the existing full dotted path.
- Positive and negative coverage for:
  - `Claude3.7Opus`
  - `Claude3.7Haiku`
  - `Llama3.2Vision`
  - `Llama3.2Turbo`
- Shared mobile settings smoke coverage for at least one new label.
- Documentation update reflecting explicit label coverage.

## Out of Scope
- Parser changes unless a new exact-variant test fails
- New family fallback behavior
- Schema, persistence, settings, or UI changes

## Approach
- Reuse the current full dotted tokenizer and trailing-guard path unchanged.
- Add explicit regression tests proving the existing path already supports the requested labels.
- Keep the slice test-first; only change shared core if a gap appears.

## Guardrails
- Exact full dotted variants only.
- No cross-label matches.
- No base-family fallback.
- No trailing numeric or stacked-label continuation matches.

## Testing
- Positive search/inference tests for `Opus`, `Haiku`, `Vision`, and `Turbo`.
- Positive replacement tests for the same labels.
- Negative tests for wrong-label and stacked-label cases.
- Mobile shared-settings smoke test for one additional full dotted label.
