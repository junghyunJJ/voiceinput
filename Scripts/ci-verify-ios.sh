#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/VoiceInputMobile.xcodeproj"
SCHEME="VoiceInputiOS"
BASELINE_ENV="${VOICEINPUT_IOS_BASELINE_ENV:-$ROOT_DIR/docs/qa-baselines/ios/environment.env}"
SIMULATOR_OVERRIDE_SET=0
RUNTIME_OVERRIDE_SET=0
FALLBACK_OVERRIDE_SET=0
if [[ -n "${VOICEINPUT_IOS_SIMULATOR+x}" ]]; then
  SIMULATOR_OVERRIDE_SET=1
fi
if [[ -n "${VOICEINPUT_IOS_SIMULATOR_RUNTIME+x}" ]]; then
  RUNTIME_OVERRIDE_SET=1
fi
if [[ -n "${VOICEINPUT_IOS_ALLOW_SIMULATOR_FALLBACK+x}" ]]; then
  FALLBACK_OVERRIDE_SET=1
fi
PREFERRED_SIMULATOR="${VOICEINPUT_IOS_SIMULATOR:-}"
REQUIRED_RUNTIME="${VOICEINPUT_IOS_SIMULATOR_RUNTIME:-}"
ALLOW_FALLBACK="${VOICEINPUT_IOS_ALLOW_SIMULATOR_FALLBACK:-0}"
ARTIFACT_ROOT="${VOICEINPUT_IOS_ARTIFACT_ROOT:-$ROOT_DIR/.artifacts/ios-ci}"
DERIVED_DATA="${VOICEINPUT_IOS_DERIVED_DATA:-$ARTIFACT_ROOT/derived-data}"
CAPTURE_DIR="${VOICEINPUT_IOS_QA_CAPTURE_DIR:-$ARTIFACT_ROOT/qa-capture}"
LOG_DIR="${VOICEINPUT_IOS_CI_LOG_DIR:-$ARTIFACT_ROOT/logs}"
RESOLVER="$ROOT_DIR/Scripts/resolve-ios-simulator.sh"
PREFLIGHT="$ROOT_DIR/Scripts/preflight-ios-qa-environment.sh"

mkdir -p "$ARTIFACT_ROOT" "$LOG_DIR"

if [[ -f "$BASELINE_ENV" ]]; then
  set -a
  source "$BASELINE_ENV"
  set +a

  if [[ -n "${VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME:-}" ]]; then
    if [[ $SIMULATOR_OVERRIDE_SET -eq 1 && -n "$PREFERRED_SIMULATOR" && "$PREFERRED_SIMULATOR" != "$VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME" ]]; then
      echo "Baseline-locked CI flow rejects simulator override '$PREFERRED_SIMULATOR'." >&2
      echo "Expected simulator from $BASELINE_ENV: $VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME" >&2
      exit 1
    fi
    PREFERRED_SIMULATOR="${VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME:-iPhone 17}"
  fi

  if [[ -n "${VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER:-}" ]]; then
    if [[ $RUNTIME_OVERRIDE_SET -eq 1 && -n "$REQUIRED_RUNTIME" && "$REQUIRED_RUNTIME" != "$VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER" ]]; then
      echo "Baseline-locked CI flow rejects runtime override '$REQUIRED_RUNTIME'." >&2
      echo "Expected runtime from $BASELINE_ENV: $VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER" >&2
      exit 1
    fi
    REQUIRED_RUNTIME="${VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER:-}"
  fi

  if [[ $FALLBACK_OVERRIDE_SET -eq 1 && "${VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK:-0}" != "$ALLOW_FALLBACK" ]]; then
    echo "Baseline-locked CI flow rejects fallback override '$ALLOW_FALLBACK'." >&2
    echo "Expected fallback policy from $BASELINE_ENV: ${VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK:-0}" >&2
    exit 1
  fi

  ALLOW_FALLBACK="${VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK:-0}"
fi

if [[ -z "$PREFERRED_SIMULATOR" ]]; then
  PREFERRED_SIMULATOR="iPhone 17"
fi

echo "[1/5] Verifying iOS QA environment"
"$PREFLIGHT" --baseline "$BASELINE_ENV" | tee "$LOG_DIR/preflight-ios-qa-environment.log"

resolver_args=(--preferred "$PREFERRED_SIMULATOR" --tsv)
if [[ -n "$REQUIRED_RUNTIME" ]]; then
  resolver_args+=(--runtime "$REQUIRED_RUNTIME")
fi
if [[ "$ALLOW_FALLBACK" == "1" ]]; then
  resolver_args+=(--allow-fallback)
fi

IFS=$'\t' read -r SIMULATOR_NAME SIMULATOR_UDID SIMULATOR_RUNTIME XCODE_DESTINATION < <("$RESOLVER" "${resolver_args[@]}")

echo "[2/5] Generating Xcode project"
"$ROOT_DIR/Scripts/generate-xcode-project.sh"

echo "[3/5] Using simulator: $SIMULATOR_NAME ($SIMULATOR_UDID)"
echo "      Runtime: $SIMULATOR_RUNTIME"
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null

echo "[4/5] Running iOS tests"
rm -rf "$DERIVED_DATA" "$CAPTURE_DIR"
mkdir -p "$CAPTURE_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$XCODE_DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  test | tee "$LOG_DIR/xcodebuild-ios-test.log"

echo "[5/5] Verifying QA snapshots"
"$ROOT_DIR/Scripts/verify-ios-qa-gallery.sh" \
  --simulator "$SIMULATOR_NAME" \
  --runtime "$SIMULATOR_RUNTIME" \
  --derived-data "$DERIVED_DATA" \
  --skip-build \
  --capture-dir "$CAPTURE_DIR"

echo
echo "iOS CI verification succeeded."
echo "Artifacts:"
echo "- DerivedData: $DERIVED_DATA"
echo "- QA capture:  $CAPTURE_DIR"
echo "- Logs:        $LOG_DIR"
