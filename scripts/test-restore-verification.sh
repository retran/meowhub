#!/usr/bin/env bash
# Proves spec 0001 T15's done-when directly: a good run reports success; a
# sabotaged one reports failure and is not counted as good. Runs a real
# backup into a throwaway repository, verifies it (expect PASS), corrupts
# the snapshot on disk, and verifies again (expect FAILED, and no
# heartbeat). Requires the stack to be up (task up).
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps postgres --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: postgres is not running (run 'task up' first)"
  exit 0
fi

WORK_DIR="$(mktemp -d)"

# A stub Telegram endpoint: this test cares about the mechanism, not real
# credentials or a real chat, so it points scripts/telegram-report.sh at a
# throwaway local responder that always answers 200 (ADR 0015).
python3 - "$WORK_DIR/stub.log" <<'PY' &
import http.server
import socketserver
import sys

log_path = sys.argv[1]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        with open(log_path, "ab") as f:
            f.write(body + b"\n")
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass

class Server(socketserver.TCPServer):
    allow_reuse_address = True

with Server(("127.0.0.1", 8791), Handler) as httpd:
    httpd.serve_forever()
PY
STUB_PID=$!

cleanup() {
  kill "$STUB_PID" 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

export RESTIC_REPOSITORY="${WORK_DIR}/repo"
export HEARTBEAT_BACKUP_URL="http://127.0.0.1:8791/"
export HEARTBEAT_RESTORE_VERIFY_URL="http://127.0.0.1:8791/heartbeat"
export TELEGRAM_API_BASE_URL="http://127.0.0.1:8791/sendMessage"
unset BACKUP_OFFSITE_REPOSITORY BACKUP_OFFSITE_ACCESS_KEY BACKUP_OFFSITE_SECRET_KEY 2>/dev/null || true

for i in $(seq 1 20); do
  curl -sS --max-time 1 "http://127.0.0.1:8791/" >/dev/null 2>&1 && break
  sleep 0.5
done

bash scripts/backup.sh >&2

if ! bash scripts/verify-restore.sh; then
  echo "FAILED: a good backup should verify cleanly"
  exit 1
fi
if ! grep -q "passed" "${WORK_DIR}/stub.log"; then
  echo "FAILED: a good run did not report success to Telegram"
  exit 1
fi
echo "PASS: a good run verifies and reports success"

# Sabotage: truncate every pack file to half its size — appending garbage
# is not enough, since restic reads each blob by the exact offset and
# length recorded in its index and simply ignores anything past it.
# Truncating actually destroys blob content, the same intent as the
# file-integrity and dedup-logic sabotage tests elsewhere in this suite.
# restic's pack files are read-only by design; writable before corrupting,
# same as scripts/test-file-storage.sh does to its own immutable files.
find "${RESTIC_REPOSITORY}/data" -type f -exec chmod 644 {} \;
find "${RESTIC_REPOSITORY}/data" -type f | while read -r f; do
  size="$(wc -c < "$f")"
  half=$((size / 2))
  dd if="$f" of="${f}.half" bs=1 count="$half" 2>/dev/null
  mv "${f}.half" "$f"
done

: > "${WORK_DIR}/stub.log"
if bash scripts/verify-restore.sh 2>/dev/null; then
  echo "FAILED: verification should have failed against a corrupted repository"
  exit 1
fi
if ! grep -q "FAILED" "${WORK_DIR}/stub.log"; then
  echo "FAILED: a sabotaged run did not report failure to Telegram"
  exit 1
fi
if grep -q "passed" "${WORK_DIR}/stub.log"; then
  echo "FAILED: a sabotaged run must never be counted as good"
  exit 1
fi
echo "PASS: a sabotaged run fails verification and is reported, never counted as good"
