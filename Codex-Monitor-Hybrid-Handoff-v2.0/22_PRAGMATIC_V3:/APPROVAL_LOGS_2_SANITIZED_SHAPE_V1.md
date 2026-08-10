# Sanitized `logs_2.sqlite` Approval Shape — v1

This retained V3-2F fixture is a privacy-bounded shape capture from the
LP0/V3-2R installed-source check. It intentionally contains no log body,
prompt, command, tool output, path, title, or raw production identifier.

```text
PRAGMA user_version: 0
table: logs
required columns: id, thread_id, ts, target, level, feedback_log_body
exact logger target: codex_core::stream_events_utils

request marker set:
  requestApproval + waitingOnApproval
  thread_id + turn_id + request_id (or call_id/item_id)

resolution marker set:
  approvalApproved | approvalDeclined | approvalCancelled |
  itemCompleted | approvalTerminal
  thread_id + turn_id + request_id (or call_id/item_id)
```

The adapter's tests use only opaque synthetic IDs and the marker grammar above.
The parser never treats the complete body as JSON and immediately discards it.
Unknown approval-looking variants fail the approval capability closed.
