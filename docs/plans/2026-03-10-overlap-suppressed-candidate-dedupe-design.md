# Overlap-Aware Suppressed Candidate Dedupe Design

## Goal
Collapse low-confidence manual suggestions that represent the same visible fix even when their stable source ranges overlap rather than match exactly.

## Problem
The current dedupe pass only collapses candidates when `sourceRangeLocation + sourceRangeLength` are identical and `resolvedReplacement` is the same. Overlapping candidates that target the same corrected output can still reach the UI as duplicates.

## Decision
Add overlap-aware grouping in shared core.

### Grouping rule
Candidates belong to the same dedupe cluster when:
- normalized `resolvedReplacement` matches
- both have stable ranges and those ranges overlap
- or they already match the existing exact-span/text fallback key

Candidates without stable ranges keep the current exact fallback behavior.

### Winner policy
Inside one cluster:
1. higher `confidence`
2. stronger `autoApplyPolicy`
3. candidate with `canonicalSource`
4. longer span / source text
5. deterministic tie-breakers

If surviving candidates disagree on canonical provenance, the winner's `canonicalSource` becomes `nil`.

### Non-goals
- no UI-local dedupe logic
- no merge of truly different replacements
- no collapsing of separate occurrences that do not overlap

## Acceptance Criteria
- overlapping same-fix suppressed candidates collapse to one
- distinct replacements still remain separate
- distinct occurrences still remain separate
- macOS/iPhone keep consuming `suppressedCandidates` without local filtering
