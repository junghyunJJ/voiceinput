#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen"
  exit 1
fi

xcodegen generate --spec project.yml
echo "Generated VoiceInputMobile.xcodeproj"
