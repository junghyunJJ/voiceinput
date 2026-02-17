#!/bin/bash
# Build, sign, and launch VoiceInput for development
# Creates .app bundle in ~/Applications with proper signing for Accessibility

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$PROJECT_DIR/.build/arm64-apple-macosx/debug/VoiceInput"
APP_DIR="$HOME/Applications/VoiceInput.app"
SIGNING_IDENTITY="VoiceInput Dev"
BUNDLE_ID="com.voiceinput.app"

# Kill existing instance
pkill -f "VoiceInput.app/Contents/MacOS/VoiceInput" 2>/dev/null || true
sleep 1

echo "Building..."
swift build 2>&1

# Create .app bundle
echo "Creating .app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BINARY" "$APP_DIR/Contents/MacOS/VoiceInput"
cp "$PROJECT_DIR/VoiceInput/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Sign the .app bundle
echo "Signing with '$SIGNING_IDENTITY'..."
codesign --force --deep --sign "$SIGNING_IDENTITY" \
  --identifier "$BUNDLE_ID" \
  "$APP_DIR"

echo "Launching..."
open "$APP_DIR"

echo "Done. VoiceInput.app is running."
echo "Add to Accessibility: $APP_DIR"
