#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift -module-cache-path /private/tmp/rayneo-swift-cache scripts/generate-icon.swift Assets
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
