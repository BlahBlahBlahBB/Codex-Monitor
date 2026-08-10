#!/usr/bin/env python3
"""Disposable, sanitized AR-P0 Hybrid capability probe.

This is evidence tooling only.  It neither imports nor implements Codex Monitor
product modules.  It deliberately retains no account values, identifiers,
thread content, command text, paths, credentials, or raw JSON-RPC payloads.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import secrets
import select
import socket
import struct
import subprocess
import tempfile
import time
from collections import Counter
from pathlib import Path
from typing import Any


class ProbeError(RuntimeError):
    pass


def _type_shape(value: Any, depth: int = 0) -> Any:
    """Return field names and value classes, never values."""
    if depth >= 5:
        return "…"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return {"array": _type_shape(value[0], depth + 1) if value else "empty"}
    if isinstance(value, dict):
        return {key: _type_shape(item, depth + 1) for key, item in sorted(value.items())}
    return type(value).__name__


def _digest(values: list[str], salt: bytes) -> str:
    """A per-run correlation digest; salt is memory-only and never exported."""
    rendered = "\x1f".join(sorted(values)).encode("utf-8")
    return hashlib.sha256(salt + rendered).hexdigest()


def _read_exact(connection: socket.socket, length: int) -> bytes:
    parts: list[bytes] = []
    while length:
        part = connection.recv(length)
        if not part:
            raise ProbeError("connection closed")
        parts.append(part)
        length -= len(part)
    return b"".join(parts)


def _send_ws_text(connection: socket.socket, message: dict[str, Any]) -> None:
    payload = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    size = len(payload)
    if size < 126:
        head = bytes((0x81, 0x80 | size))
    elif size <= 0xFFFF:
        head = bytes((0x81, 0x80 | 126)) + struct.pack("!H", size)
    else:
        head = bytes((0x81, 0x80 | 127)) + struct.pack("!Q", size)
    mask = os.urandom(4)
    encoded = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    connection.sendall(head + mask + encoded)


def _read_ws_message(connection: socket.socket) -> dict[str, Any] | None:
    first, second = _read_exact(connection, 2)
    opcode, size = first & 0x0F, second & 0x7F
    masked = bool(second & 0x80)
    if size == 126:
        size = struct.unpack("!H", _read_exact(connection, 2))[0]
    elif size == 127:
        size = struct.unpack("!Q", _read_exact(connection, 8))[0]
    mask = _read_exact(connection, 4) if masked else b""
    payload = _read_exact(connection, size)
    if masked:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    if opcode == 0x8:
        return None
    if opcode == 0x9:
        connection.sendall(bytes((0x8A, len(payload))) + payload)
        return None
    if opcode != 0x1 or not (first & 0x80):
        raise ProbeError("unsupported websocket frame")
    decoded = json.loads(payload.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise ProbeError("non-object protocol message")
    return decoded


class StreamConnection:
    """Byte bridge for the documented `codex app-server proxy` command."""
    def __init__(self, process: subprocess.Popen[bytes]) -> None:
        self.process = process
        assert process.stdin is not None and process.stdout is not None
        self.stdin = process.stdin
        self.stdout = process.stdout
        self.timeout = 5.0

    def fileno(self) -> int:
        return self.stdout.fileno()

    def settimeout(self, timeout: float) -> None:
        self.timeout = timeout

    def sendall(self, payload: bytes) -> None:
        self.stdin.write(payload)
        self.stdin.flush()

    def recv(self, size: int) -> bytes:
        ready, _, _ = select.select([self.stdout], [], [], self.timeout)
        if not ready:
            raise TimeoutError("proxy read timeout")
        return os.read(self.stdout.fileno(), size)

    def close(self) -> None:
        if not self.stdin.closed:
            self.stdin.close()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=3)


class WsRpc:
    def __init__(self, socket_path: Path | None, label: str, connection: Any | None = None) -> None:
        self.socket_path = socket_path
        self.label = label
        if connection is None:
            if socket_path is None:
                raise ProbeError("missing Unix socket path")
            connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            connection.settimeout(5)
            connection.connect(str(socket_path))
        self.connection = connection
        self._upgrade()
        self.next_id = 1
        self.notifications: list[dict[str, Any]] = []
        self.server_requests: list[dict[str, Any]] = []

    def _upgrade(self) -> None:
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode("ascii")
        self.connection.sendall(request)
        response = b""
        while b"\r\n\r\n" not in response:
            response += self.connection.recv(1024)
            if len(response) > 16_384:
                raise ProbeError("oversized websocket handshake")
        if b" 101 " not in response.split(b"\r\n", 1)[0]:
            raise ProbeError("websocket upgrade rejected")

    def initialize(self) -> dict[str, Any]:
        response = self.call("initialize", {
            "clientInfo": {"name": "codex-monitor-ar-p0-probe", "title": "Codex Monitor AR-P0 Probe", "version": "1.0"},
            "capabilities": {"experimentalApi": False, "requestAttestation": False, "optOutNotificationMethods": None, "extensions": None},
        })
        _send_ws_text(self.connection, {"method": "initialized", "params": {}})
        return response

    def _record_unsolicited(self, message: dict[str, Any]) -> None:
        if "id" in message and "method" in message:
            params = message.get("params")
            self.server_requests.append({
                "method": message.get("method") if isinstance(message.get("method"), str) else "<UNKNOWN>",
                "param_keys": sorted(params) if isinstance(params, dict) else [],
            })
        elif "method" in message:
            params = message.get("params")
            self.notifications.append({
                "method": message.get("method") if isinstance(message.get("method"), str) else "<UNKNOWN>",
                "params": params if isinstance(params, dict) else {},
            })

    def call(self, method: str, params: dict[str, Any] | None = None, timeout: float = 20) -> dict[str, Any]:
        request_id = self.next_id
        self.next_id += 1
        request: dict[str, Any] = {"method": method, "id": request_id}
        if params is not None:
            request["params"] = params
        _send_ws_text(self.connection, request)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.connection.settimeout(max(0.1, deadline - time.monotonic()))
            message = _read_ws_message(self.connection)
            if message is None:
                raise ProbeError(f"connection closed during {method}")
            if message.get("id") == request_id and "method" not in message:
                if "error" in message:
                    return {"ok": False, "error_shape": _type_shape(message.get("error"))}
                return {"ok": True, "result": message.get("result")}
            self._record_unsolicited(message)
        raise ProbeError(f"timeout during {method}")

    def drain(self, duration: float) -> None:
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.connection], [], [], min(0.25, deadline - time.monotonic()))
            if not ready:
                continue
            message = _read_ws_message(self.connection)
            if message is None:
                return
            self._record_unsolicited(message)

    def close(self) -> None:
        self.connection.close()


def _tcp_client(port: int, label: str) -> WsRpc:
    connection = socket.create_connection(("127.0.0.1", port), timeout=5)
    return WsRpc(None, label, connection)


def _proxy_client(codex: str, socket_path: Path, label: str) -> WsRpc:
    process = subprocess.Popen(
        [codex, "app-server", "proxy", "--sock", str(socket_path)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return WsRpc(socket_path, label, StreamConnection(process))


def _event_summary(events: list[dict[str, Any]], known_thread_ids: set[str]) -> dict[str, Any]:
    methods = Counter(event["method"] for event in events)
    item_types = Counter()
    correlation_checked = 0
    correlation_mismatch = 0
    token_shapes: list[Any] = []
    terminal_statuses: list[str] = []
    active_flags_seen = False
    for event in events:
        params = event["params"]
        thread_id = params.get("threadId")
        if isinstance(thread_id, str):
            correlation_checked += 1
            if thread_id not in known_thread_ids:
                correlation_mismatch += 1
        item = params.get("item")
        if isinstance(item, dict) and isinstance(item.get("type"), str):
            item_types[item["type"]] += 1
        if event["method"] == "thread/tokenUsage/updated":
            token_shapes.append(_type_shape(params.get("tokenUsage")))
        if event["method"] == "turn/completed":
            turn = params.get("turn")
            if isinstance(turn, dict) and isinstance(turn.get("status"), str):
                terminal_statuses.append(turn["status"])
        if event["method"] == "thread/status/changed":
            status = params.get("status")
            active_flags_seen = active_flags_seen or (isinstance(status, dict) and status.get("type") == "active")
    return {
        "method_counts": dict(sorted(methods.items())),
        "item_lifecycle_types": dict(sorted(item_types.items())),
        "correlation": {"checked": correlation_checked, "mismatches": correlation_mismatch},
        "token_usage_shapes": token_shapes[:1],
        "terminal_statuses": terminal_statuses,
        "active_status_observed": active_flags_seen,
        "hidden_reasoning_retained": False,
    }


def _result_shape(response: dict[str, Any]) -> dict[str, Any]:
    if not response["ok"]:
        return {"ok": False, "error_shape": response["error_shape"]}
    return {"ok": True, "shape": _type_shape(response.get("result"))}


def _start_thread(client: WsRpc, model: str, approval_policy: str = "never") -> tuple[str | None, dict[str, Any]]:
    response = client.call("thread/start", {
        "model": model,
        "cwd": str(Path.cwd()),
        "approvalPolicy": approval_policy,
        "sandbox": "read-only",
        "serviceName": "codex_monitor_ar_p0_disposable_probe",
        "ephemeral": True,
    })
    if not response["ok"] or not isinstance(response.get("result"), dict):
        return None, _result_shape(response)
    thread = response["result"].get("thread")
    thread_id = thread.get("id") if isinstance(thread, dict) else None
    return thread_id if isinstance(thread_id, str) else None, _result_shape(response)


def _start_turn(client: WsRpc, thread_id: str, prompt: str, timeout: float = 20) -> tuple[str | None, dict[str, Any]]:
    response = client.call("turn/start", {"threadId": thread_id, "input": [{"type": "text", "text": prompt}]}, timeout=timeout)
    turn_id: str | None = None
    if response.get("ok") and isinstance(response.get("result"), dict):
        turn = response["result"].get("turn")
        if isinstance(turn, dict) and isinstance(turn.get("id"), str):
            turn_id = turn["id"]
    return turn_id, _result_shape(response)


def owned_runtime_probe(codex: str, model: str) -> dict[str, Any]:
    salt = secrets.token_bytes(32)
    source_id = secrets.token_hex(16)
    runtime_id = secrets.token_hex(16)
    with tempfile.TemporaryDirectory(prefix="codex-monitor-ar-p0-") as directory:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        listener.close()
        process = subprocess.Popen(
            [codex, "app-server", "--listen", f"ws://127.0.0.1:{port}"],
            cwd=Path.cwd(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        client: WsRpc | None = None
        try:
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                try:
                    probe_connection = socket.create_connection(("127.0.0.1", port), timeout=0.2)
                    probe_connection.close()
                    break
                except OSError:
                    pass
                time.sleep(0.1)
            if process.poll() is not None:
                raise ProbeError("owned runtime exited before accepting connections")
            client = _tcp_client(port, "owned-client-1")
            initialize = _result_shape(client.initialize())

            account = {
                "account/read": _result_shape(client.call("account/read", {})),
                "account/rateLimits/read": _result_shape(client.call("account/rateLimits/read")),
                "account/usage/read": _result_shape(client.call("account/usage/read")),
            }
            first_id, first_start = _start_thread(client, model)
            second_id, second_start = _start_thread(client, model)
            known = {thread_id for thread_id in (first_id, second_id) if thread_id}
            turns: dict[str, Any] = {"first": {"thread_created": bool(first_id), "thread_start": first_start}, "second": {"thread_created": bool(second_id), "thread_start": second_start}}
            if first_id:
                _, turns["first"]["turn_start"] = _start_turn(client, first_id, "Run the command `pwd` once. Do not inspect files or modify anything. Then reply with exactly ARP0_OK.")
                client.drain(45)
            first_events_end = len(client.notifications)
            if second_id:
                _, turns["second"]["turn_start"] = _start_turn(client, second_id, "Reply with exactly ARP0_SECOND. Do not use tools and do not modify anything.")
                client.drain(45)

            # A safe, real interruption attempt. No approval response is ever sent by this probe.
            interrupt_thread, interrupt_start = _start_thread(client, model)
            if interrupt_thread:
                known.add(interrupt_thread)
            interruption: dict[str, Any] = {"thread_created": bool(interrupt_thread), "thread_start": interrupt_start}
            if interrupt_thread:
                interrupt_turn, interruption["turn_start"] = _start_turn(client, interrupt_thread, "Before replying, wait for 30 seconds without using tools or modifying anything, then reply ARP0_INTERRUPT.")
                interruption["turn_interrupt"] = _result_shape(client.call("turn/interrupt", {"threadId": interrupt_thread, "turnId": interrupt_turn}, timeout=20)) if interrupt_turn else {"ok": False, "reason": "turn_start_did_not_return_id"}
                client.drain(12)

            # A bounded approval observation attempt; server requests are recorded but never answered.
            approval_thread, approval_start = _start_thread(client, model, "untrusted")
            if approval_thread:
                known.add(approval_thread)
            approval: dict[str, Any] = {"thread_created": bool(approval_thread), "thread_start": approval_start, "monitor_or_probe_approval_response_sent": False}
            if approval_thread:
                approval_turn, approval["turn_start"] = _start_turn(client, approval_thread, "Run the harmless command `pwd` exactly once. Do not modify anything. If approval is needed, request it and wait.")
                client.drain(20)
                approval["turn_interrupt"] = _result_shape(client.call("turn/interrupt", {"threadId": approval_thread, "turnId": approval_turn}, timeout=20)) if approval_turn else {"ok": False, "reason": "turn_start_did_not_return_id"}
                client.drain(8)

            before_reconnect = _event_summary(client.notifications, known)
            approval_request_methods = Counter(request["method"] for request in client.server_requests)
            approval["server_request_methods"] = dict(sorted(approval_request_methods.items()))
            approval["approval_request_observed"] = any("requestApproval" in method for method in approval_request_methods)
            approval["authoritative_resolution_observed"] = before_reconnect["method_counts"].get("serverRequest/resolved", 0) > 0
            client.close()
            client = None
            process_survived_disconnect = process.poll() is None
            reconnect_client = _tcp_client(port, "owned-client-2")
            reconnect_initialize = _result_shape(reconnect_client.initialize())
            loaded = _result_shape(reconnect_client.call("thread/loaded/list", {"limit": 50}))
            read = _result_shape(reconnect_client.call("thread/read", {"threadId": first_id, "includeTurns": True})) if first_id else {"ok": False, "reason": "no-owned-thread"}
            reconnect_client.close()

            return {
                "source": {"source_kind": "monitorOwnedRuntime", "source_id_assigned": bool(source_id), "runtime_instance_id_assigned": bool(runtime_id), "transport": "loopback-websocket"},
                "initialize": initialize,
                "account_snapshot_shapes": account,
                "threads": turns,
                "interruption": interruption,
                "approval": approval,
                "lifecycle": before_reconnect,
                "reconnect": {"process_survived_client_disconnect": process_survived_disconnect, "initialize": reconnect_initialize, "loaded_list": loaded, "owned_thread_read": read, "active_reconstruction": "not_tested_no_authoritative_active_snapshot_after_reattach"},
                "failure_terminal": {"real": "not_observed", "fixture": "available_sanitized_mock_only"},
                "safety": {"reset_credit_consume_called": False, "desktop_thread_operations": [], "approval_response_sent": False, "raw_payload_retained": False},
            }
        finally:
            if client is not None:
                client.close()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=8)


def desktop_snapshot_probe(codex: str, socket_path: Path) -> dict[str, Any]:
    """Only the three architecture-authorized Desktop read operations."""
    if not socket_path.exists():
        return {"status": "NOT_TESTED", "reason": "managed_control_socket_absent", "operations": []}
    salt = secrets.token_bytes(32)
    client = _proxy_client(codex, socket_path, "desktop-snapshot-client")
    try:
        initialize = _result_shape(client.initialize())
        source_kinds = ["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"]
        loaded_before = client.call("thread/loaded/list", {"limit": 50})
        listed_before = client.call("thread/list", {"limit": 50, "sourceKinds": source_kinds})
        threads: list[dict[str, Any]] = []
        if listed_before.get("ok") and isinstance(listed_before.get("result"), dict):
            data = listed_before["result"].get("data")
            if isinstance(data, list):
                threads = [item for item in data if isinstance(item, dict)]
        ids = [item.get("id") for item in threads if isinstance(item.get("id"), str)]
        summaries: list[dict[str, Any]] = []
        for thread_id in ids[:3]:
            response = client.call("thread/read", {"threadId": thread_id, "includeTurns": True})
            if response.get("ok") and isinstance(response.get("result"), dict):
                thread = response["result"].get("thread")
                if isinstance(thread, dict):
                    status = thread.get("status")
                    turns = thread.get("turns")
                    summaries.append({
                        "status_shape": _type_shape(status),
                        "turn_history_returned": isinstance(turns, list),
                        "turn_count": len(turns) if isinstance(turns, list) else None,
                        "thread_shape": _type_shape({key: value for key, value in thread.items() if key not in {"id", "sessionId", "preview", "name", "path", "cwd", "turns"}}),
                    })
        time.sleep(1)
        loaded_after = client.call("thread/loaded/list", {"limit": 50})
        listed_after = client.call("thread/list", {"limit": 50, "sourceKinds": source_kinds})
        after_threads: list[dict[str, Any]] = []
        if listed_after.get("ok") and isinstance(listed_after.get("result"), dict):
            data = listed_after["result"].get("data")
            if isinstance(data, list):
                after_threads = [item for item in data if isinstance(item, dict)]
        after_ids = [item.get("id") for item in after_threads if isinstance(item.get("id"), str)]
        source_counts = Counter()
        raw_statuses = Counter()
        for thread in threads:
            source = thread.get("source")
            status = thread.get("status")
            if isinstance(source, dict) and isinstance(source.get("kind"), str):
                source_counts[source["kind"]] += 1
            if isinstance(status, dict) and isinstance(status.get("type"), str):
                raw_statuses[status["type"]] += 1
        return {
            "status": "PASS" if listed_before.get("ok") else "FAIL",
            "observation_mode": "snapshot_only_not_live",
            "initialize": initialize,
            "operations": ["thread/loaded/list", "thread/list", "thread/read(includeTurns:true)"],
            "loaded_before": _result_shape(loaded_before),
            "list_before": _result_shape(listed_before),
            "history_reads": summaries,
            "discovered_count": len(threads),
            "source_kind_counts": dict(sorted(source_counts.items())),
            "raw_status_counts": dict(sorted(raw_statuses.items())),
            "before_digest": _digest([value for value in ids if isinstance(value, str)], salt),
            "after_digest": _digest([value for value in after_ids if isinstance(value, str)], salt),
            "refresh_changed": sorted(ids) != sorted(after_ids),
            "loaded_after": _result_shape(loaded_after),
            "list_after": _result_shape(listed_after),
            "safety": {"thread_resume_start_fork_called": False, "raw_identity_or_content_retained": False},
        }
    finally:
        client.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex", default="codex")
    parser.add_argument("--model", default="gpt-5.6-terra")
    parser.add_argument("--desktop-socket", type=Path, default=Path.home() / ".codex/app-server-control/app-server-control.sock")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    report: dict[str, Any] = {
        "probe": "AR-P0 disposable Hybrid capability validation",
        "started_at": started,
        "model_requested": args.model,
        "owned_runtime": None,
        "desktop_snapshot": None,
        "safety": {"reset_credit_mutation": "NOT_RUN", "no_production_modules": True, "no_desktop_lifecycle_operations": True},
    }
    try:
        report["owned_runtime"] = owned_runtime_probe(args.codex, args.model)
    except (OSError, ProbeError, subprocess.SubprocessError) as error:
        report["owned_runtime"] = {"status": "FAIL", "error_type": type(error).__name__, "raw_error_retained": False}
    try:
        report["desktop_snapshot"] = desktop_snapshot_probe(args.codex, args.desktop_socket)
    except (OSError, ProbeError) as error:
        report["desktop_snapshot"] = {"status": "FAIL", "error_type": type(error).__name__, "raw_error_retained": False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "owned_runtime_status": report["owned_runtime"].get("status", "COMPLETE") if isinstance(report["owned_runtime"], dict) else "UNKNOWN", "desktop_snapshot_status": report["desktop_snapshot"].get("status", "UNKNOWN") if isinstance(report["desktop_snapshot"], dict) else "UNKNOWN"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
