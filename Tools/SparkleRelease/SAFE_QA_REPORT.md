# Sparkle Safe QA report — current-account isolated mode

Date: 2026-10-22
Worktree: `Worktrees/SparkleProductionIntegration`
Branch: `codex/sparkle-production-integration-20261022`

## Scope

This is a disposable, compile-time QA configuration only. It does not modify
`main`, a GitHub Release, tags, the installed production app, accounts,
authentication, or Hooks.

The QA product identity is `com.codexmonitor.sparkle.productionqa`; its
Finder-installed name became `Codex Monitor Sparkle Production QA 2.app`
because Finder retained another disposable copy. The production application
remains `/Applications/Codex Monitor.app` with bundle identifier
`com.codexmonitor.app`.

## Startup-side-effect audit and isolation implementation

`QAIsolation` is compile-time only (`CODEX_MONITOR_QA_ISOLATION`), not an
environment variable, preference, command line value, or network response.
It validates the packaged QA marker and dedicated bundle identifier before
`NSApplication` is created. The production compilation rejects a QA-marked
Info.plist.

In QA mode, before runtime startup:

- `CodexLocalMonitorDriver` is not constructed or started.
- `AccountUsageProvider` is not constructed or started; no Codex account or
  authentication transport is opened.
- `ApprovalObserverIntegration.reconcile` is not called; no Hook inspection,
  reconciliation, helper release, journal, checkpoint, or identity-key action
  occurs.
- `MonitorNotificationController` is not constructed and login-item status is
  not queried or registered.
- Settings actions that could open `.codex`, diagnostics, notification
  permission, login-item registration, pause/restart monitoring, or Codex
  Desktop are gated off.
- diagnostics and Orb-layer diagnostics return before recording.

QA uses `UserDefaults.standard` under its distinct bundle identifier, which
macOS persists as
`~/Library/Preferences/com.codexmonitor.sparkle.productionqa.plist`; it does
not reuse the production preferences domain. No `HOME` override is used.

## Regression and static safety evidence

- QA-compiled `CrossMachineValidationTests`: 7 executed, 0 failures.
- The QA-only delegate-construction test passed without application launch or
  runtime infrastructure startup.
- Standard Sparkle/isolation contract tests: 2 executed, 0 failures.
- The full Swift regression suite completed after the change without a
  non-zero exit reported by SwiftPM.
- Jev advisory review used the current `noul` schema only. It is supplementary
  and is not treated as execution or security proof.

## Assets and trust checks

The failed first asset set was retained. A new temporary key and new matching
asset set were generated after the source correction; no production private
key was used.

- A: `1.0.14 (118)`; B: `1.0.14 (119)`.
- Both use ad-hoc signing, no Hardened Runtime, and no
  `disable-library-validation` entitlement.
- Main apps, ApprovalObserver, Sparkle.framework, Updater.app, Downloader.xpc,
  and Installer.xpc passed strict signature verification.
- The appcast uses the official Sparkle tools and has a Build-119 Ed25519
  enclosure signature. The QA feed contains only the complete ZIP asset; no
  delta asset is referenced.
- QA loopback HTTP is explicit and limited to `127.0.0.1`; ordinary packaging
  remains HTTPS-only. The generated QA app includes `SUPublicEDKey`, never the
  private key.

## First QA startup correction

The first rebuilt A crashed before `applicationDidFinishLaunching`, at
`CodexMonitorAppDelegate.init()`. Evidence:

`~/Library/Logs/DiagnosticReports/CodexMonitorApp-2026-10-22-135735.ips`

and the two subsequent `135742` / `135746` reports. Offline disassembly showed
the trap occurred when `UserDefaults(suiteName:)` returned nil in the ad-hoc
release app. The QA configuration was corrected to use the automatically
bundle-scoped `UserDefaults.standard`, then A/B and the appcast were rebuilt
with a fresh disposable key. No production subsystem had started before those
crashes.

## Real A(118) → B(119) lifecycle result

**PASS.**

1. The user installed and normally Gatekeeper-approved QA A through Finder.
2. A displayed Sparkle's real update prompt for `Codex Monitor 1.0.14 (119)`
   from `1.0.14 (118)`.
3. The user clicked Sparkle's **Install Update** and relaunch confirmations.
4. The running replacement is:
   `/Users/shouchen.nsc/Applications/Codex Monitor Sparkle Production QA 2.app/Contents/MacOS/CodexMonitorApp`
5. Its live Info.plist reports the dedicated bundle identifier, version
   `1.0.14`, build `119`, and `CodexMonitorQAIsolation=true`.
6. The app is not running from an App Translocation path. The replacement app
   and its Downloader/Installer XPC services passed strict signature checks.

The suffix `2.app` is a Finder duplicate-name result, not an installer error;
the original expected filename was absent only because Finder had chosen a
different user-level name.

No automated security exception, Gatekeeper change, quarantine removal, sudo,
manual shell replacement, or administrator authorization was used. No second
Gatekeeper or administrator dialog was reported during the Sparkle update.

## Formal-user data boundary

The QA product's only observed persistent state is its dedicated preference
plist. Source-level and QA-compiled tests establish that the production
account, `.codex`, Hooks, ApprovalObserver, and production Codex Monitor data
paths are not started by the QA runtime.

The formal Codex Desktop and formal Codex Monitor were active throughout this
current-account test. Their state databases and Observer logs changed between
read-only baseline snapshots, so a whole-file hash comparison cannot honestly
attribute or rule out unrelated concurrent formal-app writes. This is recorded
as an evidence limitation, not claimed as QA-caused mutation. No QA process,
path, support directory, or Hook action was observed against those resources.

## Disposition

`A(118) → B(119)`: **PASS** for the real Sparkle download, signed full-ZIP
install, replacement, and relaunch lifecycle.

`READY FOR RC QA`: **NO**. The current-account safe QA demonstrates the updater
and QA-isolation lifecycle, but it does not constitute production account,
approval, quota, or Hook acceptance. The concurrent production process also
prevents a stronger file-diff proof of formal-user data non-mutation.

## Completion cleanup

The two loopback-only QA HTTP services were stopped after validation. Only the
two exact temporary mode-600 QA private-key files were deleted; QA ZIPs,
appcasts, crash evidence, the Finder-installed QA app, and this report were
retained. No production key, artifact, or application was removed.
