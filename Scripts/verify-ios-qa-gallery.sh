#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAPTURE_SCRIPT="$ROOT_DIR/Scripts/capture-ios-qa-gallery.sh"
PIXEL_HASH_SCRIPT="$ROOT_DIR/Scripts/hash-png-pixels.swift"
DESCRIBE_ENV_SCRIPT="$ROOT_DIR/Scripts/describe-ios-qa-environment.sh"
PREFLIGHT_ENV_SCRIPT="$ROOT_DIR/Scripts/preflight-ios-qa-environment.sh"
BASELINE_DIR="$ROOT_DIR/docs/qa-baselines/ios"
CAPTURE_DIR=""
DERIVED_DATA=""
SIMULATOR_NAME="iPhone 17"
SIMULATOR_RUNTIME="${VOICEINPUT_IOS_SIMULATOR_RUNTIME:-}"
SKIP_BUILD=0
RECORD=0
KEEP_CAPTURE=0
MANIFEST_NAME="manifest.sha256"
ENVIRONMENT_NAME="environment.env"
IGNORE_BOTTOM_PIXELS="${VOICEINPUT_IOS_QA_IGNORE_BOTTOM_PIXELS:-40}"
CREATED_CAPTURE_DIR=0
ALLOW_FALLBACK=0
SIMULATOR_SET=0
RUNTIME_SET=0

EXPECTED_FILES=(
  "qa-gallery-home.png"
  "qa-keyboard-gallery.png"
  "qa-host-idleNoSavedResult.png"
  "qa-host-savedResultReady.png"
  "qa-host-unsavedDraftEdits.png"
  "qa-host-suggestedFixes.png"
  "qa-host-recording.png"
  "qa-host-transcribing.png"
)

usage() {
  cat <<'EOF'
Usage: ./Scripts/verify-ios-qa-gallery.sh [options]

Options:
  --record               Refresh checked-in baseline snapshots from a fresh capture
  --simulator <name>     Simulator device name (default: iPhone 17)
  --runtime <id>         Exact simulator runtime identifier
  --allow-fallback       Use another available iPhone simulator if the preferred one is unavailable
  --baseline-dir <dir>   Baseline directory (default: docs/qa-baselines/ios)
  --capture-dir <dir>    Temporary capture directory (default: mktemp)
  --derived-data <dir>   DerivedData path passed through to capture script
  --skip-build           Reuse an existing Debug simulator build
  --keep-capture         Keep the temporary capture directory after verification
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --record)
      RECORD=1
      shift
      ;;
    --simulator)
      SIMULATOR_NAME="${2:?missing simulator name}"
      SIMULATOR_SET=1
      shift 2
      ;;
    --runtime)
      SIMULATOR_RUNTIME="${2:?missing runtime identifier}"
      RUNTIME_SET=1
      shift 2
      ;;
    --allow-fallback)
      ALLOW_FALLBACK=1
      shift
      ;;
    --baseline-dir)
      BASELINE_DIR="${2:?missing baseline dir}"
      shift 2
      ;;
    --capture-dir)
      CAPTURE_DIR="${2:?missing capture dir}"
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
    --keep-capture)
      KEEP_CAPTURE=1
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

BASELINE_ENV="$BASELINE_DIR/$ENVIRONMENT_NAME"
if [[ $RECORD -eq 0 && -f "$BASELINE_ENV" ]]; then
  set -a
  source "$BASELINE_ENV"
  set +a

  if [[ -n "${VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME:-}" ]]; then
    if [[ $SIMULATOR_SET -eq 1 && "$SIMULATOR_NAME" != "$VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME" ]]; then
      echo "Baseline-locked verify flow rejects simulator override '$SIMULATOR_NAME'." >&2
      echo "Expected simulator from $BASELINE_ENV: $VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME" >&2
      exit 1
    fi
    SIMULATOR_NAME="$VOICEINPUT_IOS_BASELINE_SIMULATOR_NAME"
  fi

  if [[ -n "${VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER:-}" ]]; then
    if [[ $RUNTIME_SET -eq 1 && "$SIMULATOR_RUNTIME" != "$VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER" ]]; then
      echo "Baseline-locked verify flow rejects runtime override '$SIMULATOR_RUNTIME'." >&2
      echo "Expected runtime from $BASELINE_ENV: $VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER" >&2
      exit 1
    fi
    SIMULATOR_RUNTIME="$VOICEINPUT_IOS_BASELINE_RUNTIME_IDENTIFIER"
  fi

  if [[ $ALLOW_FALLBACK -eq 1 && "${VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK:-0}" != "1" ]]; then
    echo "Baseline-locked verify flow rejects --allow-fallback." >&2
    echo "Expected fallback policy from $BASELINE_ENV: ${VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK:-0}" >&2
    exit 1
  fi

  ALLOW_FALLBACK="${VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK:-0}"
  IGNORE_BOTTOM_PIXELS="${VOICEINPUT_IOS_BASELINE_IGNORE_BOTTOM_PIXELS:-$IGNORE_BOTTOM_PIXELS}"
fi

if [[ -z "$CAPTURE_DIR" ]]; then
  CAPTURE_DIR="$(mktemp -d /tmp/voiceinput-qa-verify.XXXXXX)"
  CREATED_CAPTURE_DIR=1
fi

cleanup() {
  if [[ $CREATED_CAPTURE_DIR -eq 1 && $KEEP_CAPTURE -eq 0 ]]; then
    rm -rf "$CAPTURE_DIR"
  fi
}
trap cleanup EXIT

PIXEL_HASH_ARGS=()
if [[ "$IGNORE_BOTTOM_PIXELS" != "0" ]]; then
  PIXEL_HASH_ARGS+=(--ignore-bottom "$IGNORE_BOTTOM_PIXELS")
fi

hash_manifest() {
  local dir="$1"
  local paths=()

  for file in "${EXPECTED_FILES[@]}"; do
    paths+=("$dir/$file")
  done

  "$PIXEL_HASH_SCRIPT" "${PIXEL_HASH_ARGS[@]}" "${paths[@]}"
}

compare_files() {
  local baseline_file="$1"
  local capture_file="$2"

  local baseline_hash
  local capture_hash
  baseline_hash="$("$PIXEL_HASH_SCRIPT" "${PIXEL_HASH_ARGS[@]}" "$baseline_file" | awk '{print $1}')"
  capture_hash="$("$PIXEL_HASH_SCRIPT" "${PIXEL_HASH_ARGS[@]}" "$capture_file" | awk '{print $1}')"

  if [[ "$baseline_hash" != "$capture_hash" ]]; then
    echo "Mismatch: $(basename "$baseline_file")" >&2
    echo "  baseline: $baseline_hash" >&2
    echo "  capture:  $capture_hash" >&2
    return 1
  fi

  return 0
}

capture_args=(
  --simulator "$SIMULATOR_NAME"
  --out "$CAPTURE_DIR"
)

if [[ -n "$SIMULATOR_RUNTIME" ]]; then
  capture_args+=(--runtime "$SIMULATOR_RUNTIME")
fi

if [[ $ALLOW_FALLBACK -eq 1 ]]; then
  capture_args+=(--allow-fallback)
fi

if [[ -n "$DERIVED_DATA" ]]; then
  capture_args+=(--derived-data "$DERIVED_DATA")
fi

if [[ $SKIP_BUILD -eq 1 ]]; then
  capture_args+=(--skip-build)
fi

if [[ $RECORD -eq 0 && -f "$BASELINE_ENV" ]]; then
  echo "[1/4] Verifying QA environment"
  "$PREFLIGHT_ENV_SCRIPT" --baseline "$BASELINE_ENV"
  capture_step="[2/4]"
  verify_step="[3/4]"
  done_step="[4/4]"
else
  capture_step="[1/3]"
  verify_step="[2/3]"
  done_step="[3/3]"
fi

echo "$capture_step Capturing QA screenshots"
"$CAPTURE_SCRIPT" "${capture_args[@]}"

if [[ $RECORD -eq 1 ]]; then
  echo "$verify_step Recording baseline snapshots"
  mkdir -p "$BASELINE_DIR"
  rm -f "$BASELINE_DIR"/*.png "$BASELINE_DIR/$MANIFEST_NAME" "$BASELINE_ENV"

  for file in "${EXPECTED_FILES[@]}"; do
    cp "$CAPTURE_DIR/$file" "$BASELINE_DIR/$file"
  done

  describe_args=(--simulator "$SIMULATOR_NAME" --env)
  if [[ -n "$SIMULATOR_RUNTIME" ]]; then
    describe_args+=(--runtime "$SIMULATOR_RUNTIME")
  fi
  if [[ $ALLOW_FALLBACK -eq 1 ]]; then
    describe_args+=(--allow-fallback)
  fi
  "$DESCRIBE_ENV_SCRIPT" "${describe_args[@]}" > "$BASELINE_ENV"
  printf 'VOICEINPUT_IOS_BASELINE_ALLOW_FALLBACK=%s\n' "$ALLOW_FALLBACK" >> "$BASELINE_ENV"
  printf 'VOICEINPUT_IOS_BASELINE_IGNORE_BOTTOM_PIXELS=%s\n' "$IGNORE_BOTTOM_PIXELS" >> "$BASELINE_ENV"

  hash_manifest "$BASELINE_DIR" > "$BASELINE_DIR/$MANIFEST_NAME"

  echo "$done_step Baseline written to $BASELINE_DIR"
  exit 0
fi

echo "$verify_step Verifying against baseline snapshots"
if [[ ! -d "$BASELINE_DIR" || ! -f "$BASELINE_DIR/$MANIFEST_NAME" ]]; then
  echo "Baseline not found. Run with --record first." >&2
  exit 1
fi

status=0
for file in "${EXPECTED_FILES[@]}"; do
  if [[ ! -f "$BASELINE_DIR/$file" ]]; then
    echo "Missing baseline file: $BASELINE_DIR/$file" >&2
    status=1
    continue
  fi

  if [[ ! -f "$CAPTURE_DIR/$file" ]]; then
    echo "Missing captured file: $CAPTURE_DIR/$file" >&2
    status=1
    continue
  fi

  if ! compare_files "$BASELINE_DIR/$file" "$CAPTURE_DIR/$file"; then
    status=1
  fi
done

capture_manifest="$(mktemp /tmp/voiceinput-qa-manifest.XXXXXX)"
hash_manifest "$CAPTURE_DIR" > "$capture_manifest"

if ! diff -u "$BASELINE_DIR/$MANIFEST_NAME" "$capture_manifest" >/dev/null; then
  echo "Manifest mismatch between baseline and fresh capture." >&2
  diff -u "$BASELINE_DIR/$MANIFEST_NAME" "$capture_manifest" || true
  status=1
fi

rm -f "$capture_manifest"

if [[ $status -ne 0 ]]; then
  echo "$done_step Snapshot verification failed" >&2
  exit 1
fi

echo "$done_step Snapshot verification passed"
