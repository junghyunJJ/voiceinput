#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
RESOLVER="$ROOT_DIR/Scripts/resolve-ios-simulator.sh"

IFS=$'\t' read -r SIMULATOR_NAME SIMULATOR_UDID SIMULATOR_RUNTIME XCODE_DESTINATION < <("$RESOLVER" --preferred "${VOICEINPUT_IOS_SIMULATOR:-iPhone 17}" --allow-fallback --tsv)

echo "[1/6] Generating iOS project"
./Scripts/generate-xcode-project.sh

echo "[2/6] Validating microphone privacy keys"
plutil -extract NSMicrophoneUsageDescription raw -o - VoiceInputiOS/Resources/Info.plist >/dev/null
plutil -extract NSMicrophoneUsageDescription raw -o - VoiceInputKeyboard/Resources/Info.plist >/dev/null

echo "[3/6] Building iOS app scheme"
xcodebuild -project VoiceInputMobile.xcodeproj \
  -scheme VoiceInputiOS \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "[4/6] Building keyboard extension scheme"
xcodebuild -project VoiceInputMobile.xcodeproj \
  -scheme VoiceInputKeyboard \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "[5/6] Running iOS tests"
echo "      Using simulator: $SIMULATOR_NAME ($SIMULATOR_UDID)"
echo "      Runtime: $SIMULATOR_RUNTIME"
xcodebuild -project VoiceInputMobile.xcodeproj \
  -scheme VoiceInputiOS \
  -destination "$XCODE_DESTINATION" \
  test

echo "[6/6] Running macOS regression checks"
swift build
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme VoiceInput \
  -destination 'platform=macOS' \
  test

echo "iOS MVP verification succeeded."
