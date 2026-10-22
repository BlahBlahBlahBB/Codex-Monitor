#!/bin/zsh
set -euo pipefail

# Creates a production appcast from already packaged Sparkle ZIP archives.
# It never creates, exports, prints, or stores a private key in the checkout.

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
archives_dir="${SPARKLE_ARCHIVES_DIR:?Set SPARKLE_ARCHIVES_DIR to the directory containing signed-update ZIP files.}"
download_url_prefix="${SPARKLE_DOWNLOAD_URL_PREFIX:?Set SPARKLE_DOWNLOAD_URL_PREFIX to the update asset directory URL.}"
private_key_file="${SPARKLE_ED25519_PRIVATE_KEY_FILE:?Set SPARKLE_ED25519_PRIVATE_KEY_FILE outside this repository.}"
tools_dir="${SPARKLE_TOOLS_DIR:-$project_root/.build/artifacts/sparkle/Sparkle/bin}"
appcast_name="${SPARKLE_APPCAST_NAME:-appcast.xml}"
allow_insecure_localhost="${SPARKLE_ALLOW_INSECURE_LOCALHOST:-0}"
# Full ZIPs preserve the app bundle's symlink layout and are the default
# release asset. Delta generation is opt-in only after a separate delta QA.
maximum_deltas="${SPARKLE_MAXIMUM_DELTAS:-0}"

[[ -d "$archives_dir" ]] || { print -u2 "Missing archive directory: $archives_dir"; exit 1; }
[[ "$maximum_deltas" == <-> ]] || { print -u2 "SPARKLE_MAXIMUM_DELTAS must contain only digits."; exit 1; }
[[ -f "$private_key_file" ]] || { print -u2 "Missing private key file: $private_key_file"; exit 1; }
[[ "$private_key_file" != "$project_root"/* ]] || { print -u2 "Private key must not reside in the repository."; exit 1; }
if [[ "$download_url_prefix" != https://* ]]; then
  if [[ "$allow_insecure_localhost" != "1" || "$download_url_prefix" != http://127.0.0.1:* ]]; then
    print -u2 "Update assets must use HTTPS (localhost HTTP is only allowed with SPARKLE_ALLOW_INSECURE_LOCALHOST=1)."
    exit 1
  fi
fi
[[ -x "$tools_dir/generate_appcast" ]] || { print -u2 "Missing Sparkle generate_appcast: $tools_dir/generate_appcast"; exit 1; }
[[ -x "$tools_dir/sign_update" ]] || { print -u2 "Missing Sparkle sign_update: $tools_dir/sign_update"; exit 1; }
xmllint_tool="$(xcrun --find xmllint 2>/dev/null || command -v xmllint)"
[[ -x "$xmllint_tool" ]] || { print -u2 "Missing xmllint required to verify generated appcast entries."; exit 1; }

# Refuse group/world-readable exported-key files. A Keychain-backed operator
# may instead export to a mode-600 temporary file outside the checkout.
key_mode="$(stat -f '%Lp' "$private_key_file")"
[[ "$key_mode" == 600 || "$key_mode" == 400 ]] || {
  print -u2 "Private key file must be mode 600 or 400; observed $key_mode."
  exit 1
}

appcast_path="$archives_dir/$appcast_name"

"$tools_dir/generate_appcast" \
  --ed-key-file "$private_key_file" \
  --download-url-prefix "$download_url_prefix" \
  --maximum-versions 3 \
  --maximum-deltas "$maximum_deltas" \
  -o "$appcast_path" \
  "$archives_dir"

[[ -f "$appcast_path" ]] || { print -u2 "Sparkle did not create $appcast_path"; exit 1; }

# `sign_update --verify` validates an archive against its detached signature;
# it does not sign appcast XML. Verify every generated enclosure with the
# exact signature that generate_appcast placed in the XML index.
verified_archives=0
while IFS= read -r archive; do
  archive_name="${archive:t}"
  signature="$("$xmllint_tool" --xpath "string(//*[local-name()='enclosure' and contains(@url, '$archive_name')]/@*[local-name()='edSignature'])" "$appcast_path")"
  [[ -n "$signature" ]] || { print -u2 "No Ed25519 enclosure signature found for $archive_name"; exit 1; }
  "$tools_dir/sign_update" --verify --ed-key-file "$private_key_file" "$archive" "$signature"
  ((verified_archives += 1))
done < <(find "$archives_dir" -maxdepth 1 -type f -name '*.zip' -print | sort)

(( verified_archives > 0 )) || { print -u2 "No ZIP update assets found in $archives_dir"; exit 1; }

print "APPCAST=$appcast_path"
