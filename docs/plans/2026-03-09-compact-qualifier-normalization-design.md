# Compact Qualifier Normalization Design

## Goal
Extend deterministic glossary inference, search, and replacement coverage for compact alphanumeric model qualifiers such as `M2Ultra` / `M2-Ultra` / `M2 Ultra` without reopening family fallback.

## In Scope
- Exact `base + qualifier` forms on the existing alphanumeric compact path only.
- Supported qualifiers in this slice:
  - `Pro`
  - `Max`
  - `Ultra`
  - `Mini`
  - `Air`
- Supported separator variants between compact base and qualifier:
  - attached
  - space
  - hyphen
  - dot
  - underscore
- Runtime-only inference/search/replacement alignment in shared core.

## Out of Scope
- Bare family fallback such as `M2`
- Arbitrary new qualifiers outside the allowlist
- Schema, persistence, settings, or UI changes
- Non-alphanumeric compact paths

## Approach
- Extend the existing compact suffix parser rather than creating a new tokenizer path.
- Reuse the same compact token stream for inferred aliases, exact search gating, and replacement tokenization.
- Add a compact trailing guard in replacement so `M2 Ultra Pro` does not partially match `M2 Ultra`.

## Guardrails
- Keep exact-only semantics in search.
- Preserve current `Pro` / `Max` behavior.
- Reject stacked compact qualifiers and trailing numeric continuations during replacement.
- Keep all behavior runtime-only.

## Testing
- Positive tests for inference/search/replacement across `Ultra`, `Mini`, and `Air` examples.
- Negative tests for bare families, bare qualifiers, and stacked qualifiers such as `M2 Ultra Pro`.
- Regression coverage for existing `GPT4o`, `A17Pro`, and `M3Max` behavior.
