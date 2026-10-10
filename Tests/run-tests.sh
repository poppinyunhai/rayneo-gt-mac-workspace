#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_test_dir="$(mktemp -d /private/tmp/rayneo-tests.XXXXXX)"
trap 'rm -rf "$task_test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path /private/tmp/rayneo-swift-cache Sources/WorkspaceSettings.swift Sources/GyroIntegrator.swift Sources/AsyncDeadline.swift Sources/StartupReadiness.swift Sources/LatestFrameMailbox.swift Tests/CoreTests.swift -o "$task_test_dir/core-tests"
"$task_test_dir/core-tests"
python3 Tests/lifecycle_tests.py
