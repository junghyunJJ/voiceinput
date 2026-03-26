# Glossary Search Design

## Goal
Allow users to filter glossary rows in macOS and iPhone editors by phrase, replacement, explicit aliases, and inferred aliases.

## Options
1. UI-only filter over visible fields. Lowest effort, but misses inferred aliases.
2. Shared-core search helper plus simple search field in each editor. Recommended.
3. Full searchable UI with highlighting and sections. Too heavy for this slice.

## Recommendation
Use a shared TranscriptionGlossaryItem.matchesSearchQuery helper and add a compact search field above glossary rows in both editors. Include inferred aliases in matching so users can find items via `open-ai` even when that alias is not persisted.

## Tests
- Shared-core tests for phrase/replacement/explicit alias/inferred alias matching.
- Full build, package test, and iOS simulator regression.
