# Codex Monitor — Capability Baseline & Gates v1.0

## Current release state

```text
Architecture: CONDITIONAL GO
Release: INTERNAL / DEVELOPER ONLY
Current implementation authorization: H1 only
```

## Account

| Capability | State | Product rule |
|---|---|---|
| account returned fields | snapshot | optional + freshness scoped |
| primary rate-limit snapshot | snapshot | usable |
| secondary rate limit | optional/unvalidated | absence stays absence |
| authoritative cost | unsupported in captured shape | `$--` |
| sparse rate-limit merge | unvalidated | notification → full refetch |
| stable non-secret account key | unvalidated | no stable-key claim |
| account switching | unvalidated | no product action |
| reset-credit count | snapshot | returned count only |
| reset-credit details | partial | do not invent element semantics |
| reset mutation | unvalidated | disabled |

## Monitor-owned runtime

| Capability | State | Product rule |
|---|---|---|
| observed success lifecycle methods | partial evidence | model contracts only |
| exact Thread→Turn→Item parent correlation | unvalidated/partial | no full realtime claim |
| THINKING/WORKING production reduction | unvalidated | H3 gated |
| current activity text | unvalidated | no user-visible text |
| approval lifecycle | unvalidated | WAITING_APPROVAL disabled |
| Session Token display | unvalidated | disabled |
| multi-Thread aggregation | unvalidated | disabled |
| success terminal | partial observed | contracts/fixtures allowed |
| failed terminal | unvalidated | real projection disabled |
| interrupted terminal | unvalidated | real projection disabled |
| reconnect/reconciliation | unvalidated | no recovery claim |
| owner UI survival/reattach | unvalidated | no survival claim |

## Desktop Snapshot

| Capability | State | Product rule |
|---|---|---|
| thread/list/read methods | snapshot availability | source classification still gated |
| product-visible ordinary Desktop rows | unvalidated | disabled |
| Desktop realtime | unsupported | never emit live state |
| Desktop approval | unsupported | never emit WAITING_APPROVAL |
| Desktop Session Token | unsupported | omit |

## Transport

```text
Architecture work: allowed
Release maturity: INTERNAL / DEVELOPER ONLY
```

Before H2 starts, H1/H1R must record one exact selected local transport and its lifecycle/security assumptions.

## Capability promotion rule

Promotion requires retained, reproducible evidence.

Mocks can validate Domain behavior.

Mocks cannot promote a real Adapter capability.
