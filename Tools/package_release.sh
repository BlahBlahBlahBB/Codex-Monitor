#!/bin/zsh
set -euo pipefail

# Production packaging for Codex Monitor. This intentionally leaves the
# visual-host QA workflow untouched in package_visual_host_qa.sh.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
product_name="Codex Monitor"
bundle_identifier="com.codexmonitor.app"
marketing_version="1.0.0"
build_number="1"
icon_source="$project_root/icon/signal-capsule-mac.icns"
release_root="$project_root/Release"
app_path="$release_root/$product_name.app"
zip_path="$release_root/Codex-Monitor-$marketing_version-macOS.zip"

[[ -f "$icon_source" ]] || { print -u2 "Missing final icon: $icon_source"; exit 1; }

cd "$project_root"
rm -rf "$release_root"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

# The explicit symbol removes QA-only diagnostic controls without changing the
# normal QA build configuration. -c release provides Swift's release settings.
swift build -c release -Xswiftc -D -Xswiftc CODEX_MONITOR_RELEASE
bin_path="$(swift build -c release -Xswiftc -D -Xswiftc CODEX_MONITOR_RELEASE --show-bin-path)"
executable="$bin_path/CodexMonitorApp"
resource_bundle="$bin_path/CodexMonitorContracts_CodexMonitorApp.bundle"

[[ -x "$executable" ]] || { print -u2 "Missing executable: $executable"; exit 1; }
[[ -d "$resource_bundle" ]] || { print -u2 "Missing SwiftPM resource bundle: $resource_bundle"; exit 1; }

cp "$executable" "$app_path/Contents/MacOS/CodexMonitorApp"
ditto "$resource_bundle" "$app_path/Contents/Resources/$(basename "$resource_bundle")"
cp "$icon_source" "$app_path/Contents/Resources/$(basename "$icon_source")"

info_plist="$app_path/Contents/Info.plist"
plutil -create xml1 "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $product_name" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string CodexMonitorApp" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $bundle_identifier" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string signal-capsule-mac" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $product_name" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $marketing_version" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$info_plist"

# A Developer ID identity can be supplied by CI or a release operator later.
# The current local candidate is correctly ad-hoc signed when none is present.
signing_identity="${RELEASE_SIGNING_IDENTITY:--}"
codesign --force --deep --sign "$signing_identity" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
print "APP=$app_path"
print "ZIP=$zip_path"
