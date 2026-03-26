# Suppressed Candidate Dedupe Design

## Goal
Collapse duplicate low-confidence manual suggestions before they reach macOS and iPhone UI, while keeping genuinely different alternatives visible.

## Problem
The processor currently appends `suppressedCandidates` in regex match order. Overlapping candidate-correction rules can emit multiple manual suggestions for the same visible span and the same corrected output. This makes the UI noisy and weakens `Apply` / `Save as Rule` confidence.

## Decision
Add shared-core post-collection normalization for suppressed candidates.

### Dedupe key
A suppressed candidate is considered a duplicate of another candidate when both of these match:
- same visible source span
  - prefer `sourceRangeLocation + sourceRangeLength` when available
  - fall back to normalized `sourceText` when the stable span is unavailable
- same normalized `resolvedReplacement`

Different corrected outputs for the same span remain distinct suggestions.

### Winner selection within a duplicate group
Keep exactly one candidate using deterministic precedence:
1. higher `confidence`
2. stronger `autoApplyPolicy`
3. candidate with `canonicalSource`
4. longer stable span / longer `sourceText`
5. lexical tie-breakers for deterministic output

### Final list ordering
Sort surviving suggestions for UI stability by:
1. `sourceRangeLocation` ascending when available
2. longer span first for the same location
3. higher `confidence`
4. lexical tie-breakers

## Scope
- shared-core only for dedupe/rerank logic
- macOS/iPhone view models should keep consuming `suppressedCandidates` exactly as before
- no UI model changes beyond inheriting the cleaner list

## Risks
- accidental collapse of truly different alternatives
- unstable ordering that changes button index semantics
- provenance loss when duplicates disagree on `canonicalSource`

## Mitigations
- include `resolvedReplacement` in dedupe key
- use deterministic comparator and explicit regression tests
- prefer a concrete winner rather than merging payloads in this slice

## Acceptance Criteria
- duplicate manual suggestions for the same span and same corrected output collapse to one
- higher-confidence duplicate wins deterministically
- distinct replacements for the same span remain separate suggestions
- macOS/iPhone shell tests observe the deduped list without changing action semantics
