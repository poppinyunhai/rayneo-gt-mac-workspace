#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
task_sdk_path="$(xcrun --show-sdk-path)"
mkdir -p build/RayNeoWorkspace.app/Contents/MacOS
xcrun swiftc -sdk "$task_sdk_path" -module-cache-path /private/tmp/rayneo-swift-cache -import-objc-header Sources/VirtualDisplayBridge.h Sources/WorkspaceDemo.swift -o build/WorkspaceDemo
cp build/WorkspaceDemo build/RayNeoWorkspace.app/Contents/MacOS/RayNeoWorkspace
cat > build/RayNeoWorkspace.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RayNeoWorkspace</string>
<key>CFBundleIdentifier</key><string>local.rayneo.workspace.demo</string>
<key>CFBundleName</key><string>RayNeo Workspace</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/RayNeoWorkspace.app
