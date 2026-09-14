#!/usr/bin/env bash
# Runs prompts/agent/v1/golden-set.json against a real model (ADR 0025,
# spec 0004 T13) -- never the stub, and never part of `task test`,
# because it costs real money and is run deliberately when the prompt
# changes.
#
# What it exercises is the agent's *turn*: given the system prompt, the
# household's context and the real tool declarations, which tool does it
# reach for, does it ask rather than guess, does it refuse what no tool
# answers, and -- once tool results are in hand -- does it report the
# figure it was given rather than one of its own (A14).
#
# Scores go to stdout and to the file named by the second argument, so
# they can be recorded in the commit that changed the prompt.
set -euo pipefail

: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY must be set to a real key -- this script refuses to run against the stub}"
: "${OPENROUTER_BASE_URL:?OPENROUTER_BASE_URL must be set}"
: "${MODEL_AGENT:?MODEL_AGENT must name a real model -- refusing to run the golden set against an unset or stub model}"

if [[ "$OPENROUTER_BASE_URL" == *model-gateway-stub* ]]; then
  echo "REFUSING: OPENROUTER_BASE_URL points at the local stub, not a real model (ADR 0015 -- the stub is for workflow tests, never for the golden set)."
  exit 1
fi

GOLDEN_SET="${1:-prompts/agent/v1/golden-set.json}"
OUT="${2:-prompts/agent/v1/golden-set-results.json}"

python3 - "$GOLDEN_SET" "$OUT" prompts/agent/v1/system.md tools <<'PYEOF'
import json, os, re, sys, urllib.request, glob

golden_set_path, out_path, system_prompt_path, tools_dir = sys.argv[1:5]

golden = json.load(open(golden_set_path))
system_prompt = open(system_prompt_path).read()

# The tool list is the declarations themselves, exactly as the loop
# builds it (ADR 0046): the registry is the agent's capability, and a
# golden set run against a different list would be testing a different
# agent.
tools = []
for path in sorted(glob.glob(os.path.join(tools_dir, "*.json"))):
    decl = json.load(open(path))
    tools.append({
        "type": "function",
        "function": {
            "name": decl["name"],
            "description": decl["purpose"],
            "parameters": decl["input_schema"],
        },
    })

base_url = os.environ["OPENROUTER_BASE_URL"]
api_key = os.environ["OPENROUTER_API_KEY"]
model = os.environ["MODEL_AGENT"]

CONTEXT = {
    "member_id": 1, "is_admin": False, "default_payment_account": "ABN AMRO",
    "questions_already_asked": [], "language": "en", "timezone": "Europe/Amsterdam",
    "timezone_set": True, "currency": "EUR", "today": "2026-09-14", "memory": [],
}


def call_model(case):
    context = dict(CONTEXT, language=case.get("language", "en"))
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "system", "content": f"Context for this exchange: {json.dumps(context)}"},
    ]
    for turn in case.get("history", []):
        messages.append({"role": turn["role"], "content": turn["text"]})
    messages.append({"role": "user", "content": case["text"]})

    # A case may hand the agent tool results it has already "called",
    # which is how the reply-side expectations (A14) are exercised
    # without re-running the whole loop.
    for i, tr in enumerate(case.get("tool_results", [])):
        call_id = f"call_{i}"
        messages.append({"role": "assistant", "tool_calls": [{
            "id": call_id, "type": "function",
            "function": {"name": tr["tool"], "arguments": json.dumps(tr.get("arguments", {}))},
        }]})
        messages.append({"role": "tool", "tool_call_id": call_id, "name": tr["tool"],
                         "content": json.dumps(tr["result"])})

    body = json.dumps({"model": model, "messages": messages, "tools": tools}).encode()
    req = urllib.request.Request(
        f"{base_url}/chat/completions", data=body, method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        parsed = json.loads(resp.read())
    return parsed["choices"][0]["message"]


def is_russian(text):
    return any("Ѐ" <= ch <= "ӿ" for ch in text or "")


def check(case, message):
    expect = case["expect"]
    problems = []
    calls = message.get("tool_calls") or []
    names = [(c.get("function") or {}).get("name") for c in calls]
    content = (message.get("content") or "").strip()

    if "tool_in" in expect:
        if not names:
            problems.append(f"expected one of {expect['tool_in']}, no tool was called (said: {content!r})")
        elif names[0] not in expect["tool_in"]:
            problems.append(f"expected one of {expect['tool_in']}, called {names[0]}")
    if "tool_args_contain" in expect and calls:
        try:
            args = json.loads((calls[0].get("function") or {}).get("arguments") or "{}")
        except json.JSONDecodeError:
            args = {}
        for key, want in expect["tool_args_contain"].items():
            if args.get(key) != want:
                problems.append(f"{key}: expected {want!r}, called with {args.get(key)!r}")
    if expect.get("no_tool_call") and names:
        problems.append(f"expected no tool call, called {names}")
    if expect.get("asks_question"):
        if not content.rstrip().endswith("?"):
            problems.append(f"expected a question, got {content!r}")
        elif content.count("?") > 1:
            problems.append(f"expected exactly one question, got {content!r}")
    for want in expect.get("reply_contains", []):
        if want not in content:
            problems.append(f"reply is missing {want!r}: got {content!r}")
    for unwanted in expect.get("reply_excludes", []):
        if unwanted in content:
            problems.append(f"reply carries the raw minor-unit figure {unwanted!r}: {content!r}")
    if "reply_matches" in expect and not re.search(expect["reply_matches"], content):
        problems.append(f"reply does not match /{expect['reply_matches']}/: {content!r}")
    if expect.get("language") == "ru" and content and not is_russian(content):
        problems.append(f"expected a Russian reply, got {content!r}")
    return problems


results = []
passed = 0
for case in golden["cases"]:
    try:
        message = call_model(case)
        problems = check(case, message)
    except Exception as e:                      # noqa: BLE001 -- a failed call is a failed case
        message = None
        problems = [f"error calling model: {e}"]
    ok = not problems
    passed += 1 if ok else 0
    results.append({
        "id": case["id"], "text": case["text"], "ok": ok,
        "called": [(c.get("function") or {}).get("name") for c in ((message or {}).get("tool_calls") or [])],
        "said": ((message or {}).get("content") or "").strip(),
        "problems": problems,
    })
    print(f"{'PASS' if ok else 'FAIL'}: {case['id']} — {case['text']}")
    for p in problems:
        print(f"       {p}")

json.dump({
    "prompt": golden["prompt"], "version": golden["version"], "model": model,
    "total": len(golden["cases"]), "passed": passed, "results": results,
}, open(out_path, "w"), indent=2, ensure_ascii=False)

print(f"\n{passed}/{len(golden['cases'])} passed against {model}. Full results in {out_path}.")
sys.exit(0 if passed == len(golden["cases"]) else 1)
PYEOF
