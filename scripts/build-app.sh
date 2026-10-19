#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: scripts/build-app.sh [debug|release]" >&2
    exit 2
fi
cd "$project_root"
mkdir -p "$project_root/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
swift_options=()
if [[ "${PERSONALAI_DISABLE_SPM_SANDBOX:-0}" == "1" ]]; then
    swift_options+=(--disable-sandbox)
fi
swift build "${swift_options[@]}" --configuration "$configuration" --cache-path "$project_root/.build/cache" --config-path "$project_root/.build/config" --security-path "$project_root/.build/security" -Xswiftc -module-cache-path -Xswiftc "$project_root/.build/module-cache"
binary_dir="$(swift build --configuration "$configuration" --show-bin-path --cache-path "$project_root/.build/cache" --config-path "$project_root/.build/config" --security-path "$project_root/.build/security")"
app_dir="$project_root/build/PersonalAI.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/PersonalAI" "$app_dir/Contents/MacOS/PersonalAI.next"
mv -f "$app_dir/Contents/MacOS/PersonalAI.next" "$app_dir/Contents/MacOS/PersonalAI"
cp "$project_root/App/Info.plist" "$app_dir/Contents/Info.plist"
if [[ ! -f "$app_dir/Contents/Resources/AppIcon.icns" ]]; then
    swift -module-cache-path "$project_root/.build/module-cache" "$project_root/scripts/make-icon.swift" "$project_root/build/AppIcon.iconset"
    iconutil -c icns "$project_root/build/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
fi
signing_identity="${PERSONALAI_SIGNING_IDENTITY:--}"
# A stable developer identity preserves the app identity across updates; ad-hoc
# builds have a new cdhash and may require the user to renew Accessibility access.
if [[ "$signing_identity" == "-" ]]; then
    /usr/libexec/PlistBuddy -c "Add :PersonalAIAdHocBuild bool true" "$app_dir/Contents/Info.plist"
else
    /usr/libexec/PlistBuddy -c "Add :PersonalAIAdHocBuild bool false" "$app_dir/Contents/Info.plist"
fi
codesign --force --deep --sign "$signing_identity" --identifier com.fangjun.personalai "$app_dir"
echo "Built: $app_dir"
