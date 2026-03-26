# Glossary Auto Alias Design

## Goal
Infer deterministic English product-name alias variants at match time so users can enter a canonical term once and still match common spoken/rendered variants.

## Scope
- Shared core only; no cloud or model dependency.
- No persistence inflation: inferred aliases are not written back into saved settings.
- Match-time inference from phrase/replacement for ASCII product-like terms.

## Rules
- Split ASCII seeds on separators and camel/acronym boundaries.
- Generate common variants: spaced, joined, hyphen, dot, underscore.
- Deduplicate against explicit aliases and canonical phrase.
- Keep Korean/Japanese particle-preserving matcher behavior unchanged.

## Verification
- Red/green tests in core processor and shared settings sync.
- Full `swift build`, `swift test`, and iOS simulator tests.
