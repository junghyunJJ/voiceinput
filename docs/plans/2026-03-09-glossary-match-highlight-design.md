# Glossary Match Highlight Design

## Goal
Make glossary search results easier to scan by highlighting the matched substring inside compact `Matched on` chips.

## Options
1. UI-only ad hoc range search per platform. Fast but duplicates logic.
2. Shared-core highlight metadata on top of existing search match metadata. Recommended.
3. Full rich text highlighting inside text fields. Too invasive for this slice.

## Recommendation
Extend shared-core search match metadata with the first matched range for each hit. Keep filtering behavior unchanged, and render compact attributed chips that bold/tint only the matched substring. Apply highlight only inside `Matched on` chips, not the editable text fields.

## Constraints
- No persistence changes.
- Keep chips compact and deterministic.
- Focus-preserved rows with no real match still show no explanation.

## Tests
- Core tests for highlighted ranges across phrase, alias, and suggested alias hits.
- Full build, package tests, and iOS simulator regression.
