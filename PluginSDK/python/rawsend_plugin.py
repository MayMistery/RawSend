"""Minimal dependency-free RawSend process-plugin SDK."""

from __future__ import annotations

import json
import sys
from typing import Any, Callable

MAX_MESSAGE_BYTES = 16 * 1024 * 1024


class ProtocolError(RuntimeError):
    pass


def _read_message() -> dict[str, Any]:
    headers: dict[str, str] = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            raise EOFError
        if line in (b"\r\n", b"\n"):
            break
        name, separator, value = line.decode("ascii").partition(":")
        if not separator:
            raise ProtocolError("malformed header")
        headers[name.strip().lower()] = value.strip()
    length = int(headers.get("content-length", "-1"))
    if length < 0 or length > MAX_MESSAGE_BYTES:
        raise ProtocolError("invalid Content-Length")
    body = sys.stdin.buffer.read(length)
    if len(body) != length:
        raise EOFError
    return json.loads(body)


def _write_message(message: dict[str, Any]) -> None:
    body = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode()
    if len(body) > MAX_MESSAGE_BYTES:
        raise ProtocolError("message too large")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode())
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


class Host:
    def __init__(self) -> None:
        self._next_id = 1_000_000

    def call(self, method: str, params: Any = None) -> Any:
        request_id = self._next_id
        self._next_id += 1
        _write_message(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params,
            }
        )
        while True:
            response = _read_message()
            if response.get("id") != request_id:
                raise ProtocolError("unexpected nested message")
            if "error" in response:
                raise ProtocolError(response["error"].get("message", "host call failed"))
            return response.get("result")


Handler = Callable[[str, Any, Host], Any]


def serve(handler: Handler) -> None:
    host = Host()
    while True:
        try:
            request = _read_message()
        except EOFError:
            return
        request_id = request.get("id")
        try:
            result = handler(request["method"], request.get("params"), host)
            response = {"jsonrpc": "2.0", "id": request_id, "result": result}
        except Exception as exc:  # plugin errors must be returned, not printed to stdout
            response = {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32000, "message": str(exc)},
            }
        _write_message(response)
