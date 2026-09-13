#!/usr/bin/env bash
# R16c: a documented way to obtain a PostgREST token locally, so row-level
# security can be exercised by hand as well as by the suite, without ever
# putting one in a browser (R16a) or letting the data API be reachable from
# anywhere but the proxy path in production (R16b) — this mints the same
# short-lived HS256 shape the token bridge mints (ADR 0041), for use only
# from inside the compose network (scripts/authentik-curl.sh's "borrow the
# target's network namespace" trick, or a script run on the docker host).
#
# Usage: scripts/mint-local-jwt.sh <role> [member_id] [ttl_seconds]
set -euo pipefail

: "${PGRST_JWT_SECRET:?PGRST_JWT_SECRET not set}"

ROLE="${1:?usage: mint-local-jwt.sh <role> [member_id] [ttl_seconds]}"
MEMBER_ID="${2:-}"
TTL="${3:-300}"

python3 -c "
import base64, hashlib, hmac, json, sys, time

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

role = sys.argv[1]
member_id = sys.argv[2]
ttl = int(sys.argv[3])
secret = sys.argv[4]

payload = {'role': role, 'exp': int(time.time()) + ttl}
if member_id:
    payload['member_id'] = int(member_id)

header = b64url(json.dumps({'alg': 'HS256', 'typ': 'JWT'}).encode())
body = b64url(json.dumps(payload).encode())
signing_input = f'{header}.{body}'.encode()
signature = b64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
print(f'{signing_input.decode()}.{signature}')
" "$ROLE" "$MEMBER_ID" "$TTL" "$PGRST_JWT_SECRET"
