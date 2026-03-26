#!/usr/bin/env bash
set -euo pipefail

PREFERRED_NAME="${VOICEINPUT_IOS_SIMULATOR:-iPhone 17}"
REQUIRED_RUNTIME="${VOICEINPUT_IOS_SIMULATOR_RUNTIME:-}"
ALLOW_FALLBACK=0
OUTPUT_MODE="tsv"

usage() {
  cat <<'EOF'
Usage: ./Scripts/resolve-ios-simulator.sh [options]

Options:
  --preferred <name>   Preferred simulator device name (default: VOICEINPUT_IOS_SIMULATOR or iPhone 17)
  --runtime <id>       Require an exact simulator runtime identifier (for example com.apple.CoreSimulator.SimRuntime.iOS-26-2)
  --allow-fallback     Pick a deterministic fallback iPhone simulator if the preferred one is unavailable
  --name-only          Print only the resolved simulator name
  --udid-only          Print only the resolved simulator UDID
  --runtime-only       Print only the resolved runtime identifier
  --destination        Print only the xcodebuild destination string
  --tsv                Print name, udid, runtime, destination separated by tabs (default)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preferred)
      PREFERRED_NAME="${2:?missing preferred simulator name}"
      shift 2
      ;;
    --runtime)
      REQUIRED_RUNTIME="${2:?missing runtime identifier}"
      shift 2
      ;;
    --allow-fallback)
      ALLOW_FALLBACK=1
      shift
      ;;
    --name-only)
      OUTPUT_MODE="name"
      shift
      ;;
    --udid-only)
      OUTPUT_MODE="udid"
      shift
      ;;
    --runtime-only)
      OUTPUT_MODE="runtime"
      shift
      ;;
    --destination)
      OUTPUT_MODE="destination"
      shift
      ;;
    --tsv)
      OUTPUT_MODE="tsv"
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

xcrun_json="$(xcrun simctl list devices available -j)"
SIMCTL_JSON="$xcrun_json" /usr/bin/python3 - "$PREFERRED_NAME" "$REQUIRED_RUNTIME" "$ALLOW_FALLBACK" "$OUTPUT_MODE" <<'PY'
import json
import os
import re
import sys

preferred_name = sys.argv[1]
required_runtime = sys.argv[2]
allow_fallback = sys.argv[3] == "1"
output_mode = sys.argv[4]

fallback_order = [
    "iPhone 17",
    "iPhone 16",
    "iPhone 15",
    "iPhone 14",
    "iPhone 13",
    "iPhone SE (3rd generation)",
    "iPhone 17 Pro",
    "iPhone 16 Pro",
    "iPhone 15 Pro",
    "iPhone 14 Pro",
]
fallback_rank = {name: index for index, name in enumerate(fallback_order)}

data = json.loads(os.environ["SIMCTL_JSON"])
candidates = []


def runtime_key(identifier: str) -> tuple[int, int, int]:
    match = re.search(r"iOS-(\d+)(?:-(\d+))?(?:-(\d+))?$", identifier)
    if not match:
        return (0, 0, 0)
    return tuple(int(part or 0) for part in match.groups())


for runtime_id, devices in data.get("devices", {}).items():
    if "SimRuntime.iOS" not in runtime_id:
        continue
    parsed_runtime = runtime_key(runtime_id)
    for device in devices:
        if not device.get("isAvailable"):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        candidates.append(
            {
                "name": name,
                "udid": device["udid"],
                "runtime": runtime_id,
                "runtime_key": parsed_runtime,
            }
        )

if not candidates:
    print("No available iPhone simulators found.", file=sys.stderr)
    sys.exit(1)

preferred_matches = [candidate for candidate in candidates if candidate["name"] == preferred_name]
if required_runtime:
    preferred_matches = [candidate for candidate in preferred_matches if candidate["runtime"] == required_runtime]

if preferred_matches:
    chosen = max(preferred_matches, key=lambda candidate: candidate["runtime_key"])
elif allow_fallback:
    if required_runtime:
        newest_candidates = [candidate for candidate in candidates if candidate["runtime"] == required_runtime]
    else:
        newest_runtime = max(candidate["runtime_key"] for candidate in candidates)
        newest_candidates = [candidate for candidate in candidates if candidate["runtime_key"] == newest_runtime]
    if not newest_candidates:
        available_runtimes = ", ".join(sorted({candidate["runtime"] for candidate in candidates}))
        print(
            f"Required runtime '{required_runtime}' is unavailable. Available iOS runtimes: {available_runtimes}",
            file=sys.stderr,
        )
        sys.exit(1)
    chosen = min(
        newest_candidates,
        key=lambda candidate: (fallback_rank.get(candidate["name"], 999), candidate["name"]),
    )
else:
    if required_runtime:
        available_for_runtime = sorted({candidate["name"] for candidate in candidates if candidate["runtime"] == required_runtime})
        if available_for_runtime:
            available = ", ".join(available_for_runtime)
            print(
                f"Preferred simulator '{preferred_name}' is unavailable on runtime '{required_runtime}'. Available iPhone simulators on that runtime: {available}",
                file=sys.stderr,
            )
        else:
            available_runtimes = ", ".join(sorted({candidate["runtime"] for candidate in candidates}))
            print(
                f"Required runtime '{required_runtime}' is unavailable. Available iOS runtimes: {available_runtimes}",
                file=sys.stderr,
            )
    else:
        available = ", ".join(sorted({candidate["name"] for candidate in candidates}))
        print(
            f"Preferred simulator '{preferred_name}' is unavailable. Available iPhone simulators: {available}",
            file=sys.stderr,
        )
    sys.exit(1)

destination = f"platform=iOS Simulator,id={chosen['udid']}"

if output_mode == "name":
    print(chosen["name"])
elif output_mode == "udid":
    print(chosen["udid"])
elif output_mode == "runtime":
    print(chosen["runtime"])
elif output_mode == "destination":
    print(destination)
else:
    print(f"{chosen['name']}\t{chosen['udid']}\t{chosen['runtime']}\t{destination}")
PY
