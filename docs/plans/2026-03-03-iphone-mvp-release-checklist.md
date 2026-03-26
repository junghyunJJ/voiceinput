# iPhone MVP Release Checklist

Date: 2026-03-03

## Automated Verification

- [x] `./Scripts/generate-xcode-project.sh`
- [x] `xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputiOS -destination 'generic/platform=iOS Simulator' build`
- [x] `xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputKeyboard -destination 'generic/platform=iOS Simulator' build`
- [x] `xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputiOS -destination 'platform=iOS Simulator,name=iPhone 17' test`
- [x] `swift build`
- [x] `xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme VoiceInput -destination 'platform=macOS' test`

## Acceptance Criteria Mapping

- AC-1 (simulator build/run): Met for simulator via both iOS app + keyboard schemes.
- Simulator install/launch now verified (`simctl install` + `simctl launch` + `simctl openurl voiceinput://open`).
- AC-2 (keyboard helper insert in third-party field): Implemented as helper-only keyboard flow (`Open App for Pro Dictation` -> host app records -> keyboard `Paste Last`). Requires manual physical-device app-to-app validation.
- AC-3 (KR/EN sanity >= 90% keyword match): Automated via `iOS Transcription Sanity Tests`.
- AC-4 (settings sync <= 3s): Keyboard extension now runs App Group sync loop every 2 seconds.
- AC-5 (permission denied recovery): Host app shows `Open iOS Settings`; keyboard stays helper-only and routes users back to the host app with `Open App for Pro Dictation`.
- Keyboard extension now includes `CFBundleDisplayName` so embedded `.appex` passes installation checks.
- AC-6 (macOS green): Verified with `swift build` and macOS test suite.
- AC-7 (iOS automated coverage for state/sync): `VoiceInputMobileTests` includes state-transition and shared-settings sync tests.
- AC-8 (privacy behavior/copy): Local-first behavior documented; no background upload path introduced.

## Manual Device Verification (Required Before Release)

1. Install `VoiceInputiOS` on a physical iPhone from `VoiceInputMobile.xcodeproj`.
2. If app launch is denied with security/trust wording, complete device trust flow (`Developer Mode` + `VPN & Device Management` trust) before continuing.
3. Add VoiceInput keyboard and enable Full Access in iOS keyboard settings.
4. Open Notes (or Messages), switch to VoiceInput keyboard.
5. Tap `Open App for Pro Dictation`, speak Korean sample phrase in the host app, and tap `Stop & Transcribe`.
6. Return to Notes and tap `Paste Last`.
7. Confirm transcribed text appears at cursor position.
8. Repeat with English sample phrase.
9. In host app, change language/model/auto-insert options.
10. Return to keyboard within 3 seconds and confirm behavior reflects updated settings.
11. Deny microphone permission and confirm:
   - host app shows actionable error and `Open iOS Settings`
   - keyboard stays helper-only and never requests microphone permission
12. Re-enable permission and verify dictation recovers without reinstall.

## Recommended Final Command

```bash
./Scripts/verify-ios-mvp.sh
```
