#!/usr/bin/env python3
# Drives a REAL sign-in through the entire proxy path (spec 0002 T9) the
# way a browser would: Authentik's flow executor, its forward-auth check,
# the OAuth2 authorize/callback dance for this application, and finally
# the request that reaches PostgREST through the token bridge. Standard
# library only, run from the host against the proxy's published port —
# not a container trick, because this has to be the exact path a real
# browser takes.
#
# A known Authentik limitation (github.com/goauthentik/authentik/issues/12503):
# on a non-standard HTTPS port, the OAuth authorize redirect it generates
# for itself is missing the scheme and port (comes out as a bare
# "http://host/..." instead of "https://host:port/..."). A real browser
# hits this too — this is not a meowhub misconfiguration. FixRedirect
# below corrects it client-side, which is what lets this script prove the
# rest of the chain is genuinely correct without waiting on an upstream
# fix; local-development.md documents the same correction for a human
# hitting it in a browser.
#
# Usage: authentik-e2e-signin.py <proxy-base-url> <ca-cert-path> <path> <username> <password>
import http.cookiejar
import json
import ssl
import sys
import urllib.request
from urllib.parse import urlsplit, urlunsplit

PROXY_BASE, CA, PATH, USERNAME, PASSWORD = sys.argv[1:6]
FLOW = "default-authentication-flow"
base_parts = urlsplit(PROXY_BASE)


class FixRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parts = urlsplit(newurl)
        fixed = urlunsplit((base_parts.scheme, base_parts.netloc, parts.path, parts.query, ""))
        return super().redirect_request(req, fp, code, msg, headers, fixed)


ctx = ssl.create_default_context(cafile=CA)
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(cj),
    urllib.request.HTTPSHandler(context=ctx),
    FixRedirect(),
)


def csrf():
    for cookie in cj:
        if cookie.name == "authentik_csrf":
            return cookie.value
    return None


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(PROXY_BASE + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    request.add_header("Accept", "application/json")
    token = csrf()
    if token:
        request.add_header("X-authentik-CSRF", token)
    with opener.open(request) as response:
        return response.status, response.read()


status, body = call("GET", f"/api/v3/flows/executor/{FLOW}/?query=")
print(f"start: {status} {json.loads(body).get('component')}")

status, body = call("POST", f"/api/v3/flows/executor/{FLOW}/", {"uid_field": USERNAME})
print(f"identification: {status} {json.loads(body).get('component')}")

status, body = call("POST", f"/api/v3/flows/executor/{FLOW}/", {"password": PASSWORD})
print(f"password: {status} {json.loads(body).get('component')}")

request = urllib.request.Request(PROXY_BASE + PATH, method="GET")
with opener.open(request) as response:
    print(f"{PATH} status: {response.status}")
    print(response.read().decode())
