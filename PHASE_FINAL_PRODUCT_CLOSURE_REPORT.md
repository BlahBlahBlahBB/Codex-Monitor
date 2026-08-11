# Final Product Closure Report

## Conclusion

**READY — AUTHORIZE LUNA PRODUCT SKILL / RELEASE PREPARATION**

No P0 or P1 functional blocker remains in the scoped Final Product Closure work.

## Scope and final source revision

- Final source commit: `ce9b22cf012ae1dade4458ec6b25a3932122d8f6`
- Independent human-QA build: `QA Builds/Codex Monitor Final Closure QA.app`
- Bundle ID: `local.codex.monitor.final-closure-qa`
- The build is ad-hoc signed and verified with `codesign --verify --deep --strict`.
- This closure did not change the frozen Desktop monitoring architecture or the V3-2 approval-resolution contract.

## Closure matrix

| Category | Result | Evidence |
| --- | --- | --- |
| Orb host | **PASS** | The `NSPanel` and retained `OrbHostingView` are non-opaque/clear. A real packaged-app screenshot showed only the circular orb, without a rectangular compositor backing. |
| Settings lifecycle | **PASS** | One retained `SettingsWindowController` owns its window, hosting controller/root view, presentation model, selection, and preferences. The 30-close/reopen deterministic regression passed with stable root identity and selection retention. |
| Settings content | **PASS** | Real packaged-app inspection opened Settings to a populated sidebar and the default **Floating** detail with all four backed controls. |
| Account | **PASS** | A separate read-only `AccountUsageProvider` reads the existing validated local control socket path and admits only one fresh `AccountSnapshot` into `MonitorRuntime`. UI continues to consume only the runtime snapshot. |
| Quota | **PASS** | The provider maps validated primary/secondary rate-limit windows and the UI selects the smallest remaining valid window. Real packaged inspection showed a live `62%` orb value; no value is invented when the source is absent. |
| Usage | **PASS** | The provider maps the account summary and daily buckets. The Usage UI renders Today / Last 30 days from actual buckets and fills missing days with zero only after the authoritative daily-bucket array itself is present. Cost remains `$--` because no authoritative cost source exists. |
| Reset | **PASS** | Reset-credit count is read only when returned. One live smoke reported it available; a later smoke reported it unavailable. The latter was rendered fail-closed rather than retaining a stale count. Reset detail and mutation remain unavailable/disabled. |
| Localization | **PASS** | The packaged English smoke resolved `Refresh`, `Usage`, and `Settings`; the packaged Simplified Chinese smoke resolved `刷新`, `用量`, and `设置`. Orb, Quick View, and menu-status accessibility copy now use the same localization system. |
| Orb resize | **PASS** | Existing center-preservation and screen-clamp regression passed; settings exposes the live size slider in the real packaged app. No continuous resize loop or extra timer was introduced. |
| Popover interaction | **PASS** | The action-row visual-state contract keeps resting mouse surfaces clear, gives hover/pressed feedback only, and does not impose a custom blue keyboard outline. |
| Quick View | **PASS** | Existing side-placement/screen-clamp regression passed. Runtime-backed display values sanitize unsafe task titles and show unavailable values as `--`. |
| Usage window | **PASS** | Account, plan, quota, reset, and usage presentation read the unified `MonitorRuntimeSnapshot`; no view accesses socket, SQLite, rollout, logs, RPC, or adapters directly. |
| Runtime regression | **PASS** | Live packaged smoke observed Desktop source availability and runtime-to-UI state propagation. Existing runtime tests retain fail-closed stale-data and unavailable-source behavior. |

## Real local smoke evidence

Two independent five-second launches of the packaged QA app completed and exited cleanly.

1. English package smoke: Desktop source was available; runtime/UI synchronized to a live state; Usage, Quota, and Reset count were available after the provider’s validated `account/read({})`, `account/rateLimits/read`, and `account/usage/read` requests.
2. Simplified Chinese package smoke: Desktop source, Usage, and Quota were available; Reset count was unavailable because the current source did not provide a usable count. It was not fabricated or retained.
3. A real UI inspection showed an Idle orb with a live quota percentage and no rectangular host backing. Opening Settings showed the canonical native window with **Floating** selected and its backed controls visible.

The provider uses short-lived connections and a 60-second refresh interval. It performs no polling on the main actor, no UI scraping, no credential access, no reset mutation, and does not keep an old account snapshot current after a failed refresh.

## Verification

- `swift build` — **PASS**
- `swift test` — **PASS**: 126 tests passed, 0 failures. Three pre-existing installed-path probes were skipped because their opt-in environment variables were not set.
- `git diff --check` — **PASS**
- Focused closure regressions — **PASS**:
  - transparent orb host;
  - 30 deterministic Settings close/reopen cycles;
  - Settings default detail route;
  - orb resize center/clamp;
  - Quick View placement;
  - bilingual localized strings and action feedback;
  - account/usage/quota mapping and fail-closed runtime admission.

## Capability truthfulness and known limits

- Approval **waiting detection** remains available through the existing frozen product path.
- Approval **resolution** remains explicitly **UNAVAILABLE**. The product does not synthesize Approved, Declined, or Cancelled.
- Authoritative monetary cost remains **UNAVAILABLE** and displays `$--`.
- Reset details and reset consumption remain **UNAVAILABLE**; no server mutation is exposed.
- Account, quota, usage, and reset count are dynamically capability-aware: a missing/invalid local response produces unavailable output, never a default zero, false completion, or stale value.

These are intentional capability limits, not P0/P1 blockers for the approved release-preparation handoff.

## Handoff

The functional baseline is closed. The next authorized work is **Luna product skill / release preparation** only; do not reopen monitoring architecture, account transport, approval resolution, or unrelated functionality without a real regression.
