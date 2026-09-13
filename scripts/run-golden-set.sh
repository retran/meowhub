#!/usr/bin/env bash
# Runs prompts/capture-text/v1/golden-set.json against a real model
# (ADR 0025, spec 0003 T15) -- never the stub, and never part of
# `task test`, because this costs real money and is run deliberately.
# Scores go to stdout and to the file named by --out (default
# golden-set-results.json) so they can be recorded in the commit that
# changed the prompt.
set -euo pipefail

: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY must be set to a real key -- this script refuses to run against the stub}"
: "${OPENROUTER_BASE_URL:?OPENROUTER_BASE_URL must be set}"
: "${MODEL_TEXT_EXTRACTION:?MODEL_TEXT_EXTRACTION must name a real model -- refusing to run the golden set against an unset or stub model}"

if [[ "$OPENROUTER_BASE_URL" == *model-gateway-stub* ]]; then
  echo "REFUSING: OPENROUTER_BASE_URL points at the local stub, not a real model (ADR 0015 -- the stub is for workflow tests, never for the golden set)."
  exit 1
fi

GOLDEN_SET="${1:-prompts/capture-text/v1/golden-set.json}"
OUT="${2:-golden-set-results.json}"
SYSTEM_PROMPT_FILE="prompts/capture-text/v1/system.md"
EXAMPLES_FILE="prompts/capture-text/v1/examples.json"

python3 - "$GOLDEN_SET" "$OUT" "$SYSTEM_PROMPT_FILE" "$EXAMPLES_FILE" <<'PYEOF'
import json, os, sys, urllib.request

golden_set_path, out_path, system_prompt_path, examples_path = sys.argv[1:5]

with open(golden_set_path) as f:
    golden = json.load(f)
with open(system_prompt_path) as f:
    system_prompt = f.read()
with open(examples_path) as f:
    examples = json.load(f)

base_url = os.environ["OPENROUTER_BASE_URL"]
api_key = os.environ["OPENROUTER_API_KEY"]
model = os.environ["MODEL_TEXT_EXTRACTION"]

# The worked examples are the prompt's own few-shot demonstrations
# (ADR 0025) -- sent as real prior turns, not just kept in the repo as
# documentation nobody's request actually includes.
FEW_SHOT_MESSAGES = []
for ex in examples:
    FEW_SHOT_MESSAGES.append({"role": "user", "content": json.dumps({"text": ex["input"], "context": ex.get("context", {})})})
    FEW_SHOT_MESSAGES.append({"role": "assistant", "content": json.dumps(ex["output"])})

def call_model(text, context):
    body = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            *FEW_SHOT_MESSAGES,
            {"role": "user", "content": json.dumps({"text": text, "context": context})},
        ],
    }).encode()
    req = urllib.request.Request(
        f"{base_url}/chat/completions", data=body, method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        parsed = json.loads(resp.read())
    return json.loads(parsed["choices"][0]["message"]["content"])

def check_case(case, actual):
    expect = case["expect"]
    problems = []
    for key, want in expect.items():
        if key == "note_contains":
            got = (actual or {}).get("note") or ""
            if want not in got:
                problems.append(f"note missing '{want}': got {got!r}")
            continue
        got = (actual or {}).get(key)
        if got != want:
            problems.append(f"{key}: expected {want!r}, got {got!r}")
    return problems

results = []
passed = 0
for case in golden["cases"]:
    try:
        actual = call_model(case["text"], case.get("context", {}))
        problems = check_case(case, actual)
    except Exception as e:
        actual = None
        problems = [f"error calling model: {e}"]
    ok = not problems
    if ok:
        passed += 1
    results.append({"id": case["id"], "text": case["text"], "ok": ok, "actual": actual, "problems": problems})
    status = "PASS" if ok else "FAIL"
    print(f"{status}: {case['id']} — {case['text']}")
    for p in problems:
        print(f"       {p}")

summary = {
    "prompt": golden["prompt"],
    "version": golden["version"],
    "model": model,
    "total": len(golden["cases"]),
    "passed": passed,
    "results": results,
}
with open(out_path, "w") as f:
    json.dump(summary, f, indent=2)

print(f"\n{passed}/{len(golden['cases'])} passed against {model}. Full results in {out_path}.")
sys.exit(0 if passed == len(golden["cases"]) else 1)
PYEOF
