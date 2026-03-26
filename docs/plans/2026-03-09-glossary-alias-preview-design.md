# Glossary Alias Preview Design

## Goal
Expose inferred alias behavior in macOS and iPhone glossary editors so users can see what the matcher will derive without polluting persisted settings.

## Options
1. Plain footnote only: lowest effort, but still opaque.
2. Read-only suggested alias chips: recommended. Shows inferred aliases immediately, keeps saved aliases untouched.
3. One-click materialize suggestions into aliases: more control, but adds mutation complexity and clutters settings.

## Recommendation
Use read-only suggested alias chips under each glossary row. Show them only when inferred aliases exist, and keep explicit aliases editable exactly as before.

## Testing
- Core tests to lock inferred alias order/deduping for preview.
- Full build/test/iOS simulator regression.
