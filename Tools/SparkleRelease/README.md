# Sparkle release signing and appcast procedure

This directory contains release tooling only. It does not contain an Ed25519
private key, a test key, an appcast, or a release asset.

## Key custody

1. After explicit release-lead approval, create the long-lived production
   identity with Sparkle 2.10.0's `generate_keys` in the fixed Keychain
   account `com.codexmonitor.sparkle.production.v1`.
   Record the resulting **public** key in the protected release configuration.
2. `generate_appcast.sh` is Keychain-first: production signing uses only the
   fixed `com.codexmonitor.sparkle.production.v1` account. It neither creates
   nor exports a key. A mode-600 external key file is available only when an
   explicitly authorized recovery/CI job selects `recovery-file` mode and
   supplies the expected public key; it is never the normal production path.
   Never place key material in Git, the app bundle, an appcast, a shell trace,
   a diagnostic archive, or command-line arguments.
3. The public key is supplied to packaging through
   `SPARKLE_PUBLIC_ED25519_KEY`; `Tools/package_release.sh` writes only that
   public key to `SUPublicEDKey` in the app's Info.plist.
4. Treat loss or suspected disclosure of the private key as a release-security
   incident. Rotate with a separately planned Sparkle key-transition release;
   do not silently replace a key in an existing update chain.

## Packaging an update archive

`Tools/package_release.sh` embeds Sparkle.framework, writes the Sparkle
Info.plist keys, signs all leaf code and enclosing bundles bottom-up, and emits
a `--keepParent` ZIP that preserves the `.app` bundle and symlinks.

```zsh
VERSION=1.0.14 BUILD=118 RELEASE_LABEL=RC1 \
SPARKLE_FEED_URL=https://updates.example.invalid/codex-monitor/appcast.xml \
SPARKLE_PUBLIC_ED25519_KEY='PUBLIC_KEY_ONLY' \
./Tools/package_release.sh
```

The script rejects non-HTTPS feeds unless a local-only validation explicitly
sets `SPARKLE_ALLOW_INSECURE_LOCALHOST=1` and uses `http://127.0.0.1/...`.
That escape hatch is forbidden for a published asset.

## Publishing plan

1. Run the release package script in the protected signing environment.
2. Copy only the produced ZIP and release notes to a clean, versioned staging
   directory outside the checkout. Do not mutate an already published ZIP.
3. Run `generate_appcast.sh` using Sparkle's official `generate_appcast` and
   `sign_update` tools. Production requires an exact GitHub Release HTTPS
   prefix for `SPARKLE_RELEASE_TAG`, matches every archive's `SUPublicEDKey`
   against the selected Keychain identity, verifies every generated enclosure
   signature, and only then promotes a candidate appcast to `appcast.xml`.
   A loopback URL is permitted only for an explicit QA signing role; it is
   forbidden for a published asset.
4. Upload the immutable ZIP and signed `appcast.xml` to the configured HTTPS
   origin. Publish the appcast only after the referenced ZIP is available.
5. Fetch the public HTTPS appcast from a clean user account, verify the ZIP
   checksum, inspect the Ed25519 signature, and run the user-level Sparkle
   upgrade QA before creating a GitHub Release.

GitHub Releases remain the manual-download/rollback channel. Sparkle appcasts
must reference immutable HTTPS ZIP assets and never infer a URL from an
untrusted release response.
