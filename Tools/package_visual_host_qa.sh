#!/bin/zsh
set -euo pipefail

# Local QA packaging only. This script creates a self-contained SwiftPM app
# bundle with its processed localization resource bundle, then ad-hoc signs it.
# It deliberately does not notarize, distribute, or modify Codex Desktop.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="${1:-Codex Monitor Visual Host Fix v3 QA}"
qa_root="$project_root/QA Builds"
app_path="$qa_root/$app_name.app"

cd "$project_root"
swift build
bin_path="$(swift build --show-bin-path)"
executable="$bin_path/CodexMonitorApp"
resource_bundle="$bin_path/CodexMonitorContracts_CodexMonitorApp.bundle"

[[ -x "$executable" ]] || { print -u2 "Missing executable: $executable"; exit 1; }
[[ -d "$resource_bundle" ]] || { print -u2 "Missing SwiftPM resource bundle: $resource_bundle"; exit 1; }
[[ ! -e "$app_path" ]] || { print -u2 "Refusing to overwrite existing QA app: $app_path"; exit 1; }

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$executable" "$app_path/Contents/MacOS/CodexMonitorApp"
ditto "$resource_bundle" "$app_path/Contents/Resources/$(basename "$resource_bundle")"

info_plist="$app_path/Contents/Info.plist"
plutil -create xml1 "$info_plist"
revision="${UI_BUILD_REVISION:-$(git rev-parse HEAD)}"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $app_name" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string CodexMonitorApp" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.codexmonitor.visualhostfixv3qa" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $app_name" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 3" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :UIBuildRevision string $revision" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :UIBuildTimestamp string $timestamp" "$info_plist"

codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
print "$app_path"
