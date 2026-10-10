#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
task_sdk_path="$(xcrun --show-sdk-path)"
task_build_dir="${BUILD_DIR:-build/dev}"
task_app="$task_build_dir/RayNeoWorkspace-Dev.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
xcrun swiftc -sdk "$task_sdk_path" -module-cache-path /private/tmp/rayneo-swift-cache -import-objc-header Sources/VirtualDisplayBridge.h Sources/WorkspaceDemo.swift -o "$task_build_dir/WorkspaceDemo"
cp "$task_build_dir/WorkspaceDemo" "$task_app/Contents/MacOS/RayNeoWorkspace"
cp Assets/AppIcon.icns "$task_app/Contents/Resources/AppIcon.icns"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RayNeoWorkspace</string>
<key>CFBundleIdentifier</key><string>local.rayneo.workspace.dev</string>
<key>CFBundleName</key><string>RayNeo Workspace Dev</string>
<key>CFBundleDisplayName</key><string>RayNeo Workspace Dev</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${SIGNING_IDENTITY:--}" "$task_app"
printf 'Built: %s\n' "$task_app"
