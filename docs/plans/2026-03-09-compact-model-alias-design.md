# Compact Model Alias Normalization Design

## Goal
Add deterministic glossary inference and replacement coverage for compact alphanumeric model names without introducing fuzzy matching or broader version-family inference.

## In Scope
- Normalize exact model-name token sequences across attached, spaced, and hyphenated forms for:
  - `GPT4o` / `GPT-4o` / `GPT 4o`
  - `A17Pro` / `A17 Pro` / `A17-Pro`
  - `M3Max` / `M3 Max` / `M3-Max`
- Keep inference runtime-only.
- Reuse the same tokenization logic in shared glossary alias inference and post-transcription replacement matching.

## Out of Scope
- Dotted semantic versions such as `Claude 3.7`
- Suffix dropping or family fallback such as matching `GPT-4o` from `GPT-4`
- Fuzzy matching, LLM correction, persistence/schema changes, or UI changes

## Approach Options
1. Dedicated compact-model tokenization path before generic alias tokenization.
   - Pros: narrow blast radius, easy to gate to approved patterns, shared by inference and replacement.
   - Cons: adds one more parsing branch.
2. Broaden generic camelCase/ASCII tokenization for all alphanumeric seeds.
   - Pros: less code branching.
   - Cons: high risk of overmatching unrelated numeric brands and dotted versions.
3. Hardcode specific model families.
   - Pros: very safe.
   - Cons: poor extensibility and not worth the maintenance burden.

## Recommendation
Use option 1. Add a dedicated compact-model tokenizer that only emits semantic units for the approved pattern family:
- leading letters+digits as one unit when the seed is compacted (`A17`, `M3`)
- digits+short lowercase suffix as one unit for forms like `4o`
- optional trailing capitalized qualifier unit like `Pro` or `Max`

The tokenizer will feed both inferred alias generation and replacement variant generation so search, suggestion preview, and runtime correction stay aligned.

## Data Flow
- `TranscriptionGlossaryItem.inferredAliases` asks for token sequences.
- If the seed matches the compact-model shape, emit model units and generate separator variants from those units.
- Otherwise fall back to the existing generic separator inference.
- `PostTranscriptionProcessor` uses the same semantic-unit splitting when building replacement variants.

## Guardrails
- Never emit truncated families such as `GPT-4`, `A17`, or `M3` from richer forms.
- Never persist inferred aliases into stored glossary entries.
- Keep dotted versions on the existing path, unchanged.

## Testing
- Positive inference/replacement tests for `GPT4o`, `A17Pro`, `M3Max` across attached/spaced/hyphenated variants.
- Negative boundary tests proving no fallback to `GPT-4`, `A17`, or `M3`.
- Regression test proving `Claude 3.7` remains unaffected.
- Shared-settings/mobile regression proving inference remains runtime-only.
