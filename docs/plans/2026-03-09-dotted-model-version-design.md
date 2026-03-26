# Dotted Model Version Normalization Design

## Goal
Add deterministic glossary inference, search, and replacement coverage for exact dotted model versions such as `Claude3.7` / `Claude-3.7` / `Claude 3.7` without introducing family fallback or fuzzy version parsing.

## In Scope
- Exact `brand + major.minor` model forms only.
- Supported separator variants between brand and dotted version:
  - attached
  - space
  - hyphen
- Initial examples:
  - `Claude3.7`, `Claude-3.7`, `Claude 3.7`
  - `Llama3.2`, `Llama-3.2`, `Llama 3.2`
- Runtime-only inference/search/replacement alignment in shared core.

## Out of Scope
- Spoken or split versions such as `3 7` or `three point seven`
- Family fallback such as `Claude 3`
- Extended labels such as `Claude 3.7 Sonnet`
- Bare decimals such as `3.7`
- Persistence, UI, or schema changes

## Approach Options
1. Dedicated dotted-version tokenizer path in shared core.
   - Pros: narrow, deterministic, keeps existing generic tokenization untouched.
   - Cons: adds one more specialized parser.
2. Broaden generic tokenization to preserve dotted decimals everywhere.
   - Pros: less branching.
   - Cons: high risk of overmatching non-model decimals and reintroducing family fallback.
3. Hardcode individual model families.
   - Pros: safest.
   - Cons: not reusable and not worth the maintenance cost.

## Recommendation
Use option 1. Add a dotted-version tokenizer parallel to the compact-model tokenizer. It should emit semantic units like `["claude", "3.7"]` or `["llama", "3.2"]`, then reuse the existing separator-variant flow so inference, search, and replacement all stay aligned.

## Guardrails
- Require both the brand token and the exact dotted version token.
- Do not split `3.7` into `3` and `7`.
- Do not admit bare decimal matches or extended labels.
- Keep all behavior runtime-only.

## Testing
- Positive tests for inference/search/replacement across attached, spaced, and hyphenated forms.
- Negative tests for `Claude 3`, `Claude3`, `Claude 3 7`, `Claude 3 Opus`, bare `3.7`, `Llama 3`, and `Llama 3 2`.
- Regression tests proving compact-model behavior for `GPT4o`, `A17Pro`, and `M3Max` remains intact.
