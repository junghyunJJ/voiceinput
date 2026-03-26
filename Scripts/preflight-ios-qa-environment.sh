#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_ENV="$ROOT_DIR/docs/qa-baselines/ios/environment.env"
DESCRIBE_SCRIPT="$ROOT_DIR/Scripts/describe-ios-qa-environment.sh"
PREFERRED_SIMULATOR=""
ALLOW_FALLBACK=""

usage() {
  cat <<'EOF'
Usage: ./Scripts/preflight-ios-qa-environment.sh [options]

Options:
  --baseline <path>      Baseline environment file (default: docs/qa-baselines/ios/environment.env)
  --simulator <name>     Override the preferred simulator name before resolution
  --allow-fallback       Override baseline policy and allow deterministic simulator fallback
  --no-fallback          Override baseline policy and disallow fallback
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline)
      BASELINE_ENV="${2:?missing baseline path}"
      shift 2
      ;;
    --simulator)
      PREFERRED_SIMULATOR="${2:?missing simulator name}"
      shift 2
      ;;
    --allow-fallback)
      ALLOW_FALLBACK="1"
      shift
      ;;
    --no-fallback)
      ALLOW_FALLBACK="0"
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

if [[ ! -f "$BASELINE_ENV" ]]; then
  echo "Baseline environment file not found: $BASELINE_ENV" >&2
  exit 1
fi

set -a
source "$BASELINE_ENV"
set +a

EXPECTED_XCODE_VERSION="${VOICEINPUT_IOS_BASELINE_XCODE_VERSION:-}"
EXPECTED_XCODE_BUILD="${VOICEINPUT_IOS_BASELINE_XCODE_BUILD:-}"
EXPECTED_SIMULATOR="${PREFERRED_SIMULATOR:-${VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME:-}}"
EXPECTED_RUNTIME="${VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER:-}"
EXPECTED_FALLBACK_POLICY="${ALLOW_FALLBACK:-${VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK:-0}}"

if [[ -z "$EXPECTED_XCODE_VERSION" || -z "$EXPECTED_XCODE_BUILD" || -z "$EXPECTED_SIMULATOR" || -z "$EXPECTED_RUNTIME" ]]; then
  echo "Baseline environment file is missing one of the required keys:" >&2
  echo "- VOICEINPUT_IOS_BASELINE_XCODE_VERSION" >&2
  echo "- VOICEINPUT_IOS_BASELINE_XCODE_BUILD" >&2
  echo "- VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME" >&2
  echo "- VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER" >&2
  exit 1
fi

describe_args=(--simulator "$EXPECTED_SIMULATOR" --runtime "$EXPECTED_RUNTIME" --env)
if [[ "$EXPECTED_FALLBACK_POLICY" == "1" ]]; then
  describe_args+=(--allow-fallback)
fi

CURRENT_ENV_OUTPUT="$("$DESCRIBE_SCRIPT" "${describe_args[@]}")"
eval "$CURRENT_ENV_OUTPUT"

ACTUAL_XCODE_VERSION="$VOICEINPUT_IOS_BASELINE_XCODE_VERSION"
ACTUAL_XCODE_BUILD="$VOICEINPUT_IOS_BASELINE_XCODE_BUILD"
ACTUAL_SIMULATOR="$VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME"
ACTUAL_RUNTIME="$VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER"

echo "Baseline environment: $BASELINE_ENV"
echo "Expected Xcode:    $EXPECTED_XCODE_VERSION ($EXPECTED_XCODE_BUILD)"
echo "Observed Xcode:    $ACTUAL_XCODE_VERSION ($ACTUAL_XCODE_BUILD)"
echo "Expected simulator: $EXPECTED_SIMULATOR"
echo "Observed simulator: $ACTUAL_SIMULATOR"
echo "Expected runtime:   $EXPECTED_RUNTIME"
echo "Observed runtime:   $ACTUAL_RUNTIME"
if [[ -n "${ImageOS:-}" || -n "${ImageVersion:-}" ]]; then
  echo "Runner image:       ${ImageOS:-unknown} ${ImageVersion:-unknown}"
fi

status=0

if [[ "$ACTUAL_XCODE_VERSION" != "$EXPECTED_XCODE_VERSION" ]]; then
  echo "Mismatch: expected Xcode version $EXPECTED_XCODE_VERSION, got $ACTUAL_XCODE_VERSION" >&2
  status=1
fi

if [[ "$ACTUAL_XCODE_BUILD" != "$EXPECTED_XCODE_BUILD" ]]; then
  echo "Mismatch: expected Xcode build $EXPECTED_XCODE_BUILD, got $ACTUAL_XCODE_BUILD" >&2
  status=1
fi

if [[ "$ACTUAL_SIMULATOR" != "$EXPECTED_SIMULATOR" ]]; then
  echo "Mismatch: expected simulator $EXPECTED_SIMULATOR, got $ACTUAL_SIMULATOR" >&2
  status=1
fi

if [[ "$ACTUAL_RUNTIME" != "$EXPECTED_RUNTIME" ]]; then
  echo "Mismatch: expected runtime $EXPECTED_RUNTIME, got $ACTUAL_RUNTIME" >&2
  status=1
fi

if [[ $status -ne 0 ]]; then
  echo "iOS QA environment preflight failed." >&2
  exit 1
fi

echo "iOS QA environment preflight passed."
