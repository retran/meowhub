#!/usr/bin/env python3
# The model gateway stub (spec 0001 T18, R17, ADR 0015): a local responder
# with the same OpenAI-compatible shape OpenRouter itself uses, so anything
# that calls OPENROUTER_BASE_URL cannot tell the difference except by the
# "provider" field this stub deliberately stamps on every response — the
# one thing a real call to OpenRouter would never contain, and the only
# thing a test needs to check to prove which one actually answered.
import http.server
import json


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        requested_model = body.get("model", "unknown")

        response = {
            "id": "stub-completion",
            "provider": "meowhub-local-stub",
            "model": requested_model,
            "choices": [
                {
                    "index": 0,
                    "finish_reason": "stop",
                    "message": {
                        "role": "assistant",
                        "content": "This is the local model gateway stub — no external request was made.",
                    },
                }
            ],
        }
        payload = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"status":"ok","provider":"meowhub-local-stub"}')

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    with http.server.ThreadingHTTPServer(("0.0.0.0", 8090), Handler) as httpd:
        httpd.serve_forever()
