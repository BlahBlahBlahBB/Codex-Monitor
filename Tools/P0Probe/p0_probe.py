#!/usr/bin/env python3
"""P0-only safe primitives for a passive Codex app-server observer."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import select
import socket
import struct
import time
from pathlib import Path
from typing import Any

SENSITIVE_KEY = re.compile(r"(?:^|[_-])(token|access[_-]?token|refresh[_-]?token|authorization|cookie|secret|api[_-]?key|bearer)(?:$|[_-])", re.I)
PII_KEY = re.compile(r"(?:email|account(?:[_-]?id)?|user(?:[_-]?id)?|message|prompt|title|command|path|file(?:[_-]?content)?|cwd)", re.I)
USAGE_KEY = re.compile(r"(?:tokenUsage|tokens|inputTokens|cachedInputTokens|outputTokens|reasoningOutputTokens|totalTokens)", re.I)
HOME_PATH = re.compile(r"/Users/[^/\"'\\s]+")


def sanitize(value: Any, key: str = "") -> Any:
    """Redact credential/PII values while retaining numeric token-usage allowlist."""
    if SENSITIVE_KEY.search(key) and not USAGE_KEY.search(key):
        return "<REDACTED>"
    if PII_KEY.search(key):
        return "<REDACTED>"
    if isinstance(value, dict):
        return {k: sanitize(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize(v, key) for v in value]
    if isinstance(value, str):
        return HOME_PATH.sub("<HOME>", value)
    return value


def sanitized_json(value: Any) -> str:
    return json.dumps(sanitize(value), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def socket_status(path: Path) -> dict[str, str]:
    return {
        "socket": "<CODEX_HOME>/app-server-control/app-server-control.sock",
        "status": "present" if path.exists() and path.is_socket() else "absent",
        "policy": "do_not_start_or_restart_daemon",
    }


def merge_sparse_rate_limits(snapshot: dict[str, Any], update: dict[str, Any]) -> dict[str, Any]:
    """Preserve omitted fields; this is a shape-agnostic fixture-test helper."""
    merged = dict(snapshot)
    for key, value in update.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_sparse_rate_limits(merged[key], value)
        else:
            merged[key] = value
    return merged


def accept_current_epoch(event_epoch: int, current_epoch: int) -> bool:
    """Fixture guard: stale connection events must not mutate current state."""
    return event_epoch == current_epoch


def export_fixture(payload: Any, destination: Path) -> str:
    """Write only a sanitized fixture and return its SHA-256."""
    rendered = sanitized_json(payload)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(rendered, encoding="utf-8")
    return hashlib.sha256(rendered.encode("utf-8")).hexdigest()


class ProtocolError(RuntimeError):
    """A bounded P0-only protocol failure with no payload retention."""


def _read_exact(connection: socket.socket, length: int) -> bytes:
    chunks: list[bytes] = []
    remaining = length
    while remaining:
        chunk = connection.recv(remaining)
        if not chunk:
            raise ProtocolError("connection closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _send_ws_text(connection: socket.socket, value: dict[str, Any]) -> None:
    """Send one client-masked RFC 6455 text frame."""
    payload = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    length = len(payload)
    if length < 126:
        header = bytes((0x81, 0x80 | length))
    elif length <= 0xFFFF:
        header = bytes((0x81, 0x80 | 126)) + struct.pack("!H", length)
    else:
        header = bytes((0x81, 0x80 | 127)) + struct.pack("!Q", length)
    mask = os.urandom(4)
    masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    connection.sendall(header + mask + masked)


def _read_ws_message(connection: socket.socket) -> dict[str, Any] | None:
    """Read one unfragmented server text frame; discard ping/pong safely."""
    first, second = _read_exact(connection, 2)
    opcode = first & 0x0F
    length = second & 0x7F
    masked = bool(second & 0x80)
    if length == 126:
        length = struct.unpack("!H", _read_exact(connection, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", _read_exact(connection, 8))[0]
    mask = _read_exact(connection, 4) if masked else b""
    payload = _read_exact(connection, length)
    if masked:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    if opcode == 0x8:
        return None
    if opcode == 0x9:
        connection.sendall(bytes((0x8A, len(payload))) + payload)
        return None
    if opcode != 0x1 or not (first & 0x80):
        raise ProtocolError("unsupported websocket frame")
    try:
        decoded = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProtocolError("invalid websocket JSON") from error
    if not isinstance(decoded, dict):
        raise ProtocolError("non-object protocol message")
    return decoded


def _message_summary(message: dict[str, Any]) -> dict[str, Any]:
    """Retain method/result shape only; never retain message values or IDs."""
    result = message.get("result")
    params = message.get("params")
    summary: dict[str, Any] = {}
    if "id" in message:
        summary["kind"] = "response"
        summary["has_error"] = "error" in message
        summary["result_is_object"] = isinstance(result, dict)
        summary["result_keys"] = sorted(result) if isinstance(result, dict) else []
    else:
        summary["kind"] = "notification"
        summary["method"] = message.get("method") if isinstance(message.get("method"), str) else "<UNKNOWN>"
        summary["params_is_object"] = isinstance(params, dict)
        summary["param_keys"] = sorted(params) if isinstance(params, dict) else []
        if isinstance(params, dict):
            summary["identity_fields_present"] = sorted(
                key for key in params if key.lower() in {"threadid", "turnid", "itemid", "requestid"}
            )
    return summary


def observe(socket_path: Path, duration: float) -> dict[str, Any]:
    """Perform a passive initialize/read sequence and optionally observe events."""
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(5)
    transcript: list[dict[str, Any]] = []
    try:
        connection.connect(str(socket_path))
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        handshake = (
            "GET / HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        ).encode("ascii")
        connection.sendall(handshake)
        response = b""
        while b"\r\n\r\n" not in response:
            response += connection.recv(1024)
            if len(response) > 16384:
                raise ProtocolError("oversized websocket handshake")
        status_line = response.split(b"\r\n", 1)[0]
        if b" 101 " not in status_line:
            raise ProtocolError("websocket upgrade rejected")

        request_id = 1
        _send_ws_text(connection, {
            "method": "initialize",
            "id": request_id,
            "params": {
                "clientInfo": {"name": "codex-monitor-p0-probe", "title": "Codex Monitor P0 Probe", "version": "0D1"},
                "capabilities": {"experimentalApi": False, "requestAttestation": False, "optOutNotificationMethods": None, "extensions": None},
            },
        })
        while True:
            message = _read_ws_message(connection)
            if message is None:
                raise ProtocolError("connection closed during initialize")
            transcript.append(_message_summary(message))
            if message.get("id") == request_id:
                if "error" in message:
                    raise ProtocolError("initialize returned an error")
                break
        _send_ws_text(connection, {"method": "initialized"})

        requests: list[tuple[str, dict[str, Any] | None]] = [
            ("account/read", {}),
            ("account/rateLimits/read", None),
            ("account/usage/read", None),
            ("thread/loaded/list", {"limit": 50}),
        ]
        completed: list[str] = []
        for method, params in requests:
            request_id += 1
            request: dict[str, Any] = {"method": method, "id": request_id}
            if params is not None:
                request["params"] = params
            _send_ws_text(connection, request)
            while True:
                message = _read_ws_message(connection)
                if message is None:
                    raise ProtocolError(f"connection closed during {method}")
                transcript.append(_message_summary(message))
                if message.get("id") == request_id:
                    completed.append(method if "error" not in message else f"{method}:error")
                    break

        deadline = time.monotonic() + max(duration, 0)
        while time.monotonic() < deadline:
            ready, _, _ = select.select([connection], [], [], min(0.5, deadline - time.monotonic()))
            if not ready:
                continue
            message = _read_ws_message(connection)
            if message is None:
                break
            transcript.append(_message_summary(message))
        return {
            "socket": "<CODEX_HOME>/app-server-control/app-server-control.sock",
            "websocket_upgrade": "PASS",
            "initialize": "PASS",
            "initialized": "PASS",
            "read_requests": completed,
            "events": transcript,
            "observer_window_seconds": round(max(duration, 0), 3),
        }
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["status", "observe"])
    parser.add_argument("--socket", required=True, type=Path)
    parser.add_argument("--duration", type=float, default=0.0, help="Passive post-read observation window in seconds")
    parser.add_argument("--output", type=Path, help="Optional destination for a sanitized observation summary")
    args = parser.parse_args()
    if args.command == "status":
        print(json.dumps(socket_status(args.socket), ensure_ascii=False, sort_keys=True))
        return 0
    try:
        result = observe(args.socket, args.duration)
        if args.output is not None:
            digest = export_fixture(result, args.output)
            result = {"sanitized_summary": str(args.output), "sha256": digest}
        print(sanitized_json(result), end="")
    except (OSError, ProtocolError) as error:
        print(json.dumps({"status": "FAIL", "error_type": type(error).__name__}, sort_keys=True))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
