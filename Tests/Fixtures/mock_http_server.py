#!/usr/bin/env python3
import http.server
import json
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    remaining = int(sys.argv[1])

    def do_GET(self):
        body = json.dumps(
            {"secret": "mock-sensitive", "request_path": self.path},
            separators=(",", ":"),
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        Handler.remaining -= 1
        if Handler.remaining <= 0:
            self.server.shutdown_requested = True

    def log_message(self, format, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.timeout = 0.1
print(server.server_port, flush=True)
while not getattr(server, "shutdown_requested", False):
    server.handle_request()
server.server_close()
