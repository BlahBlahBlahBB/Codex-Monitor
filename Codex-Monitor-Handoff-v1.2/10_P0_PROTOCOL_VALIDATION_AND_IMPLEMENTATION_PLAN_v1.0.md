# Codex Monitor — P0 Protocol Validation & Implementation Plan v1.0

> Status: **P0 Gate — Must run before production UI implementation**
> Platform: macOS
> Target integration: Codex app-server
> Generated: 2026-08-08
> Depends on:
> - `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
> - `05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md`
> - `06_LOCAL_DATABASE_AND_SWIFT_DATA_LAYER_v1.0.md`
> - `07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md`
> - `08_DESIGN_SYSTEM_AND_COMPONENT_SPEC_v1.0.md`
> - `09_USER_FLOWS_INTERACTION_AND_EDGE_CASES_v1.0.md`

---

# 1. Why P0 Exists

Codex Monitor must not begin by building the polished SwiftUI interface and only later
discover that a required Codex Desktop signal cannot be observed.

P0 therefore validates the real installed Codex build before production work starts.

The gate answers six questions:

```text
A. What Codex version is installed?
B. Can Monitor attach to a supported local app-server transport?
C. Can it observe Threads / Turns / Items started elsewhere?
D. Can it observe the approval lifecycle without owning the approval UI?
E. What are the exact stable account / quota / usage response schemas?
F. Can account switching be supported without Monitor storing credentials?
```

Until P0 passes, UI work is limited to shell/prototype infrastructure.

---

# 2. Supported Protocol Facts To Rely On

Current Codex app-server documentation defines:

```text
JSON-RPC 2.0 style protocol
stdio transport -> JSONL
Unix socket transport -> WebSocket over local Unix socket
default Unix socket path ->
$CODEX_HOME/app-server-control/app-server-control.sock
```

The Unix socket transport is specifically intended for local app-server control-plane
clients.

The connection lifecycle is:

```text
open transport
→ initialize request
→ initialize response
→ initialized notification
→ normal requests/events
```

Any normal request before initialization should be treated as invalid.

---

# 3. Stable Schema Is Version-Specific

Before writing Swift decoders, generate the schema using the same installed Codex binary
that will be tested.

Required:

```bash
codex app-server generate-json-schema --out "$TMPDIR/codex-monitor-schema"
codex app-server generate-ts --out "$TMPDIR/codex-monitor-ts"
```

Important:

```text
stable schema generation is the default
```

Do not pass:

```text
--experimental
```

for the production v1 adapter unless a later product decision explicitly approves an
experimental dependency.

The generated schema is version-specific and must be archived with the P0 report.

---

# 4. P0 Output Folder

Create a local diagnostic folder outside the app repository:

```bash
mkdir -p "$HOME/Desktop/Codex-Monitor-P0"
```

Suggested structure:

```text
Codex-Monitor-P0/
├── environment/
│   ├── codex-version.txt
│   ├── codex-path.txt
│   ├── app-server-help.txt
│   └── doctor.json
│
├── schema/
│   ├── json/
│   └── ts/
│
├── transport/
│   ├── socket-status.txt
│   ├── initialize.jsonl
│   └── reconnect-notes.md
│
├── sanitized/
│   ├── account-read.json
│   ├── rate-limits-read.json
│   ├── usage-read.json
│   ├── loaded-threads.json
│   ├── approval-lifecycle.jsonl
│   └── token-usage.jsonl
│
└── P0_REPORT.md
```

Never save:

```text
OAuth tokens
refresh tokens
API keys
Authorization headers
cookies
full auth.json
```

---

# 5. P0 Step 1 — Environment Inventory

Run:

```bash
which codex
codex --version
codex app-server --help
codex doctor --json
```

Record:

```text
Codex CLI version
binary path
macOS version
CPU architecture
CODEX_HOME if explicitly configured
doctor app-server status
doctor-reported control socket path
auth mode label only
```

Do not include auth token values.

### PASS

```text
Codex binary is available
app-server commands are available
doctor command completes or an equivalent supported diagnostic is available
```

### FAIL

```text
installed Codex build has no app-server support
```

Fail result:

```text
STOP implementation
update integration strategy first
```

---

# 6. P0 Step 2 — Generate Stable Protocol Schema

Run:

```bash
rm -rf "$HOME/Desktop/Codex-Monitor-P0/schema/json"
rm -rf "$HOME/Desktop/Codex-Monitor-P0/schema/ts"

codex app-server generate-json-schema \
  --out "$HOME/Desktop/Codex-Monitor-P0/schema/json"

codex app-server generate-ts \
  --out "$HOME/Desktop/Codex-Monitor-P0/schema/ts"
```

Search generated schema for:

```text
account/read
account/rateLimits/read
account/rateLimits/updated
account/rateLimitResetCredit/consume
account/usage/read
thread/loaded/list
thread/list
thread/status/changed
turn/started
turn/completed
thread/tokenUsage/updated
item/commandExecution/requestApproval
item/fileChange/requestApproval
serverRequest/resolved
```

### PASS

All required stable methods/events for core v1 are present, except any feature explicitly
allowed to degrade.

### FAIL

If a core feature is missing:

```text
do not guess its wire shape
do not copy a shape from a different Codex version
```

Update the relevant product capability matrix.

---

# 7. P0 Step 3 — Determine Local Transport

Default candidate:

```text
$CODEX_HOME/app-server-control/app-server-control.sock
```

If `CODEX_HOME` is unset, use the value reported by app-server initialization/doctor
rather than hard-coding assumptions into production code.

Check:

```bash
codex doctor --json
```

and record whether the control socket is:

```text
running
not running
missing
unhealthy
```

Do not start killing/replacing Codex-owned daemon processes automatically.

---

# 8. Transport Rule For Production

Preferred production path:

```text
attach as a local control-plane client to the supported Unix socket
```

Fallback development path:

```text
launch a separate `codex app-server` process over stdio for protocol-adapter testing
```

These are not equivalent.

A Monitor-owned stdio server can validate:

```text
JSON-RPC implementation
schema decoding
account APIs
basic thread lifecycle
```

but it does **not** prove that Monitor can observe the existing Codex Desktop runtime.

---

# 9. P0 Step 4 — Initialization Probe

Build a tiny disposable probe client.

Recommended language for probe:

```text
Swift
or
Python/Node only for P0 diagnostics
```

Production implementation remains Swift.

The probe must:

```text
1. connect to the local Unix socket using the documented HTTP WebSocket Upgrade
2. send `initialize`
3. receive result
4. send `initialized`
5. log only sanitized method/result metadata
```

Client metadata:

```json
{
  "clientInfo": {
    "name": "codex_monitor_p0",
    "title": "Codex Monitor P0",
    "version": "0.0.1"
  }
}
```

Do not request experimental API capability for the initial stable probe.

### PASS

Initialization returns:

```text
userAgent
codexHome
platformFamily
platformOs
```

and subsequent stable requests are accepted.

### FAIL

Record:

```text
transport error
HTTP upgrade error
initialization error
Codex version
socket path
```

Do not immediately redesign the UI.

---

# 10. Known Transport Risk To Explicitly Test

Recent public Codex issue reports have described cases where:

```text
direct Unix socket works
but `codex app-server proxy` does not bridge correctly
```

and cases where a managed app-server daemon restarts or drops WebSocket clients.

Therefore P0 must test the direct supported socket path independently of any proxy helper.

Production should not assume:

```text
proxy success == socket health
proxy failure == socket failure
```

This is a validation risk, not a reason to use an unsupported transport.

---

# 11. P0 Step 5 — Account Read

Request:

```text
account/read
```

Capture sanitized response.

Validate availability of:

```text
auth mode
account kind
email
plan type
stable account identifier if any
requires auth / account state
```

### PASS

Monitor can determine enough account metadata to populate the approved account UI without
reading Codex credential files.

### FAIL / DEGRADE

If email/plan is absent:

```text
hide unsupported field
```

Do not invent it.

---

# 12. P0 Step 6 — Rate Limits

Request:

```text
account/rateLimits/read
```

Capture sanitized response.

Validate exact stable shape of:

```text
primary
secondary
usedPercent
windowDurationMins
resetsAt
rateLimitReachedType
individualLimit if present
spendControlReached if present
rateLimitResetCredits
rateLimitResetCredits.availableCount
rateLimitResetCredits.credits if present
```

### PASS

At least one authoritative quota surface can be decoded if the backend exposes it.

### DEGRADE

If the account/backend returns no rate-limit window:

```text
Orb center = --
runtime monitoring remains functional
```

This is not a fatal P0 failure.

---

# 13. P0 Step 7 — Sparse Rate-Limit Update

With Monitor probe connected, exercise normal Codex use long enough to observe:

```text
account/rateLimits/updated
```

Confirm that a notification may omit fields from the full snapshot.

Test adapter logic:

```text
full = account/rateLimits/read
update = sparse notification

merged = merge(full, update)
```

### PASS

Unspecified fields survive.

### FAIL

If the adapter replaces the whole snapshot with sparse data:

```text
fix before continuing
```

---

# 14. P0 Step 8 — Account Usage

Request:

```text
account/usage/read
```

This step is critical because production must not guess the response shape.

Capture only sanitized usage values.

Verify exact schema fields for:

```text
summary range
daily bucket date
input tokens
cached input tokens
output tokens
reasoning output tokens
total tokens
authoritative fee/cost if present
```

### Cost Rule

If the actual stable response contains no authoritative cost:

```text
Today fee = $--
30-day fee = $--
```

No estimation.

### PASS

Exact response can be mapped to the normalized Usage model.

### PARTIAL PASS

Usage tokens work but fee is absent:

```text
ship tokens
show $--
```

### FAIL

If `account/usage/read` is not available in the installed stable schema:

```text
do not ship a fabricated 30-day account Usage implementation
```

Re-scope Usage to supported data.

---

# 15. P0 Step 9 — Loaded Threads

Request:

```text
thread/loaded/list
```

Validate:

```text
currently loaded Threads are visible
thread ID
status
title/preview data available
```

If the exact title is not returned in this response:

```text
use supported thread/read / thread/list data
```

as defined by the stable schema.

---

# 16. P0 Step 10 — Observe An Existing Codex Desktop Turn

This is the most important runtime integration test.

Sequence:

```text
1. Keep P0 Monitor client connected.
2. In Codex Desktop, start a normal task.
3. Do not start that Turn from the probe.
4. Observe Monitor events.
```

Expected events/state evidence:

```text
thread becomes known/subscribed
thread/status/changed -> active
turn/started
item/started
item/completed
turn/completed
```

### PASS

The secondary Monitor client can observe enough of a Desktop-created Turn to drive the
frozen state engine.

### FAIL

If events are only delivered to the client that created/subscribed to the Thread:

```text
STOP
```

Do not ship realtime monitoring based on assumptions.

Investigate a supported subscription/reconciliation path first.

---

# 17. Subscription/Reconciliation Probe

If an existing loaded Thread is visible but events do not initially stream:

Test supported stable subscription behavior from the generated schema.

Goal:

```text
Monitor attaches/subscribes to existing loaded Thread
without starting/resuming a fake user Turn
```

Record the exact supported method used.

Do not use:

```text
thread/resume
```

merely to force monitoring if that changes the user's active Codex session behavior.

The production client must be observational.

---

# 18. P0 Step 11 — Thread Status

Exercise:

```text
idle
active
system error if safely reproducible
```

Verify `thread/status/changed` shape.

Known documented status types include:

```text
notLoaded
idle
systemError
active
```

`active` may include:

```text
activeFlags
```

The state engine may use thread status as a coarse fallback, not the sole current-action
signal.

---

# 19. P0 Step 12 — Item Mapping

Run safe tasks that cause:

```text
reasoning
command execution
file change
tool invocation if available
```

Capture event method + item type only.

Verify that the adapter can derive:

```text
THINKING
WORKING
```

and one-line current activity without exposing reasoning content.

---

# 20. P0 Step 13 — Token Usage

During a Turn, capture:

```text
thread/tokenUsage/updated
```

Verify:

```text
threadId correlation
cumulative vs delta semantics
token field names
replay/resume behavior if observable
```

### PASS

Quick View can show current Session Token usage independently from quota %.

### FAIL / DEGRADE

If no stable per-thread token event exists in the installed schema:

```text
hide Session Token rather than inventing it
```

---

# 21. P0 Step 14 — Approval Visibility

This is a hard gate for the yellow state.

Create a harmless Codex task that naturally requires authorization under the user's
current Codex approval policy.

Observe from the Monitor connection.

Expected lifecycle can include:

```text
item/started
item/.../requestApproval
serverRequest/resolved
item/completed
```

Important:

The Monitor must **not** respond to the approval request.

The user resolves it in Codex Desktop.

### PASS

Monitor sees:

```text
request arrives
→ WAITING_APPROVAL

user resolves in Codex
→ serverRequest/resolved or equivalent authoritative resolution
→ Monitor leaves WAITING_APPROVAL
```

### FAIL

If approval requests are routed only to the owning Codex Desktop client and are not
observable from the Monitor connection:

```text
yellow WAITING_APPROVAL cannot be claimed reliable
```

Do not infer it from timeouts or stalled work.

Product fallback:

```text
disable yellow approval state until a supported observer mechanism exists
```

or revise integration architecture.

---

# 22. Approval Safety

P0 code must never accidentally approve a real request.

For server-initiated approval requests:

```text
log sanitized request identity
do not send accept
do not send decline
```

If the protocol requires every subscribed client to answer and no passive-observer
behavior exists:

```text
record FAIL
disconnect the test client safely
```

This is exactly what P0 is designed to discover.

---

# 23. P0 Step 15 — Turn Completion

Create three safe scenarios where possible:

```text
successful completion
user interruption
controlled failure
```

Verify exact `turn/completed` terminal status values.

Map to:

```text
completed
interrupted
failed
```

Then test frozen retention:

```text
completed -> 5 s
red terminal -> 15 s
```

The retention timer belongs to Monitor, not Codex.

---

# 24. P0 Step 16 — Multiple Threads

With at least two loaded Threads:

```text
A working
B working / waiting / terminal
```

Verify events retain sufficient:

```text
threadId
turnId
itemId
```

for isolated per-thread state.

Test global aggregation separately with recorded events even if live concurrency is
difficult to reproduce.

---

# 25. P0 Step 17 — Reset Credit Read

Do:

```text
account/rateLimits/read
```

and inspect:

```text
rateLimitResetCredits.availableCount
credits detail if present
```

No credit must be consumed just to prove the read API.

### PASS

Count is decoded correctly whenever backend provides it.

---

# 26. P0 Step 18 — Reset Consume Safety

Do **not** automatically consume a real earned reset during P0.

Production adapter should be validated first with:

```text
generated schema
unit mock
recorded protocol fixtures
```

Only perform a live consume test if the user explicitly approves spending one real reset
credit.

If approved, test:

```text
idempotencyKey
response enum
full refetch afterward
```

Never run this as part of automated CI.

---

# 27. P0 Step 19 — Account Change / Switching

Goal 1:

Verify:

```text
account/updated
```

when Codex account/auth state changes.

Goal 2:

Inspect stable schema for an official account-switching surface.

### PASS FOR HISTORY SCOPING

Monitor can detect account changes and separate local data by account.

### PASS FOR ACTIVE SWITCHING

Only if an official supported mechanism allows switching without Monitor storing raw
credentials.

### FAIL FOR ACTIVE SWITCHING

If no supported mechanism exists:

```text
remove/disable prototype “save/switch account” actions in v1
```

This does not block the rest of Monitor.

---

# 28. P0 Step 20 — Disconnect / Reconnect

While a Turn is idle or safely running:

```text
temporarily stop/restart the relevant Codex/app-server path
or reproduce a benign connection loss
```

Verify:

```text
Monitor -> DISCONNECTED
no fake FAILED
automatic reconnect
fresh initialize
fresh snapshots
thread reconciliation
correct restored state
```

Use exponential backoff with jitter in production.

---

# 29. P0 Step 21 — Sleep / Wake

Close full-screen critical work first.

Test:

```text
Mac sleeps
↓
wake
↓
Monitor reconnects/revalidates
↓
account/rate limits/thread state reconcile
```

No manual Refresh should be required.

---

# 30. P0 Step 22 — Load / Backpressure

The app-server documentation defines a retryable overloaded request error:

```text
code -32001
"Server overloaded; retry later."
```

Test the client policy with a mock/fixture.

Production behavior:

```text
exponential backoff
jitter
request dedupe
no busy loop
```

Do not intentionally overload the user's real Codex process for P0.

---

# 31. Sanitization Rules

Before writing any response to the P0 folder, recursively redact keys/names matching
credential semantics, including:

```text
token
access_token
refresh_token
authorization
cookie
secret
api_key
apiKey
bearer
```

Exception:

```text
token usage numeric fields
```

must not be erased solely because they contain the word `token`.

Sanitizer must distinguish:

```text
usage counts
```

from:

```text
credentials
```

---

# 32. P0 Report Template

`P0_REPORT.md`:

```text
# Codex Monitor P0 Report

Codex version:
macOS version:
Architecture:
Codex binary:
Codex home:
Stable schema generated: PASS/FAIL

## Gates

P0-A Local app-server attach: PASS/FAIL
P0-B Observe Desktop-created Turn: PASS/FAIL
P0-C Approval lifecycle visibility: PASS/FAIL
P0-D Account read: PASS/PARTIAL/FAIL
P0-E Rate limits: PASS/PARTIAL/FAIL
P0-F Account usage: PASS/PARTIAL/FAIL
P0-G Thread token usage: PASS/PARTIAL/FAIL
P0-H Account change detection: PASS/FAIL
P0-I Safe official active account switching: PASS/NOT SUPPORTED/FAIL
P0-J Reconnect: PASS/FAIL

## Exact Supported Methods

...

## Exact Schema Notes

...

## Required Product Degradations

...

## Go / No-Go

GO
or
NO-GO
```

---

# 33. Hard Go / No-Go Gates

## GO for full v1

Required:

```text
Local supported connection = PASS
Observe Desktop-created runtime state = PASS
Thread identity/event correlation = PASS
Account/rate-limit surface sufficient for Orb quota = PASS or graceful PARTIAL
Reconnect = PASS
```

Approval:

```text
PASS -> ship yellow approval state
FAIL -> yellow approval state must be removed/degraded before release
```

Usage:

```text
PASS -> ship full approved Usage page
PARTIAL -> hide unsupported cost/fields
FAIL -> re-scope Usage before release
```

Multi-account switching:

```text
NOT SUPPORTED -> do not block core Monitor
```

---

# 34. Automatic No-Go Conditions

Stop production implementation if:

```text
Monitor cannot observe Codex Desktop-created active Threads/Turns
```

or:

```text
the only available solution requires reading/storing private Codex credentials
```

or:

```text
the integration requires unstable/private backend endpoints to implement core monitoring
```

or:

```text
Monitor would need to own/alter Codex task lifecycle merely to observe it
```

---

# 35. Fallback Hierarchy

Allowed:

```text
A. supported local Unix-socket control-plane connection
B. other stable officially supported app-server local transport
C. Monitor-owned stdio app-server only for capabilities that are truly equivalent
```

Not acceptable as the primary production architecture without a new design review:

```text
private backend endpoints
auth.json credential extraction
screen scraping
UI accessibility scraping of Codex Desktop
continuous JSONL log tailing as the main runtime truth
guessing approval state
guessing quota from Token usage
```

Local persisted Codex data may be used only as a narrowly scoped fallback when the
specific product field cannot be supplied by the stable protocol and the safety/privacy
implications are explicitly reviewed.

---

# 36. Implementation Order After P0

Only after the P0 report is accepted:

### Milestone 1 — Core transport

```text
Swift JSON-RPC/WebSocket-over-Unix transport
initialize
reconnect
request/response routing
notification routing
server-request routing
sanitization
```

### Milestone 2 — Protocol adapter

```text
generated stable schema
domain models
event normalization
account/rate-limit/usage adapters
```

### Milestone 3 — State engine

Implement frozen:

```text
per-thread states
global priority
5 s completion
15 s red terminal
0.8 s visual breathing flag
```

### Milestone 4 — Persistence

```text
SQLite/GRDB
migrations
usage history
thread usage
settings
```

### Milestone 5 — Headless integration test harness

Before UI:

```text
print normalized state changes
print sanitized account/quota/usage summaries
replay fixture event streams
```

### Milestone 6 — macOS shell

```text
LSUIElement
NSStatusItem
WindowCoordinator
Usage/Settings NSWindow
Orb NSPanel
Quick View NSPanel
```

### Milestone 7 — Native UI

```text
status capsule
menu popup
Orb
Quick View
Usage
Settings
```

### Milestone 8 — Native Liquid Glass

Apply only after behavior is correct:

```text
Orb
Quick View
system-appropriate surfaces
```

### Milestone 9 — Notifications / Login Item

```text
UNUserNotificationCenter
SMAppService
```

### Milestone 10 — QA / packaging

```text
unit tests
integration tests
accessibility
Light/Dark
Reduce Motion
Reduce Transparency
multi-display
sleep/wake
signed build
```

---

# 37. What Codex Must Not Do First

Do not start with:

```text
polishing Liquid Glass
animating the Orb
building the Usage chart
building account switching UI
```

before P0 transport/runtime visibility passes.

The first visible milestone should intentionally be ugly/headless if necessary.

Correct runtime truth is more important than visual completeness at P0.

---

# 38. Recommended P0 Probe Deliverable

Codex should create a disposable folder:

```text
Tools/P0Probe/
```

with:

```text
README.md
probe source
sanitizer
schema inspection script
event recorder
fixture exporter
```

The probe is not shipped inside the release app unless its code is deliberately promoted
into the production transport module after review.

---

# 39. Fixture Strategy

After successful P0, create sanitized fixtures for:

```text
disconnected
idle
thinking
command working
file change
waiting approval
approval resolved
completed
interrupted
failed
rate-limit full snapshot
rate-limit sparse update
usage snapshot
thread token update
account change
```

These fixtures power deterministic tests without consuming Codex quota or requiring a
real account in CI.

---

# 40. Test Pyramid

```text
many:
unit tests
protocol decoding tests
state engine fixture tests
formatting tests
database tests

some:
mock app-server integration tests

few:
real local Codex Desktop P0/manual tests
```

CI must not depend on:

```text
real user ChatGPT account
real reset credits
real OAuth credentials
```

---

# 41. Build Milestones / Exit Criteria

## M0 — P0

Exit:

```text
P0_REPORT accepted
```

## M1 — Headless core

Exit:

```text
real events -> normalized console state
```

## M2 — Persistence

Exit:

```text
usage/history survive restart
```

## M3 — System utility shell

Exit:

```text
status item + Orb + windows open/close correctly
```

## M4 — Functional UI

Exit:

```text
all approved flows work
visual polish not final
```

## M5 — Design fidelity

Exit:

```text
v1.9 approved design translated into native macOS behavior
```

## M6 — Release candidate

Exit:

```text
QA matrix passes
no P0 regression
signed/notarized distribution path prepared
```

---

# 42. P0 Acceptance Checklist

P0 is complete only when Codex can answer with evidence:

```text
[ ] Exact installed Codex version captured
[ ] Stable JSON schema generated from that version
[ ] Stable TS schema generated
[ ] Local control socket path discovered safely
[ ] Initialize handshake succeeds
[ ] account/read captured
[ ] account/rateLimits/read captured
[ ] sparse rate-limit update tested or fixture verified
[ ] account/usage/read exact schema captured
[ ] loaded Threads visible
[ ] Desktop-created Turn observable
[ ] Item lifecycle observable
[ ] thread/tokenUsage/updated validated
[ ] approval lifecycle passive visibility tested
[ ] turn/completed mapping validated
[ ] multi-thread identity correlation validated
[ ] reconnect tested
[ ] account change behavior tested
[ ] no credentials stored
[ ] sanitized fixtures generated
[ ] P0_REPORT contains GO / NO-GO
```

---

# 43. Current External Risk Notes

At the time of this document, public Codex reports have included:

```text
app-server proxy bridging failures in some versions/environments
managed daemon reconnect/restart issues
Unix-domain-socket path-length constraints when CODEX_HOME is unusually deep
```

These are reasons to make the connection layer defensive.

They are **not** permission to replace the documented local protocol with a private
backend.

Production must:

```text
discover the actual socket path
handle reconnects
handle missing socket
handle version mismatch
surface diagnostics
avoid assuming proxy health
```

---

# 44. Final P0 Principle

The production rule is:

```text
Observe only what Codex can authoritatively expose.
Display unavailable data honestly.
Never guess a safety/approval/accounting state.
Never store Codex credentials to make a feature easier.
```

Once P0 passes, the rest of the product can be built against a stable, testable domain
layer instead of a collection of assumptions.

---

# 45. Next Step After P0 Plan

After this plan is accepted, prepare:

```text
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS
```

That final master document should:

```text
merge all frozen product decisions
reference the approved v1.9 visual prototype
reference specs 04–10
define repository setup
define implementation phases
define mandatory Apple design skill usage
define acceptance gates
give Codex a strict “do not redesign” directive
```

Then package the complete handoff bundle for Codex.
