# Mixed-Language Correction Design

## Goal
Improve local glossary-driven post-processing so mixed-language transcriptions are corrected without any cloud model. The immediate target is aliases such as `open ai`, `open-ai`, and `open.ai`, plus attached particles such as `open ai에서`, resolving to the glossary replacement (`OpenAI`) across macOS, iPhone host app, and keyboard helper flows.

## Approach Options
1. Exact-only replacement.
- Lowest risk.
- Insufficient for the main user problem because punctuation/spacing and attached particles still fail.

2. Flexible alias matching in shared core. Recommended.
- Expand glossary alias matching to tolerate separator variants and attached language particles.
- Keeps behavior deterministic and shared across macOS/iPhone/keyboard.
- Limited scope and testable with current architecture.

3. Heuristic candidate re-ranking layer.
- Stronger future direction.
- Larger scope and more regression risk for this slice.

## Chosen Design
Implement option 2 in `VoiceInputCore` so all product shells inherit the same behavior automatically.

### Matching rules
- Normalize glossary aliases for persistence first.
- Build replacement patterns that match:
  - exact aliases with word boundaries
  - flexible separator variants across spaces, hyphens, underscores, slashes, and dots
  - attached postposition/particle suffixes for common mixed-language cases
- Preserve the matched suffix while replacing only the glossary phrase.
- Prefer longer variants before shorter ones to reduce accidental partial replacement.

### Scope boundaries
- No LLMs.
- No new settings surface.
- No model-level rescoring.
- No per-language ML heuristics in this slice.

## Risks
- Overmatching short glossary items.
  - Mitigation: longest-first ordering and boundary checks remain for non-suffix cases.
- Particle heuristics may be incomplete.
  - Mitigation: keep suffix set explicit and small; validate with tests.

## Verification
- Add failing core tests first for separator-tolerant replacement and attached Korean particle replacement.
- Add one shared mobile test to prove host/keyboard shared settings get the improved correction path.
- Run `swift build`, `swift test`, and `xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputiOS -destination 'platform=iOS Simulator,name=iPhone 17' test`.
