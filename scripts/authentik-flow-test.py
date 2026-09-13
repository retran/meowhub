#!/usr/bin/env python3
# Drives Authentik's own flow-executor API the way its login page does —
# identification, then password, then whatever the flow decides next
# (spec 0002 T6). Standard library only: this runs inside a throwaway
# container with no extra dependencies (scripts/authentik-curl.sh's
# network-namespace trick).
#
# Usage: authentik-flow-test.py <username> <password> <max-attempts>
# Submits <password> repeatedly (up to <max-attempts> times) against the
# default authentication flow for <username> and prints each step's
# component so a caller can see exactly where the flow ended.
import http.cookiejar
import json
import sys
import urllib.request

BASE = "http://localhost:9000"
FLOW = "default-authentication-flow"

username, password, max_attempts = sys.argv[1], sys.argv[2], int(sys.argv[3])

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))


def csrf_token():
    for cookie in cj:
        if cookie.name == "authentik_csrf":
            return cookie.value
    return None


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    request.add_header("Accept", "application/json")
    token = csrf_token()
    if token:
        request.add_header("X-authentik-CSRF", token)
    with opener.open(request) as response:
        return json.loads(response.read())


step = call("GET", f"/api/v3/flows/executor/{FLOW}/?query=")
print(f"start: {step.get('component')}")

step = call("POST", f"/api/v3/flows/executor/{FLOW}/", {"uid_field": username})
print(f"identification: {step.get('component')}")

for attempt in range(1, max_attempts + 1):
    step = call("POST", f"/api/v3/flows/executor/{FLOW}/", {"password": password})
    component = step.get("component")
    print(f"attempt {attempt}: {component}")
    if component != "ak-stage-password":
        break
