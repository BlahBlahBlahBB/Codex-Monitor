#!/bin/zsh
set -euo pipefail

# Preview-distribution packaging for Codex Monitor. This is intentionally
# independent of package_visual_host_qa.sh and never notarizes or publishes.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
product_name="Codex Monitor"
bundle_identifier="${BUNDLE_IDENTIFIER:-com.codexmonitor.app}"
marketing_version="${VERSION:-1.0.1}"
build_number="${BUILD:-101}"
preview_channel="Preview"
frozen_sdk_version="26.5"
icon_source="$project_root/icon/signal-capsule-mac.icns"
release_root="${RELEASE_ROOT:-$project_root/Release}"
app_bundle_name="${APP_BUNDLE_NAME:-$product_name.app}"
app_path="$release_root/$app_bundle_name"
dmg_name="Codex-Monitor-$marketing_version-Preview-macOS-arm64.dmg"
dmg_path="$release_root/$dmg_name"
dmg_staging="$release_root/dmg-root"

# SIGNING_IDENTITY is deliberately not resolved through the keychain. An empty
# value creates an explicitly local, ad-hoc rehearsal build; a release operator
# supplies a Developer ID Application identity when one is provisioned.
signing_identity="${SIGNING_IDENTITY:-${RELEASE_SIGNING_IDENTITY:-}}"

[[ "$marketing_version" =~ '^[0-9]+(\.[0-9]+){1,2}([-.][0-9A-Za-z.]+)?$' ]] || {
  print -u2 "VERSION must be a valid marketing version (for example, 1.0.1): $marketing_version"
  exit 1
}
[[ "$build_number" == <-> ]] || {
  print -u2 "BUILD must contain only digits: $build_number"
  exit 1
}
[[ -f "$icon_source" ]] || { print -u2 "Missing final icon: $icon_source"; exit 1; }

swift_tool="$(xcrun --find swift)"
swiftc_tool="$(xcrun --find swiftc)"
otool_tool="$(xcrun --find otool)"
install_name_tool="$(xcrun --find install_name_tool)"
hdiutil_tool="$(xcrun --find hdiutil)"
codesign_tool="$(xcrun --find codesign)"
toolchain_root="${swiftc_tool%/usr/bin/swiftc}"
sdk_path="$(xcrun --show-sdk-path)"
sdk_version="$(xcrun --show-sdk-version)"

# The frozen visual contract was verified with this exact macOS SDK. Refuse to
# create an artifact when the selected Xcode environment cannot provide it.
print "SWIFT_EXECUTABLE=$swift_tool"
"$swift_tool" --version
print "SDK_VERSION=$sdk_version"
print "SDK_PATH=$sdk_path"
[[ "$sdk_version" == "$frozen_sdk_version" ]] || {
  print -u2 "Refusing to package Codex Monitor with non-frozen SDK."
  print -u2 "Expected SDK $frozen_sdk_version; selected SDK is $sdk_version."
  exit 1
}

# SwiftPM's generated resource accessor includes its build directory as a
# fallback. Building outside the checkout prevents developer-specific workspace
# paths from becoming release-binary strings. It is safe to remove on exit.
scratch_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codex-monitor-release.XXXXXX")"
cleanup() {
  rm -rf "$scratch_root"
}
trap cleanup EXIT

cd "$project_root"
rm -rf "$release_root"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

# -debug-prefix-map covers compiler debug/source references. --scratch-path
# keeps SwiftPM-generated resource fallback paths out of the developer checkout.
build_args=(
  build
  --scratch-path "$scratch_root"
  -c release
  -Xswiftc -D -Xswiftc CODEX_MONITOR_RELEASE
  -Xswiftc -debug-prefix-map -Xswiftc "$project_root=/CodexMonitor"
)
SDKROOT="$sdk_path" "$swift_tool" "${build_args[@]}"
bin_path="$(SDKROOT="$sdk_path" "$swift_tool" "${build_args[@]}" --show-bin-path)"
executable="$bin_path/CodexMonitorApp"
resource_bundle="$bin_path/CodexMonitorContracts_CodexMonitorApp.bundle"

[[ -x "$executable" ]] || { print -u2 "Missing executable: $executable"; exit 1; }
[[ -d "$resource_bundle" ]] || { print -u2 "Missing SwiftPM resource bundle: $resource_bundle"; exit 1; }

cp "$executable" "$app_path/Contents/MacOS/CodexMonitorApp"
ditto "$resource_bundle" "$app_path/Contents/Resources/$(basename "$resource_bundle")"
cp "$icon_source" "$app_path/Contents/Resources/$(basename "$icon_source")"

app_executable="$app_path/Contents/MacOS/CodexMonitorApp"

# SwiftPM/Xcode currently adds a toolchain-local Swift rpath. It is useful only
# to the build host and makes the app nonportable. Remove that Mach-O load
# command structurally (not by binary-string replacement), preserving the
# system Swift and @loader_path rpaths used at runtime.
toolchain_rpaths=()
while IFS= read -r rpath; do
  [[ "$rpath" == "$toolchain_root"/* ]] && toolchain_rpaths+=("$rpath")
done < <("$otool_tool" -l "$app_executable" | awk '
  $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
  in_rpath && $1 == "path" { print $2; in_rpath = 0 }
')
for rpath in "${toolchain_rpaths[@]}"; do
  "$install_name_tool" -delete_rpath "$rpath" "$app_executable"
done

if "$otool_tool" -l "$app_executable" | awk '
  $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
  in_rpath && $1 == "path" { print $2; in_rpath = 0 }
' | grep -Eq '^/.*?/Toolchains/'; then
  print -u2 "Refusing to package an executable with an absolute Xcode toolchain LC_RPATH"
  exit 1
fi
if grep -aFq "$project_root" "$app_executable"; then
  print -u2 "Refusing to package an executable containing the checkout path"
  exit 1
fi

# Validate the final, post-RPATH-cleanup binary before signing or creating a
# DMG. The SDK marker is part of the frozen visual-release contract.
mach_platform="$("$otool_tool" -l "$app_executable" | awk '
  $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build_version = 1; next }
  in_build_version && $1 == "platform" { print $2; exit }
')"
mach_minos="$("$otool_tool" -l "$app_executable" | awk '
  $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build_version = 1; next }
  in_build_version && $1 == "minos" { print $2; exit }
')"
mach_sdk="$("$otool_tool" -l "$app_executable" | awk '
  $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build_version = 1; next }
  in_build_version && $1 == "sdk" { print $2; exit }
')"
print "FINAL_LC_BUILD_VERSION_PLATFORM=$mach_platform"
print "FINAL_LC_BUILD_VERSION_MINOS=$mach_minos"
print "FINAL_LC_BUILD_VERSION_SDK=$mach_sdk"
if [[ "$mach_platform" != "1" || "$mach_minos" != "13.0" || "$mach_sdk" != "$frozen_sdk_version" ]]; then
  print -u2 "Refusing to package Codex Monitor with non-frozen SDK."
  print -u2 "Expected SDK $frozen_sdk_version."
  print -u2 "Observed platform=$mach_platform minOS=$mach_minos sdk=$mach_sdk."
  exit 1
fi

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
/usr/libexec/PlistBuddy -c "Add :CodexMonitorReleaseChannel string $preview_channel" "$info_plist"

if [[ -n "$signing_identity" ]]; then
  signing_status="Developer ID signing requested"
else
  signing_identity="-"
  signing_status="UNSIGNED / AD-HOC LOCAL PREVIEW"
fi
/usr/libexec/PlistBuddy -c "Add :CodexMonitorSigningStatus string $signing_status" "$info_plist"

sign_code() {
  local code_path="$1"
  if [[ "$signing_identity" == "-" ]]; then
    "$codesign_tool" --force --sign - "$code_path"
  else
    "$codesign_tool" --force --options runtime --timestamp --sign "$signing_identity" "$code_path"
  fi
}

# Sign nested executable code first, then enclosing nested bundles, and the app
# last. Do not use --deep for signing; it is verification-only below.
main_executable="$app_path/Contents/MacOS/CodexMonitorApp"
while IFS= read -r nested_executable; do
  [[ "$nested_executable" == "$main_executable" ]] || sign_code "$nested_executable"
done < <(find "$app_path/Contents" -type f -perm -111 -print | sort)
while IFS= read -r nested_bundle; do
  sign_code "$nested_bundle"
done < <(find "$app_path/Contents" -depth -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.plugin' \) -print | sort)
sign_code "$main_executable"
sign_code "$app_path"
"$codesign_tool" --verify --deep --strict --verbose=2 "$app_path"

# The staging directory is deliberately limited to the app and Applications
# alias. hdiutil receives a stable volume name and output filename.
mkdir -p "$dmg_staging"
ditto "$app_path" "$dmg_staging/$product_name.app"
ln -s /Applications "$dmg_staging/Applications"
"$hdiutil_tool" create -quiet -ov -volname "$product_name $marketing_version $preview_channel" \
  -srcfolder "$dmg_staging" -format UDZO "$dmg_path"

print "APP=$app_path"
print "DMG=$dmg_path"
print "SIGNING_STATUS=$signing_status"
