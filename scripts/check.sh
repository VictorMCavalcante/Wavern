#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/wavern-checks"
swiftc -Onone -swift-version 5 -target arm64-apple-macos14.4 \
  -sdk "$(xcrun --show-sdk-path)" \
  Sources/Wavern/TapHealth.swift Sources/Wavern/AudioMix.swift Sources/Wavern/SettingsStore.swift Tests/LogicChecks/main.swift -o "$out"
"$out"
