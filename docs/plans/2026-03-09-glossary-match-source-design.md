# Glossary Match Source Design

## Goal
When a glossary row appears under search, explain why it matched without changing search behavior.

## Options
1. UI-only heuristics per platform. Fast but duplicates logic and drifts.
2. Shared-core search match metadata. Recommended.
3. Full highlighted substring rendering. Too heavy for this slice.

## Recommendation
Add shared-core search match metadata that records source (`phrase`, `replacement`, `explicitAlias`, `suggestedAlias`) and matched value. Keep the existing filter behavior, and render a compact read-only explanation under matching rows when search is active.

## Constraints
- No persistence changes.
- Focus-preserved rows that are visible only because they are being edited should not show a fake match explanation.
- Keep the UI compact; show only the first one or two matches.

## Tests
- Core tests for source classification and empty-query behavior.
- Full build, package tests, and iOS simulator regression.
