# Sparkle 1.0.14 isolated integration report

## Scope and baseline

- Branch: `codex/sparkle-production-integration-20261022`, created from
  `origin/main` at `37c015ab01646798437796a1d973e5807f6381e4`.
- The two prior Sparkle reports were reviewed before this change. The
  free-signing A→B→C experiment demonstrated that the existing ad-hoc
  strategy works after one normal first-launch Gatekeeper approval, without
  Hardened Runtime or a Library Validation exemption.
- No production application, `main`, GitHub Release, tag, account, Codex
  Desktop, or Hooks were changed.

## Integrated design

`SparkleUpdateController` owns an `SPUStandardUpdaterController`. The normal
Settings update action invokes Sparkle; the old GitHub polling notifier is no
longer constructed or scheduled, so it cannot create a competing update
dialog. A separate **Manual Download** action opens the fixed official Releases
page, preserving the manual rollback/download route without querying or
trusting a release-provided URL.

`package_release.sh` pins Sparkle 2.10.0, embeds `Sparkle.framework`, and
copies the framework's `Updater.app`, Downloader XPC, and Installer XPC as
part of that framework. It signs executable leaves first, then enclosing XPCs,
Updater.app, framework, main executable, and app. The final verifier uses
`codesign --verify --deep --strict`; signing itself never uses `--deep`.

The host is unsandboxed. `SUEnableInstallerLauncherService` is intentionally
absent, matching both successful prior POCs; `SUEnableDownloaderService=true`
is present for the dockless host.

The normal default remains `codesign --force --sign -`, with no Hardened
Runtime and no `disable-library-validation` entitlement. The optional existing
Developer ID path remains separate and is not the free-update configuration.

## Key and publishing controls

- Only `SUPublicEDKey` is injected into the packaged Info.plist.
- The private key is never read by the package script. The release procedure
  requires a protected Keychain or a mode-600 temporary export outside the
  checkout; it must not enter Git, an app, diagnostics, or command arguments.
- `generate_appcast.sh` uses Sparkle's official `generate_appcast` and
  `sign_update`, accepts only HTTPS asset URLs in normal use, and verifies each
  emitted ZIP against its appcast Ed25519 signature.
- The generated update ZIP uses `ditto --keepParent`, preserving the bundle
  and framework symlinks. DMGs are first-download/manual assets and must not
  share the appcast input directory with an equivalent ZIP.

## Completed evidence

1. `swift build` completed with Sparkle 2.10.0 copied from the SwiftPM binary
   artifact.
2. The final Sparkle source/packaging contract group passed: 5 executed,
   0 failed.
3. The final full suite passed: 479 executed, 4 skipped, 0 failed (78.4 s).
4. Two isolated ad-hoc artifacts were packaged without installation or launch:
   A = `1.0.14 (118)`, B = `1.0.14 (119)`, both using the dedicated
   `com.codexmonitor.sparkle.productionqa` test identifier.
5. Each app's main bundle, ApprovalObserver, Sparkle.framework, Updater.app,
   Downloader.xpc, and Installer.xpc passed strict code-signature validation.
   The updater binary links via `@rpath`, and the host adds only
   `@executable_path/../Frameworks` for Sparkle.
6. The official tools produced an appcast for B with
   `sparkle:version=119`, `sparkle:shortVersionString=1.0.14`, and an
   Ed25519 enclosure signature; the script then verified that signature.
7. A release-configured artifact uses an HTTPS feed and contains no ATS local
   exception. A loopback HTTP feed and `NSAllowsLocalNetworking` exist only
   behind the explicit `SPARKLE_ALLOW_INSECURE_LOCALHOST=1` QA switch.

## Real upgrade QA status

**NOT RUN.** The A/B payloads and appcast are staged, but the app was not
installed or started. On this existing user account, normal application
startup automatically reconciles `ApprovalObserver`, whose owned data and
possible Hook reconciliation live in the current user's shared application
support area. Starting it would violate this task's prohibition on changing
accounts, authentication, or Hooks.

Therefore none of the following may be claimed yet: live Orb/QuickView,
quota-read continuity, ApprovalObserver preservation across relaunch,
download-interruption recovery, real automatic replacement/relaunch, or the
absence of a second Gatekeeper prompt. They require an approved clean macOS
user environment (or an explicit waiver for this account), normal Finder/Safari
first-launch approval, and user confirmation of Sparkle's install/relaunch UI.

## Independent-user preflight (read-only)

On 2026-10-22, the console/current user was `shouchen.nsc` (UID 502, HOME
`/Users/shouchen.nsc`). An existing candidate test account, `admin` (UID 501,
HOME `/Users/admin`), is a distinct local macOS user. At the time of the
check, its home contained no `.codex`, no Codex Monitor ApprovalObserver
directory, and no user-level Applications directory. The corresponding
formal-user paths are owned by UID 502. No candidate QA app is installed or
running; the only observed Codex Monitor process is the formal app from
`/Applications`.

This confirms a viable *candidate* isolation boundary, but it is not an active
test environment until the user manually logs into `admin`. No `HOME`
override, account creation, account switch, authentication-file access, or
Hook change was used.

Source inspection confirms why this boundary is required: app startup calls
`MonitorSurfaceCoordinator.start()`, which invokes
`activateApprovalObserver()`, which calls
`ApprovalObserverIntegration.reconcile(enabled: true)`. The reconciler may
write a helper release and identity key beneath the actual current user's
Application Support directory and reconcile Hooks. It must therefore run only
after a real login to the independent account.

## RC disposition

**READY FOR RC QA: NO.** The integration, signing chain, and update assets are
ready for controlled RC lifecycle QA, but the required real installed-app
upgrade has not been run under the task's safety constraints.
