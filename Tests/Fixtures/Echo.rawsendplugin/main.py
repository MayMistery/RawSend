#!/usr/bin/env python3
import json
import sys


def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            raise EOFError
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    length = int(headers["content-length"])
    return json.loads(sys.stdin.buffer.read(length))


def write_message(message):
    body = json.dumps(message, separators=(",", ":")).encode()
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    sys.stdout.buffer.flush()


def host_call(request_id, method, params=None):
    write_message(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }
    )
    response = read_message()
    if response.get("id") != request_id or "error" in response:
        raise RuntimeError("host call failed")
    return response.get("result")


while True:
    try:
        request = read_message()
    except EOFError:
        break
    request_id = request["id"]
    method = request["method"]
    params = request.get("params") or {}
    try:
        if method == "initialize":
            host_call(900001, "host.info")
            result = {"initialized": True}
        elif method == "send.plan":
            host_call(900002, "ui.status.set", {"message": "fixture planned"})
            fields = params["request"]["fields"]
            variants = []
            if fields:
                variants.append(
                    {
                        "id": "fixture-variant",
                        "label": "Fixture mutation",
                        "scheme": "http",
                        "mutations": [
                            {
                                "target_id": fields[0]["id"],
                                "replacement": "http://callback.fixture/",
                            }
                        ],
                        "metadata": {"fixture": "true"},
                    }
                )
            result = {
                "variants": variants,
                "annotations": [],
                "findings": [],
                "status_message": "planned",
            }
        elif method == "exchange.completed":
            response = params["exchange"]["response"]
            result = {
                "variants": [],
                "annotations": [
                    {
                        "id": "fixture-annotation",
                        "response_id": response["id"],
                        "value": "mock-sensitive",
                        "location": None,
                        "length": None,
                        "line": None,
                        "severity": "high",
                        "title": "Fixture annotation",
                        "message": "Fixture matched a response value",
                    }
                ],
                "findings": [
                    {
                        "id": "fixture-finding",
                        "plugin_id": None,
                        "response_id": response["id"],
                        "title": "Fixture finding",
                        "summary": "Process plugin completed end-to-end",
                        "severity": "high",
                        "status": "confirmed",
                        "details": {},
                    }
                ],
                "status_message": "analyzed",
            }
        else:
            result = {
                "variants": [],
                "annotations": [],
                "findings": [],
                "status_message": None,
            }
        write_message({"jsonrpc": "2.0", "id": request_id, "result": result})
    except Exception as error:
        write_message(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32000, "message": str(error)},
            }
        )
