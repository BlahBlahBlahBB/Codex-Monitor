#!/bin/zsh
set -euo pipefail

# Creates a production appcast from already packaged Sparkle ZIP archives.
# It never creates, exports, prints, or stores a private key in the checkout.

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
archives_dir="${SPARKLE_ARCHIVES_DIR:?Set SPARKLE_ARCHIVES_DIR to the directory containing signed-update ZIP files.}"
download_url_prefix="${SPARKLE_DOWNLOAD_URL_PREFIX:?Set SPARKLE_DOWNLOAD_URL_PREFIX to the update asset directory URL.}"
tools_dir="${SPARKLE_TOOLS_DIR:-$project_root/.build/artifacts/sparkle/Sparkle/bin}"
appcast_name="${SPARKLE_APPCAST_NAME:-appcast.xml}"
allow_insecure_localhost="${SPARKLE_ALLOW_INSECURE_LOCALHOST:-0}"
key_role="${SPARKLE_ED25519_KEY_ROLE:-production}"
key_source="${SPARKLE_ED25519_KEY_SOURCE:-keychain}"
keychain_account_override="${SPARKLE_ED25519_KEYCHAIN_ACCOUNT:-}"
private_key_file="${SPARKLE_ED25519_PRIVATE_KEY_FILE:-}"
recovery_or_ci_authorization="${SPARKLE_ED25519_RECOVERY_OR_CI_AUTHORIZATION:-}"
expected_public_key_override="${SPARKLE_ED25519_EXPECTED_PUBLIC_KEY:-}"
release_tag="${SPARKLE_RELEASE_TAG:-}"
production_keychain_account="com.codexmonitor.sparkle.production.v1"
production_release_prefix="https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download"
# Full ZIPs preserve the app bundle's symlink layout and are the default
# release asset. Delta generation is opt-in only after a separate delta QA.
maximum_deltas="${SPARKLE_MAXIMUM_DELTAS:-0}"

fail() {
  print -u2 "ERROR: $1"
  exit 1
}

[[ -d "$archives_dir" ]] || fail "Missing archive directory: $archives_dir"
[[ "$maximum_deltas" == <-> ]] || fail "SPARKLE_MAXIMUM_DELTAS must contain only digits."
[[ "$allow_insecure_localhost" == "0" || "$allow_insecure_localhost" == "1" ]] || fail "SPARKLE_ALLOW_INSECURE_LOCALHOST must be 0 or 1."
[[ -x "$tools_dir/generate_appcast" ]] || fail "Missing Sparkle generate_appcast: $tools_dir/generate_appcast"
[[ -x "$tools_dir/sign_update" ]] || fail "Missing Sparkle sign_update: $tools_dir/sign_update"
[[ -x "$tools_dir/generate_keys" ]] || fail "Missing Sparkle generate_keys: $tools_dir/generate_keys"
xmllint_tool="$(xcrun --find xmllint 2>/dev/null || command -v xmllint)"
[[ -x "$xmllint_tool" ]] || fail "Missing xmllint required to verify generated appcast entries."

case "$key_role" in
  production)
    [[ -z "$keychain_account_override" || "$keychain_account_override" == "$production_keychain_account" ]] || fail "Production signing only permits Keychain account $production_keychain_account."
    keychain_account="$production_keychain_account"
    [[ "$allow_insecure_localhost" == "0" ]] || fail "Production appcast signing forbids SPARKLE_ALLOW_INSECURE_LOCALHOST."
    [[ -n "$release_tag" ]] || fail "Production appcast signing requires SPARKLE_RELEASE_TAG."
    expected_download_url_prefix="$production_release_prefix/$release_tag/"
    [[ "$download_url_prefix" == "$expected_download_url_prefix" ]] || fail "Production enclosure URL prefix must be $expected_download_url_prefix."
    ;;
  qa)
    [[ -n "$keychain_account_override" && "$keychain_account_override" == com.codexmonitor.sparkle.qa.* ]] || fail "QA signing requires an explicit com.codexmonitor.sparkle.qa.* Keychain account."
    keychain_account="$keychain_account_override"
    ;;
  *)
    fail "SPARKLE_ED25519_KEY_ROLE must be production or qa."
    ;;
esac

if [[ "$download_url_prefix" != https://* ]]; then
  if [[ "$key_role" != "qa" || "$allow_insecure_localhost" != "1" || "$download_url_prefix" != http://127.0.0.1:* ]]; then
    fail "Update assets must use HTTPS (localhost HTTP is only allowed for explicit QA signing)."
  fi
fi

case "$key_source" in
  keychain)
    [[ -z "$private_key_file" ]] || fail "SPARKLE_ED25519_PRIVATE_KEY_FILE requires explicit recovery-file mode."
    if ! expected_public_key="$("$tools_dir/generate_keys" --account "$keychain_account" -p)"; then
      fail "Required Keychain signing identity is unavailable: $keychain_account."
    fi
    [[ -n "$expected_public_key" ]] || fail "Required Keychain signing identity returned no public key."
    signing_args=(--account "$keychain_account")
    ;;
  recovery-file)
    [[ "$recovery_or_ci_authorization" == "approved" ]] || fail "Recovery-file mode requires SPARKLE_ED25519_RECOVERY_OR_CI_AUTHORIZATION=approved."
    [[ -n "$private_key_file" && -f "$private_key_file" ]] || fail "Recovery-file mode requires an existing private key file."
    [[ "$private_key_file" != "$project_root"/* ]] || fail "Private key must not reside in the repository."
    key_mode="$(stat -f '%Lp' "$private_key_file")"
    [[ "$key_mode" == 600 || "$key_mode" == 400 ]] || fail "Private key file must be mode 600 or 400; observed $key_mode."
    [[ -n "$expected_public_key_override" ]] || fail "Recovery-file mode requires SPARKLE_ED25519_EXPECTED_PUBLIC_KEY."
    expected_public_key="$expected_public_key_override"
    signing_args=(--ed-key-file "$private_key_file")
    ;;
  *)
    fail "SPARKLE_ED25519_KEY_SOURCE must be keychain or recovery-file."
    ;;
esac

validation_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codex-monitor-appcast-validation.XXXXXX")"
candidate_appcast="$archives_dir/.${appcast_name}.candidate.$$"
cleanup() {
  rm -rf "$validation_root"
  rm -f "$candidate_appcast"
}
trap cleanup EXIT

archive_public_key() {
  local archive="$1"
  local info_path
  local extracted_info
  local archive_root="$validation_root/${archive:t}"

  # ditto archives can include AppleDouble metadata under __MACOSX. Select
  # only the real bundle Info.plist, never its ._Info.plist sidecar.
  info_path="$(unzip -Z1 "$archive" | awk '$0 ~ /^[^/]+\.app\/Contents\/Info\.plist$/ { print; exit }')"
  [[ -n "$info_path" ]] || fail "Update archive does not contain an app Info.plist: ${archive:t}"
  mkdir -p "$archive_root"
  unzip -qq "$archive" "$info_path" -d "$archive_root"
  extracted_info="$archive_root/$info_path"
  plutil -extract SUPublicEDKey raw -o - "$extracted_info" 2>/dev/null || fail "Update archive is missing SUPublicEDKey: ${archive:t}"
}

archives=()
while IFS= read -r archive; do
  archives+=("$archive")
done < <(find "$archives_dir" -maxdepth 1 -type f -name '*.zip' -print | sort)
(( ${#archives} > 0 )) || fail "No ZIP update assets found in $archives_dir"

for archive in "${archives[@]}"; do
  [[ "$(archive_public_key "$archive")" == "$expected_public_key" ]] || fail "SUPublicEDKey does not match the selected signing identity: ${archive:t}"
done

"$tools_dir/generate_appcast" \
  "${signing_args[@]}" \
  --download-url-prefix "$download_url_prefix" \
  --maximum-versions 3 \
  --maximum-deltas "$maximum_deltas" \
  -o "$candidate_appcast" \
  "$archives_dir"

[[ -f "$candidate_appcast" ]] || fail "Sparkle did not create a candidate appcast."

# `sign_update --verify` validates every ZIP using the selected identity. An
# unsigned or public-key-mismatched archive has no edSignature and cannot move
# the candidate appcast into the publishable filename.
for archive in "${archives[@]}"; do
  archive_name="${archive:t}"
  signature="$("$xmllint_tool" --xpath "string(//*[local-name()='enclosure' and contains(@url, '$archive_name')]/@*[local-name()='edSignature'])" "$candidate_appcast")"
  enclosure_url="$("$xmllint_tool" --xpath "string(//*[local-name()='enclosure' and contains(@url, '$archive_name')]/@url)" "$candidate_appcast")"
  [[ -n "$signature" ]] || fail "No Ed25519 enclosure signature found for $archive_name"
  [[ "$enclosure_url" == "$download_url_prefix"* ]] || fail "Enclosure URL does not use the specified Release HTTPS prefix for $archive_name"
  "$tools_dir/sign_update" --verify "${signing_args[@]}" "$archive" "$signature"
done

mv "$candidate_appcast" "$archives_dir/$appcast_name"
print "APPCAST=$archives_dir/$appcast_name"
