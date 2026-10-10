#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_test_dir="$(mktemp -d /private/tmp/rayneo-texture-tests.XXXXXX)"
trap 'rm -rf "$task_test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path /private/tmp/rayneo-swift-cache Tests/TextureTests.swift -o "$task_test_dir/texture-tests"
"$task_test_dir/texture-tests"
