#!/usr/bin/env bash
set -euo pipefail

PROJECT="VoiceInputMobile.xcodeproj"
SCHEME="VoiceInputiOSQA"
BUNDLE_ID="com.voiceinput.ios.qa"
READY_MARKER_FILENAME="voiceinput-qa-ready.txt"
READY_TIMEOUT_SECONDS="${VOICEINPUT_IOS_QA_READY_TIMEOUT_SECONDS:-15}"
POST_READY_SETTLE_SECONDS="${VOICEINPUT_IOS_QA_POST_READY_SETTLE_SECONDS:-0.25}"
SIMULATOR_NAME="${VOICEINPUT_IOS_SIMULATOR:-iPhone 17}"
SIMULATOR_RUNTIME="${VOICEINPUT_IOS_SIMULATOR_RUNTIME:-}"
OUTPUT_DIR="/tmp/voiceinput-qa"
DERIVED_DATA=""
SKIP_BUILD=0
ALLOW_FALLBACK=0
RESOLVER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-ios-simulator.sh"

HOST_STATES=(
  "idleNoSavedResult"
  "savedResultReady"
  "unsavedDraftEdits"
  "suggestedFixes"
  "recording"
  "transcribing"
)

usage() {
  cat <<'EOF'
Usage: ./Scripts/capture-ios-qa-gallery.sh [options]

Options:
  --simulator <name>     Simulator device name (default: iPhone 17)
  --runtime <id>         Exact simulator runtime identifier
  --allow-fallback       Use another available iPhone simulator if the preferred one is unavailable
  --out <dir>            Output directory for PNGs (default: /tmp/voiceinput-qa)
  --derived-data <dir>   Custom derived data path
  --skip-build           Reuse existing Debug simulator build
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --simulator)
      SIMULATOR_NAME="${2:?missing simulator name}"
      shift 2
      ;;
    --runtime)
      SIMULATOR_RUNTIME="${2:?missing runtime identifier}"
      shift 2
      ;;
    --allow-fallback)
      ALLOW_FALLBACK=1
      shift
      ;;
    --out)
      OUTPUT_DIR="${2:?missing output dir}"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA="${2:?missing derived data path}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$DERIVED_DATA" ]]; then
  DERIVED_DATA="$OUTPUT_DIR/derived-data"
fi

mkdir -p "$OUTPUT_DIR"

if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  echo "[1/5] Generating Xcode project"
  ./Scripts/generate-xcode-project.sh
fi

if [[ $SKIP_BUILD -eq 0 ]]; then
  echo "[1/5] Regenerating Xcode project"
  ./Scripts/generate-xcode-project.sh
fi

resolver_args=(--preferred "$SIMULATOR_NAME" --tsv)
if [[ -n "$SIMULATOR_RUNTIME" ]]; then
  resolver_args+=(--runtime "$SIMULATOR_RUNTIME")
fi
if [[ $ALLOW_FALLBACK -eq 1 ]]; then
  resolver_args+=(--allow-fallback)
fi

IFS=$'\t' read -r SIMULATOR_NAME UDID SIMULATOR_RUNTIME XCODE_DESTINATION < <("$RESOLVER" "${resolver_args[@]}")

echo "[2/5] Booting simulator: $SIMULATOR_NAME ($UDID)"
echo "      Runtime: $SIMULATOR_RUNTIME"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

if xcrun simctl status_bar "$UDID" override \
  --time "10:13" \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100 >/dev/null 2>&1; then
  SHOULD_CLEAR_STATUS_BAR=1
else
  SHOULD_CLEAR_STATUS_BAR=0
fi

cleanup() {
  if [[ "${SHOULD_CLEAR_STATUS_BAR:-0}" -eq 1 ]]; then
    xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ $SKIP_BUILD -eq 0 ]]; then
  echo "[3/5] Building debug simulator app"
  rm -rf "$DERIVED_DATA"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$XCODE_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build >/dev/null
else
  echo "[3/5] Skipping build"
fi

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/VoiceInputiOSQA.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Debug simulator app not found at: $APP_PATH" >&2
  echo "Re-run without --skip-build or pass a matching --derived-data path." >&2
  exit 1
fi

echo "[4/5] Installing app"
xcrun simctl install "$UDID" "$APP_PATH" >/dev/null

APP_DATA_CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
if [[ -z "$APP_DATA_CONTAINER" || ! -d "$APP_DATA_CONTAINER" ]]; then
  echo "Unable to resolve app data container for $BUNDLE_ID on simulator $UDID." >&2
  exit 1
fi

READY_MARKER_PATH="$APP_DATA_CONTAINER/Library/Caches/$READY_MARKER_FILENAME"

clear_ready_marker() {
  rm -f "$READY_MARKER_PATH"
}

wait_for_ready_signal() {
  local expected_token="$1"
  local expected_screen="$2"
  local deadline=$((SECONDS + READY_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if [[ -f "$READY_MARKER_PATH" ]]; then
      local observed_payload
      observed_payload="$(<"$READY_MARKER_PATH")"
      observed_payload="${observed_payload%$'\n'}"
      if [[ "$observed_payload" == "$expected_token"$'\t'"$expected_screen" ]]; then
        return 0
      fi
    fi

    sleep 0.1
  done

  echo "Timed out waiting for QA ready signal." >&2
  echo "Expected token:  $expected_token" >&2
  echo "Expected screen: $expected_screen" >&2
  echo "Marker path:     $READY_MARKER_PATH" >&2
  if [[ -f "$READY_MARKER_PATH" ]]; then
    echo "Observed marker: $(tr -d '\n' < "$READY_MARKER_PATH")" >&2
  else
    echo "Observed marker: <missing>" >&2
  fi
  return 1
}

launch_and_capture() {
  local filename="$1"
  local expected_screen="$2"
  shift
  shift
  local ready_token
  ready_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  clear_ready_marker
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" --qa-ready-token "$ready_token" >/dev/null
  wait_for_ready_signal "$ready_token" "$expected_screen"
  # The app-side ready marker can arrive a fraction of a second before
  # simulator-managed chrome fully settles, so give capture a brief buffer.
  sleep "$POST_READY_SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot "$OUTPUT_DIR/$filename" >/dev/null
  echo "Captured $OUTPUT_DIR/$filename"
}

echo "[5/5] Capturing QA screenshots"
launch_and_capture "qa-gallery-home.png" "gallery-home" --qa-gallery
launch_and_capture "qa-keyboard-gallery.png" "keyboard-gallery" --qa-keyboard-gallery

for state in "${HOST_STATES[@]}"; do
  launch_and_capture "qa-host-${state}.png" "host-${state}" --qa-host-state "$state"
done

echo
echo "QA screenshots saved to: $OUTPUT_DIR"
