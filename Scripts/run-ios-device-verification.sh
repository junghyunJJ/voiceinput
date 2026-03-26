#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  cat <<'USAGE'
Usage:
  ./Scripts/run-ios-device-verification.sh <DEVICE_ID_OR_NAME>
  ./Scripts/run-ios-device-verification.sh <DEVELOPMENT_TEAM_ID> <DEVICE_ID_OR_NAME>

Examples:
  ./Scripts/run-ios-device-verification.sh "John's iPhone"
  ./Scripts/run-ios-device-verification.sh 00008110-0012345678901234
  ./Scripts/run-ios-device-verification.sh ABCD123456 "John's iPhone"
  ./Scripts/run-ios-device-verification.sh ABCD123456 00008110-0012345678901234

Tip:
  List available devices with:
    xcrun devicectl list devices
USAGE
  exit 1
fi

TEAM_ID=""
DEVICE_ID=""
if [[ $# -eq 1 ]]; then
  DEVICE_ID="$1"
else
  TEAM_ID="$1"
  DEVICE_ID="$2"
fi

DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedDataMobile"
APP_BUNDLE_ID="com.voiceinput.ios"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/VoiceInputiOS.app"
KEYBOARD_PATH="$APP_PATH/PlugIns/VoiceInputKeyboard.appex"
EXPECTED_APP_GROUP_ID="group.com.jungj2.voiceinput.shared"

read_signing_authority() {
  codesign -dvv "$APP_PATH" 2>&1 | sed -n 's/^Authority=//p' | head -n 1
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$timeout_seconds" "$@"
}

print_device_state() {
  local details_json
  details_json="$(mktemp)"
  if xcrun devicectl device info details --device "$DEVICE_ID" --json-output "$details_json" >/dev/null 2>&1; then
    python3 - "$details_json" <<'PY'
import json,sys
def as_dict(value):
    return value if isinstance(value, dict) else {}
try:
    with open(sys.argv[1]) as f:
        data=json.load(f)
except Exception:
    data={}
result=as_dict(as_dict(data).get("result"))
device=as_dict(result.get("deviceProperties"))
conn=as_dict(result.get("connectionProperties"))
print("Device state:")
print(f"- developerModeStatus: {device.get('developerModeStatus','unknown')}")
print(f"- bootState: {device.get('bootState','unknown')}")
print(f"- pairingState: {conn.get('pairingState','unknown')}")
print(f"- tunnelState: {conn.get('tunnelState','unknown')}")
PY
  fi
  rm -f "$details_json"

  local lock_out
  lock_out="$(xcrun devicectl device info lockState --device "$DEVICE_ID" 2>/dev/null || true)"
  local passcode_required unlocked_since_boot
  passcode_required="$(printf '%s\n' "$lock_out" | sed -n 's/.*passcodeRequired: //p' | head -n1)"
  unlocked_since_boot="$(printf '%s\n' "$lock_out" | sed -n 's/.*unlockedSinceBoot: //p' | head -n1)"
  if [[ -n "$passcode_required" || -n "$unlocked_since_boot" ]]; then
    echo "- passcodeRequired: ${passcode_required:-unknown}"
    echo "- unlockedSinceBoot: ${unlocked_since_boot:-unknown}"
  fi
}

check_device_readiness() {
  local details_json
  details_json="$(mktemp)"
  if ! xcrun devicectl device info details --device "$DEVICE_ID" --json-output "$details_json" >/dev/null 2>&1; then
    rm -f "$details_json"
    cat <<'EOF'
Warning: Unable to read detailed device state.
Proceeding anyway, but launch may fail if pairing or Developer Mode is not ready.
EOF
    return 0
  fi

  local state_line
  state_line="$(python3 - "$details_json" <<'PY'
import json,sys
def as_dict(value):
    return value if isinstance(value, dict) else {}
try:
    with open(sys.argv[1]) as f:
        data=json.load(f)
except Exception:
    data={}
result=as_dict(as_dict(data).get("result"))
device=as_dict(result.get("deviceProperties"))
conn=as_dict(result.get("connectionProperties"))
print(
    f"{device.get('developerModeStatus','unknown')}\t"
    f"{device.get('bootState','unknown')}\t"
    f"{conn.get('pairingState','unknown')}"
)
PY
)"
  rm -f "$details_json"

  local developer_mode boot_state pairing_state
  IFS=$'\t' read -r developer_mode boot_state pairing_state <<< "$state_line"
  developer_mode="${developer_mode:-unknown}"
  boot_state="${boot_state:-unknown}"
  pairing_state="${pairing_state:-unknown}"

  if [[ "$developer_mode" != "enabled" ]]; then
    cat <<'EOF'
Developer Mode is not enabled on the device.
Enable it at Settings > Privacy & Security > Developer Mode, then reboot and retry.
EOF
    return 1
  fi

  if [[ "$boot_state" != "booted" ]]; then
    if [[ "$boot_state" == "unknown" ]]; then
      echo "Warning: Device boot state is 'unknown'. Continuing because pairing/developer mode are ready."
    else
      echo "Device boot state is not ready: $boot_state"
      return 1
    fi
  fi

  if [[ "$pairing_state" != "paired" ]]; then
    cat <<EOF
Device pairing state is '$pairing_state' (expected: paired).
Reconnect cable, unlock iPhone, approve 'Trust This Computer', then retry.
EOF
    return 1
  fi

  local lock_out
  lock_out="$(xcrun devicectl device info lockState --device "$DEVICE_ID" 2>/dev/null || true)"
  local passcode_required unlocked_since_boot
  passcode_required="$(printf '%s\n' "$lock_out" | sed -n 's/.*passcodeRequired: //p' | head -n1)"
  unlocked_since_boot="$(printf '%s\n' "$lock_out" | sed -n 's/.*unlockedSinceBoot: //p' | head -n1)"

  if [[ "$passcode_required" == "true" ]]; then
    cat <<'EOF'
Device appears locked (passcode required).
Unlock iPhone, keep it on the Home Screen, and keep the screen awake while installing.
EOF
    return 1
  fi

  if [[ "$unlocked_since_boot" == "false" ]]; then
    cat <<'EOF'
Device must be unlocked at least once after reboot before development installs can proceed.
Unlock with passcode once, then retry.
EOF
    return 1
  fi

  return 0
}

print_signing_guidance() {
  local detected_team="${1:-<unknown>}"
  cat <<EOF

Signing failed for team: $detected_team

Do this once in Xcode:
1. Xcode > Settings > Accounts: sign in with the Apple ID that owns your iPhone development certificate.
2. Open VoiceInputMobile.xcodeproj.
3. VoiceInputiOS target > Signing & Capabilities:
   - Automatically manage signing: ON
   - Team: choose the same signed-in account.
4. VoiceInputKeyboard target: set the same Team.
5. Press "Try Again" or "Fix Issue".

Then re-run:
  ./Scripts/run-ios-device-verification.sh "$DEVICE_ID"
EOF
}

print_trust_guidance() {
  local signer
  signer="$(read_signing_authority)"
  cat <<EOF

Launch was blocked by iOS security trust checks.
Code signer:
- ${signer:-<unknown signer>}

On the iPhone:
1. Keep the phone unlocked and open VoiceInputiOS from Home Screen once.
2. If a trust dialog appears, approve it.
3. Settings > Privacy & Security > Developer Mode: ON
4. Settings > General > VPN & Device Management > Developer App: Trust your Apple ID
   (if shown: tap "Allow & Restart", reboot, then unlock and retry).
5. Keep the phone on network while trusting (Apple verification endpoint: https://ppq.apple.com).
6. If it still fails: Settings > General > Transfer or Reset iPhone > Reset > Reset Location & Privacy,
   reconnect cable, trust computer again, then re-run.

Then re-run:
  ./Scripts/run-ios-device-verification.sh "$DEVICE_ID"
EOF
}

show_launch_json_diagnostics() {
  local launch_json="$1"
  [[ -s "$launch_json" ]] || return 0

  python3 - "$launch_json" <<'PY'
import json,sys
try:
    with open(sys.argv[1]) as f:
        payload=json.load(f)
except Exception:
    sys.exit(0)

def as_dict(value):
    if not isinstance(value, dict):
        return {}
    current=value
    while isinstance(current.get("error"), dict) and len(current) == 1:
        current=current.get("error")
    return current

def as_string(value):
    if isinstance(value, str):
        return value
    if isinstance(value, (int, float, bool)):
        return str(value)
    if isinstance(value, dict):
        for key in ("string", "value", "description", "number", "code", "domain"):
            if key in value:
                out=as_string(value.get(key))
                if out:
                    return out
    return ""

def as_int(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        s=value.strip()
        if s.isdigit():
            return int(s)
        return None
    if isinstance(value, dict):
        for key in ("number", "int", "value", "code", "string"):
            if key in value:
                out=as_int(value.get(key))
                if out is not None:
                    return out
    return None

err=as_dict(payload.get("error"))
if not err:
    sys.exit(0)

user_info=as_dict(err.get("userInfo"))
domain=as_string(err.get("domain")) or "unknown"
code_num=as_int(err.get("code"))
code=code_num if code_num is not None else (as_string(err.get("code")) or "unknown")
desc=as_string(user_info.get("NSLocalizedDescription"))
under=as_dict(user_info.get("NSUnderlyingError"))
under_domain=as_string(under.get("domain"))
under_code_num=as_int(under.get("code"))
under_code=under_code_num if under_code_num is not None else as_string(under.get("code"))
under_reason=as_string(as_dict(under.get("userInfo")).get("NSLocalizedFailureReason"))

print("Launch diagnostics (json):")
print(f"- CoreDevice error: {domain} ({code})")
if desc:
    print(f"- Description: {desc}")
if under_domain or under_code:
    print(f"- Underlying error: {under_domain} ({under_code})")
if under_reason:
    print(f"- Underlying reason: {under_reason}")
PY
}

is_trust_blocked() {
  local launch_log="$1"
  local launch_json="$2"

  if grep -Eiq "invalid code signature|profile has not been explicitly trusted|RequestDenied|inadequate entitlements|FBSOpenApplicationErrorDomain|BSErrorCodeDescription = Security" "$launch_log"; then
    return 0
  fi

  local verdict
  verdict="$(python3 - "$launch_json" <<'PY'
import json,sys
try:
    with open(sys.argv[1]) as f:
        payload=json.load(f)
except Exception:
    print("no")
    raise SystemExit(0)

def as_dict(value):
    if not isinstance(value, dict):
        return {}
    current=value
    while isinstance(current.get("error"), dict) and len(current) == 1:
        current=current.get("error")
    return current

def as_int(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        s=value.strip()
        if s.isdigit():
            return int(s)
        return None
    if isinstance(value, dict):
        for key in ("number", "int", "value", "code", "string"):
            if key in value:
                out=as_int(value.get(key))
                if out is not None:
                    return out
    return None

err=as_dict(payload.get("error"))
code=as_int(err.get("code"))
user_info=as_dict(err.get("userInfo"))
under=as_dict(user_info.get("NSUnderlyingError"))
stack=[]
if err:
    stack.append(json.dumps(err))
if under:
    stack.append(json.dumps(under))

text=" ".join(stack).lower()

if code == 10002:
    print("yes")
elif "profile has not been explicitly trusted" in text or "requestdenied" in text or "invalid code signature" in text or "\"security\"" in text:
    print("yes")
else:
    print("no")
PY
)"

  [[ "$verdict" == "yes" ]]
}

validate_entitlements_alignment() {
  local app_entitlements
  local keyboard_entitlements
  local app_profile
  local keyboard_profile

  app_entitlements="$(mktemp)"
  keyboard_entitlements="$(mktemp)"
  app_profile="$(mktemp)"
  keyboard_profile="$(mktemp)"

  if ! codesign -d --entitlements :- "$APP_PATH" >"$app_entitlements" 2>/dev/null; then
    echo "Warning: failed to read signed entitlements for app target."
    rm -f "$app_entitlements" "$keyboard_entitlements" "$app_profile" "$keyboard_profile"
    return 1
  fi
  if ! codesign -d --entitlements :- "$KEYBOARD_PATH" >"$keyboard_entitlements" 2>/dev/null; then
    echo "Warning: failed to read signed entitlements for keyboard extension."
    rm -f "$app_entitlements" "$keyboard_entitlements" "$app_profile" "$keyboard_profile"
    return 1
  fi
  if ! security cms -D -i "$APP_PATH/embedded.mobileprovision" >"$app_profile"; then
    echo "Warning: failed to decode embedded provisioning profile for app target."
    rm -f "$app_entitlements" "$keyboard_entitlements" "$app_profile" "$keyboard_profile"
    return 1
  fi
  if ! security cms -D -i "$KEYBOARD_PATH/embedded.mobileprovision" >"$keyboard_profile"; then
    echo "Warning: failed to decode embedded provisioning profile for keyboard extension."
    rm -f "$app_entitlements" "$keyboard_entitlements" "$app_profile" "$keyboard_profile"
    return 1
  fi

  local app_signed_group
  local app_profile_group
  local keyboard_signed_group
  local keyboard_profile_group

  app_signed_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$app_entitlements" 2>/dev/null || true)"
  app_profile_group="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups:0' "$app_profile" 2>/dev/null || true)"
  keyboard_signed_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$keyboard_entitlements" 2>/dev/null || true)"
  keyboard_profile_group="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups:0' "$keyboard_profile" 2>/dev/null || true)"

  local app_id
  local keyboard_id
  app_id="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$app_entitlements" 2>/dev/null || true)"
  keyboard_id="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$keyboard_entitlements" 2>/dev/null || true)"

  rm -f "$app_entitlements" "$keyboard_entitlements" "$app_profile" "$keyboard_profile"

  echo "Entitlements summary:"
  echo "- App application-identifier: ${app_id:-<missing>}"
  echo "- Keyboard application-identifier: ${keyboard_id:-<missing>}"
  echo "- App AppGroup (signed/profile): ${app_signed_group:-<missing>} / ${app_profile_group:-<missing>}"
  echo "- Keyboard AppGroup (signed/profile): ${keyboard_signed_group:-<missing>} / ${keyboard_profile_group:-<missing>}"

  if [[ "$app_signed_group" != "$app_profile_group" || "$keyboard_signed_group" != "$keyboard_profile_group" ]]; then
    cat <<'EOF'
Warning: signed entitlements and provisioning profile entitlements are not aligned.
Check Signing & Capabilities for both VoiceInputiOS and VoiceInputKeyboard targets.
EOF
    return 1
  fi

  if [[ "$app_signed_group" != "$EXPECTED_APP_GROUP_ID" || "$keyboard_signed_group" != "$EXPECTED_APP_GROUP_ID" ]]; then
    cat <<EOF
Warning: unexpected App Group detected. Expected: $EXPECTED_APP_GROUP_ID
Regenerate project and re-check target capabilities.
EOF
    return 1
  fi

  return 0
}

resolve_team_id() {
  local from_build_settings
  from_build_settings="$(xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputiOS -showBuildSettings 2>/dev/null \
    | sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = //p' \
    | sed '/^[[:space:]]*$/d' \
    | head -n 1)"
  if [[ -n "$from_build_settings" ]]; then
    echo "$from_build_settings"
    return
  fi

  if [[ -f "$APP_PATH/embedded.mobileprovision" ]]; then
    local existing_profile
    existing_profile="$(mktemp)"
    if security cms -D -i "$APP_PATH/embedded.mobileprovision" >"$existing_profile" 2>/dev/null; then
      local from_existing_profile
      from_existing_profile="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$existing_profile" 2>/dev/null || true)"
      rm -f "$existing_profile"
      if [[ -n "$from_existing_profile" ]]; then
        echo "$from_existing_profile"
        return
      fi
    fi
    rm -f "$existing_profile"
  fi

  local from_identity
  from_identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' \
    | head -n 1)"
  if [[ -n "$from_identity" ]]; then
    echo "$from_identity"
    return
  fi
}

if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(resolve_team_id || true)"
fi

if [[ -z "$TEAM_ID" ]]; then
  cat <<'EOF'
No DEVELOPMENT_TEAM could be resolved.

Do this once in Xcode:
1. Xcode > Settings > Accounts: sign in with Apple ID.
2. Open VoiceInputMobile.xcodeproj
3. Target VoiceInputiOS > Signing & Capabilities > Team 선택
4. Target VoiceInputKeyboard > Signing & Capabilities > Team 동일하게 선택

Then re-run:
  ./Scripts/run-ios-device-verification.sh <DEVICE_ID_OR_NAME>
EOF
  exit 1
fi

echo "[0/5] Checking device readiness"
if ! check_device_readiness; then
  echo
  print_device_state
  exit 1
fi

echo "[1/5] Generating iOS project"
./Scripts/generate-xcode-project.sh

echo "[2/5] Building signed iOS app for physical device"
build_log="$(mktemp)"
if ! xcodebuild -project VoiceInputMobile.xcodeproj \
  -scheme VoiceInputiOS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build >"$build_log" 2>&1
then
  cat "$build_log"
  if grep -q "No Account for Team" "$build_log"; then
    print_signing_guidance "$TEAM_ID"
  elif grep -q "No profiles for" "$build_log"; then
    cat <<'EOF'

Provisioning profiles are missing for one or more bundle identifiers.
Confirm both targets are signed with the same Team in Xcode and retry.
EOF
  fi
  rm -f "$build_log"
  exit 1
fi
cat "$build_log"
rm -f "$build_log"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app not found: $APP_PATH"
  exit 1
fi

echo "[3/5] Validating signed entitlements"
if ! validate_entitlements_alignment; then
  cat <<'EOF'
Entitlements validation failed. Resolve signing/capabilities mismatch before install/launch.
EOF
  exit 1
fi

echo "[4/5] Installing app on device: $DEVICE_ID"
if ! check_device_readiness; then
  echo
  print_device_state
  exit 1
fi
print_device_state
xcrun devicectl device uninstall app --device "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
install_status=0
run_with_timeout 600 xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" || install_status=$?
if [[ $install_status -ne 0 ]]; then
  if [[ $install_status -eq 142 ]]; then
    cat <<'EOF'

Install timed out waiting for device-side approval/readiness.
On iPhone: unlock, keep screen awake, and approve any "Install from Developer" prompts, then retry.
EOF
  fi
  exit "$install_status"
fi

echo "[5/5] Launching app (voiceinput://open)"
if ! check_device_readiness; then
  echo
  print_device_state
  exit 1
fi
print_device_state
launch_log="$(mktemp)"
launch_json="$(mktemp)"
if ! xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --activate \
  --terminate-existing \
  --payload-url 'voiceinput://open' \
  "$APP_BUNDLE_ID" \
  --json-output "$launch_json" >"$launch_log" 2>&1
then
  cat "$launch_log"
  show_launch_json_diagnostics "$launch_json"
  echo
  echo "Retrying plain app launch without payload URL..."
  plain_launch_log="$(mktemp)"
  plain_launch_json="$(mktemp)"
  if xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --activate \
    --terminate-existing \
    "$APP_BUNDLE_ID" \
    --json-output "$plain_launch_json" >"$plain_launch_log" 2>&1
  then
    cat "$plain_launch_log"
    show_launch_json_diagnostics "$plain_launch_json"
    rm -f "$plain_launch_log" "$plain_launch_json" "$launch_log" "$launch_json"
    cat <<'EOF'

App launched without payload URL.
This indicates app signing/trust is OK, and the payload-url launch path needs separate validation.
EOF
    exit 0
  fi
  cat "$plain_launch_log"
  show_launch_json_diagnostics "$plain_launch_json"
  if is_trust_blocked "$launch_log" "$launch_json" || is_trust_blocked "$plain_launch_log" "$plain_launch_json"; then
    print_trust_guidance
  else
    cat <<'EOF'

Launch failed for an unknown reason. Re-run with:
  xcrun devicectl device process launch --device <DEVICE_ID_OR_NAME> --activate --terminate-existing --payload-url 'voiceinput://open' com.voiceinput.ios
EOF
  fi
  rm -f "$plain_launch_log" "$plain_launch_json" "$launch_log" "$launch_json"
  exit 1
fi

cat "$launch_log"
show_launch_json_diagnostics "$launch_json"
rm -f "$launch_log" "$launch_json"

echo "Device verification bootstrap completed."
echo "Next: run manual keyboard validation checklist in docs/plans/2026-03-03-iphone-mvp-release-checklist.md."
