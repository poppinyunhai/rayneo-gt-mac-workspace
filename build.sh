#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
task_sdk_path="$(xcrun --show-sdk-path)"
task_identity="${SIGNING_IDENTITY:-}"
if [[ -z "$task_identity" && -f .signing-identity ]]; then
    task_identity="$(cat .signing-identity)"
fi
if [[ -z "$task_identity" ]]; then
    if [[ "${ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then task_identity="-";
    else printf 'No stable signing identity configured. Run scripts/configure-signing.sh SHA1, or explicitly set ALLOW_ADHOC_SIGNING=1.\n' >&2; exit 1; fi
fi
if [[ "$task_identity" != "-" && ! "$task_identity" =~ ^[[:xdigit:]]{40}$ ]]; then
    printf 'SIGNING_IDENTITY must be a certificate SHA-1 fingerprint.\n' >&2; exit 1
fi
task_build_dir="${BUILD_DIR:-build/dev}"
task_app="$task_build_dir/RayNeoWorkspace-Dev.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
xcrun swiftc -sdk "$task_sdk_path" -module-cache-path /private/tmp/rayneo-swift-cache -import-objc-header Sources/VirtualDisplayBridge.h -target arm64-apple-macos26.0 -O Sources/*.swift -o "$task_build_dir/WorkspaceDemo"
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
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleShortVersionString</key><string>0.10.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
task_keychain_args=()
if [[ "$task_identity" != "-" && -f .signing-config/signing.keychain-db && -f .signing-config/password && -f .signing-config/identity.sha1 && "$task_identity" == "$(cat .signing-config/identity.sha1)" ]]; then
    task_keychain="$(pwd)/.signing-config/signing.keychain-db"
    security unlock-keychain -p "$(cat .signing-config/password)" "$task_keychain"
    task_keychain_args=(--keychain "$task_keychain")
fi
if [[ "$task_identity" == "-" ]]; then
    codesign --force --sign - "$task_app"
else
    codesign --force --sign "$task_identity" "${task_keychain_args[@]}" --requirements "=designated => identifier \"local.rayneo.workspace.dev\" and certificate leaf = H\"$task_identity\"" "$task_app"
fi
codesign --verify --deep --strict "$task_app"
printf 'Built: %s\n' "$task_app"
