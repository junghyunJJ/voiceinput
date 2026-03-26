# Full Dotted Model Variant Normalization Design

## Goal
Add deterministic glossary inference, search, and replacement coverage for exact full dotted model variants such as `Claude3.7Sonnet` / `Claude-3.7-Sonnet` / `Claude 3.7 Sonnet` without reopening base-family fallback.

## In Scope
- Exact `brand + major.minor + trailingLabel` model forms only.
- Supported separator variants between tokens:
  - attached
  - space
  - hyphen
- Initial examples:
  - `Claude3.7Sonnet`, `Claude-3.7-Sonnet`, `Claude 3.7 Sonnet`
  - `Llama3.2Instruct`, `Llama-3.2-Instruct`, `Llama 3.2 Instruct`
- Runtime-only inference/search/replacement alignment in shared core.

## Out of Scope
- Base-family fallback such as `Claude 3.7` or `Claude 3`
- Wrong-label matches such as `Claude 3.7 Opus` when the glossary entry is `Claude 3.7 Sonnet`
- Spoken or split versions such as `Claude 3 7 Sonnet`
- Bare labels or bare versions
- Persistence, UI, or schema changes

## Approach Options
1. Dedicated full-variant tokenizer path in shared core.
   - Pros: keeps existing base dotted-version path narrow and deterministic.
   - Cons: adds another specialized parser.
2. Broaden the base dotted-version tokenizer to allow optional labels.
   - Pros: less code branching.
   - Cons: high risk of family fallback and wrong-label overmatching.
3. Hardcode exact supported labels per family.
   - Pros: safest.
   - Cons: not reusable and becomes product-specific too early.

## Recommendation
Use option 1. Add a full-variant tokenizer parallel to the existing dotted-version tokenizer. It should emit semantic units like `["claude", "3.7", "sonnet"]` and `["llama", "3.2", "instruct"]`, then reuse the same token stream for alias inference, exact search gating, and deterministic replacement.

## Guardrails
- Require all three semantic tokens.
- Do not collapse full variants into base dotted versions.
- Do not admit cross-label matches.
- Preserve attached Korean/Japanese suffix replacement behavior for exact full variants.
- Reject extra trailing model labels or trailing numeric qualifiers during replacement.

## Testing
- Positive tests for inference/search/replacement across attached, spaced, and hyphenated forms.
- Negative tests for `Claude 3.7`, `Claude 3`, `Claude 3.7 Opus`, `Claude 3.7 Sonnet 4`, `Llama 3.2`, and `Llama 3.2 Vision`.
- Coexistence test proving a longer full variant wins when both `Claude 3.7` and `Claude 3.7 Sonnet` glossary entries are present.
