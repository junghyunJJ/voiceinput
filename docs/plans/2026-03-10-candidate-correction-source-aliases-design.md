# Candidate Correction Source Aliases

## Goal

Extend `TranscriptionCandidateCorrectionRule` so one candidate rule can evaluate multiple heard variants with the same confidence, evidence, and auto-apply policy.

## Why This Slice

- It directly improves mixed-language accuracy, which is the current product bottleneck.
- It fits the existing shared path: `VoiceInputCore` -> shared settings -> macOS settings -> iPhone host settings.
- It is bounded. We are not adding generative reranking or changing processor order.

## Scope

1. Add `aliases: [String]` to `TranscriptionCandidateCorrectionRule`.
2. Normalize aliases for evaluation:
   - trim whitespace
   - drop empties
   - dedupe case-insensitively
   - exclude duplicates of the primary `source`
3. Evaluate `source + aliases` with the existing candidate heuristic path.
4. Expose alias editing in macOS and iPhone settings as a comma-separated field.
5. Add red/green coverage for:
   - alias matching through the processor
   - alias round-trip through shared settings
   - alias sanitization in iPhone persistence

## Non-Goals

- No UI deduplication/refactor in this slice.
- No inferred aliases for candidate rules.
- No change to correction precedence or confidence gating.

## Risks

- Alias expansion can increase overmatching.
- Mitigation: keep the existing conservative candidate matcher and add explicit regression tests for alias-driven matching.
