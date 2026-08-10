# H4 — Terra / High — Account / Rate Limit / Usage Read Adapters

> Execute only if H3R authorizes H4.

```text
实现 only validated/partial read capabilities：

account/read
account/rateLimits/read
account/usage/read
reset-credit count snapshot

规则：
- all optional
- freshness
- full rate-limit refetch on update notification
- no sparse merge
- dynamic quota windows
- no cost estimate
- no stable account key
- no account switching
- no reset consume
- no timezone-sensitive 30-day chart semantic claim until validated

输出 PHASE_H4_REPORT.md。
停止。
下一阶段建议 Sol High H4R。
```
