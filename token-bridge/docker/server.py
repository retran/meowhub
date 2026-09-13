#!/usr/bin/env python3
# The token bridge (ADR 0041, spec 0002 T7). Sits behind Authentik's
# forward-auth and in front of PostgREST: given the forward-auth headers
# for an already-authenticated request, it resolves the asserted identity
# to a member via member_identity, decides the role from group membership,
# and mints a short-lived PostgREST JWT — or refuses outright if the
# subject has no resolvable member (R15a's "no resolvable member id" case
# is a refusal to mint, never a token PostgREST would later reject).
#
# Stateless and reconstructed on every request from Authentik's live
# session: a revoked passkey or a deactivated member (ADR 0026) stops
# minting new tokens on the very next request, nothing waits for one to
# expire on its own.
import base64
import hashlib
import hmac
import http.server
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import psycopg2

JWT_SECRET = os.environ["PGRST_JWT_SECRET"]
TOKEN_TTL_SECONDS = 300

DB_DSN = (
    "host=postgres "
    f"dbname={os.environ['POSTGRES_DB']} "
    f"user={os.environ['POSTGRES_SUPERUSER']} "
    f"password={os.environ['POSTGRES_SUPERUSER_PASSWORD']}"
)

AUTHENTIK_API_BASE_URL = os.environ["AUTHENTIK_API_BASE_URL"]
AUTHENTIK_API_TOKEN = os.environ["AUTHENTIK_API_TOKEN"]


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def mint_jwt(role: str, member_id: int) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64url(
        json.dumps(
            {
                "role": role,
                "member_id": member_id,
                "exp": int(time.time()) + TOKEN_TTL_SECONDS,
            }
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    signature = b64url(hmac.new(JWT_SECRET.encode(), signing_input, hashlib.sha256).digest())
    return f"{header}.{payload}.{signature}"


def fetch_groups(provider_subject):
    # Authentik's forward-auth response carries X-Authentik-Groups, but
    # spec 0002 T10 found it unreliable: it depends on which OAuth scopes
    # happened to be negotiated for a given request, and can be entirely
    # absent for a user who does hold the group. A direct, server-to-server
    # API call using the token bridge's own service account (its own
    # superuser group, authentik/blueprints/04-token-bridge-account.yaml)
    # is not subject to that at all — the authoritative source instead.
    if not provider_subject:
        return []

    # Authentik's user list endpoint has no filter for "uid" (the header's
    # value — a deterministic hash of the user, distinct from the "uuid"
    # primary key it does let you filter by) — confirmed empirically: an
    # unrecognised query param is silently ignored rather than rejected,
    # so filtering client-side over the full list is the only option. A
    # household is a handful of accounts; this is not a scale problem.
    req = urllib.request.Request(
        f"{AUTHENTIK_API_BASE_URL}/api/v3/core/users/",
        headers={"Authorization": f"Bearer {AUTHENTIK_API_TOKEN}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = json.load(resp)
    except urllib.error.URLError:
        return []

    for user in body.get("results", []):
        if user.get("uid") == provider_subject:
            return [g["name"] for g in user.get("groups_obj", [])]
    return []


def resolve_member(provider_subject, groups):
    if not provider_subject:
        return None

    conn = psycopg2.connect(DB_DSN)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "select mi.member_id, m.active from member_identity mi"
                " join member m on m.id = mi.member_id"
                " where mi.provider_subject = %s",
                (provider_subject,),
            )
            row = cur.fetchone()
    finally:
        conn.close()

    # A deactivated member (ADR 0026, A17) stops minting on the very next
    # request — Authentik's own account is disabled too, so this only
    # matters for the narrow window between deactivation and that syncing.
    if row is None or not row[1]:
        return None
    member_id = row[0]

    # ADR 0006's admin/household groups map onto R7's two roles. Neither
    # recognised group present is treated the same as no member at all —
    # refuse to mint, never guess a role.
    if "admin" in groups:
        return "hh_admin", member_id
    if "household" in groups:
        return "hh_member", member_id
    return None


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        subject = self.headers.get("X-Authentik-Uid", "")
        path = urllib.parse.urlsplit(self.path).path

        # n8n and Uptime Kuma (spec 0002 T10, R17a) are admin-only but need
        # no PostgREST token — Caddy calls this as its own forward_auth
        # check, wanting only a 200/403 verdict on group membership.
        prefix = "/require-group/"
        if path.startswith(prefix):
            required_group = path[len(prefix) :]
            groups = fetch_groups(subject)
            self.send_response(200 if required_group in groups else 403)
            self.end_headers()
            return

        groups = fetch_groups(subject)
        result = resolve_member(subject, groups)
        if result is None:
            self.send_response(403)
            self.end_headers()
            return

        role, member_id = result
        token = mint_jwt(role, member_id)
        self.send_response(200)
        self.send_header("Authorization", f"Bearer {token}")
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    with http.server.ThreadingHTTPServer(("0.0.0.0", 8095), Handler) as httpd:
        httpd.serve_forever()
