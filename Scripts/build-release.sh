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
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
EXPORT_PATH="${BUILD_DIR}/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-voiceinput-notarize}"

preflight_signing_identity() {
    echo "==> Checking code signing identity..."

    local identities
    if ! identities="$(security find-identity -v -p codesigning 2>&1)"; then
        cat >&2 <<EOF
error: unable to inspect code signing identities.

security find-identity failed with:
${identities}
EOF
        exit 1
    fi

    local matching_identities
    matching_identities="$(printf '%s\n' "${identities}" | awk -v identity="${SIGN_IDENTITY}" 'index($0, identity) > 0')"

    if [[ -z "${matching_identities}" ]]; then
        cat >&2 <<EOF
error: signing identity '${SIGN_IDENTITY}' was not found.

Release builds must be signed with a Developer ID Application certificate.
Install the certificate in your keychain, or set SIGN_IDENTITY to the exact
Developer ID identity name:

  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build-release.sh

Available code signing identities:
${identities}
EOF
        exit 1
    fi

    if ! printf '%s\n' "${matching_identities}" | grep -Fq -- '"Developer ID Application'; then
        cat >&2 <<EOF
error: signing identity '${SIGN_IDENTITY}' is not a Developer ID Application identity.

Release builds are notarized for public distribution and cannot use an Apple
Development or ad-hoc signing identity. Use a Developer ID Application
certificate, for example:

  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build-release.sh

Matching code signing identities:
${matching_identities}
EOF
        exit 1
    fi
}

preflight_signing_identity

echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# ---- Build ----
echo "==> Building ${APP_NAME} with SwiftPM..."
swift build -c release --package-path "${PROJECT_DIR}"
BINARY_PATH="$(swift build -c release --package-path "${PROJECT_DIR}" --show-bin-path)/${APP_NAME}"

if [[ ! -x "${BINARY_PATH}" ]]; then
    echo "error: release binary not found at ${BINARY_PATH}" >&2
    exit 1
fi

# ---- Bundle ----
echo "==> Creating app bundle..."
mkdir -p "${APP_PATH}/Contents/MacOS"
cp "${BINARY_PATH}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
cp "${PROJECT_DIR}/VoiceInput/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

# ---- Sign embedded code ----
echo "==> Signing embedded code..."
find "${APP_PATH}/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0 | while IFS= read -r -d '' lib; do
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${lib}"
done

# Re-sign the main app bundle
codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp --options runtime \
    --entitlements "${PROJECT_DIR}/VoiceInput/Resources/VoiceInput.entitlements" \
    "${APP_PATH}"

echo "==> Verifying code signature..."
codesign --verify --deep --strict "${APP_PATH}"

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

echo "==> Assessing notarized app..."
spctl --assess --type execute --verbose "${APP_PATH}"

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
echo "    App:     ${APP_PATH}"
echo "    DMG:     ${DMG_PATH}"
echo ""
echo "    DMG size: $(du -h "${DMG_PATH}" | cut -f1)"
