# Mixed-Language Accuracy V2 Design

## Problem
Current local post-processing is strong for exact glossary aliases, separator variants, particles, and deterministic candidate rules. It is still weak when ASR hears English acronyms or mixed-brand endings as spoken Korean/Japanese letter names or spaced letter sequences, for example `지피티`, `에이피아이`, or `chat g p t`.

## Goal
Deepen mixed-language accuracy without introducing cloud dependencies or broad hallucination risk.

## Chosen Approach
Harden existing acronym inference instead of broadening it blindly.

### Scope
- Preserve existing glossary acronym inference and fill the remaining gaps:
  - keep legacy English separator forms such as `g-p-t`
  - keep Korean/Japanese phonetic acronym coverage
- Narrow candidate-correction matching so it reuses only replacement-side acronym/phonetic expansions, not generic collapsed replacement aliases.
- Support:
  - letter-separated ASCII acronym variants such as `g p t`, `a p i`
  - punctuation-separated ASCII acronym variants such as `g-p-t`, `a_p_i`
  - Korean phonetic acronym variants such as `지피티`, `에이피아이`
  - Japanese phonetic acronym variants such as `ジーピーティー`, `エーピーアイ`
  - mixed variants for seeds like `ChatGPT` -> `chat g p t`, `chat 지피티`, `chat ジーピーティー`
- Keep the heuristic local and bounded to configured glossary/candidate entries only.

## Rejected Alternatives
1. General transliteration of arbitrary English words
- Too much ambiguity and risk of false positives.

2. Decoder-level reranking or model changes
- Higher value long term, but materially larger and not the next safe slice.

## Safety Constraints
- No free-form guessing for unconfigured terms.
- Only infer variants from ASCII seeds already present in glossary phrase/replacement or candidate rule replacement.
- Preserve existing exact/dotted/compact variant boundaries.
- Do not change auto-apply semantics.
- Do not let candidate replacement inference re-match the already normalized canonical replacement text.

## Verification
- Add red-first tests for:
  - legacy punctuation-separated acronym forms
  - explicit correction precedence over candidate rewrites
  - candidate replacement-side acronym inference without canonical collapsed overmatch
- Run `swift test`, `swift build`, and `xcodebuild ... VoiceInputiOS ... test`.
