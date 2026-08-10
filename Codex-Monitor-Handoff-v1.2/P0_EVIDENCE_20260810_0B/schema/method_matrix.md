# Stable schema method presence

Generated from Codex CLI `0.147.0-alpha.6.5` without `--experimental`.

| Stable method/notification | Presence |
|---|---|
| `account/read` | PRESENT |
| `account/rateLimits/read` | PRESENT |
| `account/rateLimits/updated` | PRESENT; description requires sparse merge/refetch |
| `account/rateLimitResetCredit/consume` | PRESENT; not invoked |
| `account/usage/read` | PRESENT |
| `account/updated` | PRESENT |
| `thread/loaded/list` | PRESENT; cursor pagination |
| `thread/list` / `thread/read` | PRESENT; cursor pagination/read support |
| `thread/subscribe` | ABSENT |
| `thread/unsubscribe` | PRESENT |
| `thread/status/changed` | PRESENT |
| `turn/started` / `turn/completed` | PRESENT |
| `thread/tokenUsage/updated` | PRESENT |
| `serverRequest/resolved` | PRESENT |
| legacy `item/*/requestApproval` names in P0 plan | ABSENT; exact current passive observation remains unverified |

Schema aggregate SHA-256: `7d79fe309dd7520843459070f3884ecf0e39cee2620c1c49aad6efb4eca76ecb`.
