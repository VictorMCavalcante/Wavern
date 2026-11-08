#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/wavern-browser-tab-checks"
swiftc -Onone -swift-version 5 -target arm64-apple-macos14.4 -sdk "$(xcrun --show-sdk-path)" \
  Sources/Wavern/BrowserTabStore.swift Sources/Wavern/SettingsStore.swift Tests/BrowserTabChecks/main.swift -o "$out"
"$out"
