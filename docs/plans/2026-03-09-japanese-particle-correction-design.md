# Japanese Particle Correction Design

## Goal
Extend the shared local glossary correction layer so English product words also survive common Japanese particle attachment, for example `open aiで`, `open-aiは`, and `open aiの` becoming `OpenAIで`, `OpenAIは`, and `OpenAIの`.

## Options
1. Leave support at Korean only.
- Lowest risk.
- Does not meet the user goal for non-Korean mixed-language dictation.

2. Extend the shared suffix list with common Japanese particles. Recommended.
- Minimal change because the suffix-preserving matcher already exists.
- Shared across macOS, iPhone host app, and keyboard helper flow.
- Easy to verify with targeted tests.

3. Add a general language-plugin layer.
- Better long-term abstraction.
- Too much scope for this slice.

## Chosen Design
Use option 2 now. Keep the current matcher, but expand the attached suffix list to include explicit Japanese particles and common compounds like `では`, `には`, and `とは`. Add core and mobile shared-settings tests, then document the broader mixed-language behavior.

## Risks
- Overmatching very short suffixes.
  - Mitigation: keep suffix list explicit and noun-particle oriented.
- Scope creep into full multilingual morphology.
  - Mitigation: limit this slice to Japanese particles only.

## Verification
- Add failing tests first for Japanese particle preservation.
- Run `swift build`, `swift test`, and `xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputiOS -destination 'platform=iOS Simulator,name=iPhone 17' test`.
