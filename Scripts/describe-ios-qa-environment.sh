#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT_DIR/Scripts/resolve-ios-simulator.sh"
SIMULATOR_NAME="${VOICEINPUT_IOS_SIMULATOR:-iPhone 17}"
SIMULATOR_RUNTIME="${VOICEINPUT_IOS_SIMULATOR_RUNTIME:-}"
ALLOW_FALLBACK=0
OUTPUT_MODE="env"

usage() {
  cat <<'EOF'
Usage: ./Scripts/describe-ios-qa-environment.sh [options]

Options:
  --simulator <name>     Simulator device name (default: VOICEINPUT_IOS_SIMULATOR or iPhone 17)
  --runtime <id>         Exact simulator runtime identifier to resolve
  --allow-fallback       Allow deterministic simulator fallback
  --pretty               Print a human-readable summary
  --env                  Print shell-style KEY=VALUE lines (default)
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
    --pretty)
      OUTPUT_MODE="pretty"
      shift
      ;;
    --env)
      OUTPUT_MODE="env"
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

XCODE_VERSION_LINE="$(xcodebuild -version | sed -n '1p')"
XCODE_BUILD_LINE="$(xcodebuild -version | sed -n '2p')"
XCODE_VERSION="${XCODE_VERSION_LINE#Xcode }"
XCODE_BUILD="${XCODE_BUILD_LINE#Build version }"

resolver_args=(--preferred "$SIMULATOR_NAME" --tsv)
if [[ -n "$SIMULATOR_RUNTIME" ]]; then
  resolver_args+=(--runtime "$SIMULATOR_RUNTIME")
fi
if [[ $ALLOW_FALLBACK -eq 1 ]]; then
  resolver_args+=(--allow-fallback)
fi

IFS=$'\t' read -r RESOLVED_NAME RESOLVED_UDID RESOLVED_RUNTIME RESOLVED_DESTINATION < <("$RESOLVER" "${resolver_args[@]}")

if [[ "$OUTPUT_MODE" == "pretty" ]]; then
  echo "Xcode: $XCODE_VERSION ($XCODE_BUILD)"
  echo "Simulator: $RESOLVED_NAME ($RESOLVED_UDID)"
  echo "Runtime: $RESOLVED_RUNTIME"
  echo "Destination: $RESOLVED_DESTINATION"
else
  printf 'VOICEINPUT_IOS_BASELINE_XCODE_VERSION=%q\n' "$XCODE_VERSION"
  printf 'VOICEINPUT_IOS_BASELINE_XCODE_BUILD=%q\n' "$XCODE_BUILD"
  printf 'VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME=%q\n' "$RESOLVED_NAME"
  printf 'VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER=%q\n' "$RESOLVED_RUNTIME"
fi
