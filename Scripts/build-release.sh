#!/bin/bash
set -euo pipefail

# ============================================================================
# VoiceInput - Build, Sign, Notarize, and Package as DMG
# ============================================================================
# Prerequisites:
#   - Xcode 16+ installed
#   - Apple Developer ID certificate in keychain
#   - App-specific password stored in keychain for notarization
#
# Usage:
#   ./Scripts/build-release.sh
#
# Environment variables (optional overrides):
#   TEAM_ID        - Apple Developer Team ID
#   SIGN_IDENTITY  - Code signing identity (default: "Developer ID Application")
#   APPLE_ID       - Apple ID for notarization
#   KEYCHAIN_PROFILE - Notarytool keychain profile name
# ============================================================================

APP_NAME="VoiceInput"
SCHEME="${APP_NAME}"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-voiceinput-notarize}"

echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# ---- Archive ----
echo "==> Archiving ${APP_NAME}..."
xcodebuild archive \
    -scheme "${SCHEME}" \
    -archivePath "${ARCHIVE_PATH}" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    | tail -5

# ---- Export ----
echo "==> Exporting archive..."

# Create export options plist
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
cat > "${EXPORT_OPTIONS}" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    | tail -5

# ---- Sign WhisperKit dylibs (if unsigned) ----
echo "==> Signing embedded frameworks..."
find "${APP_PATH}" -name "*.dylib" -o -name "*.framework" | while read -r lib; do
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${lib}" 2>/dev/null || true
done

# Re-sign the main app bundle
codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp --options runtime \
    --entitlements "VoiceInput/Resources/VoiceInput.entitlements" \
    "${APP_PATH}"

echo "==> Verifying code signature..."
codesign --verify --deep --strict "${APP_PATH}"
spctl --assess --type execute --verbose "${APP_PATH}"

# ---- Notarize ----
echo "==> Creating ZIP for notarization..."
ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Submitting for notarization..."
xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "${APP_PATH}"

# ---- Create DMG ----
echo "==> Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${APP_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Sign the DMG
codesign --sign "${SIGN_IDENTITY}" --timestamp "${DMG_PATH}"

echo ""
echo "==> Build complete!"
echo "    Archive: ${ARCHIVE_PATH}"
echo "    App:     ${APP_PATH}"
echo "    DMG:     ${DMG_PATH}"
echo ""
echo "    DMG size: $(du -h "${DMG_PATH}" | cut -f1)"
