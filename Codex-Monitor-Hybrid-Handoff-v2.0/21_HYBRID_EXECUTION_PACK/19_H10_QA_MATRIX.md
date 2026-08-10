# H10 — Capability/Source QA

## Execution model

```text
Luna Medium:
execute bounded regression matrix / record failures

Terra Medium:
ordinary fixes

Terra High:
protocol / concurrency / AppKit lifecycle / migration fixes

Sol High:
only if architecture/product/capability promotion is proposed
```

## Matrix

Test by both:

```text
source kind
×
capability state
```

Required:

```text
Account snapshot
runtimeUnavailable
Monitor-owned live available subset
Desktop snapshot-only
mixed mode
stale
capability loss
transport loss
Light/Dark
Reduce Motion/Transparency
multi-display
sleep/wake
DB migration
privacy
forbidden inference
no reset mutation
no public-release wording
```

Output:
`PHASE_H10_REPORT.md`

Do not promote a capability merely because UI tests pass.
