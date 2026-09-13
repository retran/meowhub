#!/usr/bin/env python3
# The model gateway stub (spec 0001 T18, R17, ADR 0015): a local responder
# with the same OpenAI-compatible shape OpenRouter itself uses, so anything
# that calls OPENROUTER_BASE_URL cannot tell the difference except by the
# "provider" field this stub deliberately stamps on every response.
#
# Extended for spec 0003: capture-text's extraction is what a real model
# would do, so a workflow test needs input-aware canned responses, not one
# fixed string. This applies simple, deterministic heuristics — an amount
# regex, a merchant-alias lookup against whatever the request itself
# supplied as context, "no digits at all" as the unparsed case — never a
# real model call. Good enough to drive the fixtures this project's own
# tests need; nowhere near a real extraction and never meant to be.
import http.server
import json
import re


CURRENCY_MINOR_EXPONENT = 2  # EUR only, this project's default (ADR 0011)


def extract_amount_minor(text):
    # "24,40" / "24.40" states euros and cents explicitly. A bare number
    # with no separator ("350") is the household's own informal shorthand
    # for 3.50 — the digits themselves are the minor units, not euros to
    # multiply by 100 (spec 0003 A7 is explicit: "coffee 350" is 3.50).
    match = re.search(r"(\d+)[.,](\d{1,2})\b|(?<!\d)(\d+)(?!\d*[.,]\d)", text)
    if not match:
        return None
    if match.group(1) is not None:
        whole, frac = match.group(1), match.group(2).ljust(2, "0")
        return int(whole) * 100 + int(frac)
    return int(match.group(3))


def find_merchant(text, aliases):
    lowered = text.lower()
    for alias, canonical in (aliases or {}).items():
        if alias.lower() in lowered:
            return canonical
    # No known alias matched — a real model would still name whatever
    # merchant the member typed (system.md: "return the raw name as
    # typed"), so this heuristic looks for "at <Capitalized Words>",
    # good enough for this project's own fixtures without pretending to
    # be a real entity extractor.
    match = re.search(r"\bat ([A-Z][\w']*(?:\s+[A-Z&][\w']*)*)", text)
    return match.group(1) if match else None


def extract_date_hint(text):
    lowered = text.lower()
    if "yesterday" in lowered or "вчера" in lowered:
        return "yesterday"
    return None


def extract_payment_hint(text):
    lowered = text.lower()
    for needle, hint in (
        ("credit card", "credit card"),
        ("card", "credit card"),
        ("карт", "credit card"),
        ("cash", "cash"),
        ("наличными", "cash"),
        ("savings", "savings"),
    ):
        if needle in lowered:
            return hint
    return None


def extract_note(text):
    for marker in ("подарок", "gift for", "for the office", "это"):
        idx = text.lower().find(marker)
        if idx != -1:
            return text[idx:].strip()
    return None


def compose_setup_conversation_response(user_text, context):
    step = (context or {}).get("step", "accounts")
    lowered = user_text.lower()

    empty = {
        "status": "resolved", "done": None, "account_name": None, "account_type": None,
        "opening_balance_minor": None, "overdraft_limit_minor": None, "credit_limit_minor": None,
        "timezone": None, "currency": None, "question": None,
    }

    if step == "accounts":
        if any(w in lowered for w in ("done", "that's all", "готово", "всё", "все")):
            return {**empty, "done": True}
        balance = extract_amount_minor(user_text)
        if balance is None:
            return {**empty, "status": "question", "question": "What does it currently hold?"}
        account_type = "liability" if any(w in lowered for w in ("credit card", "card", "loan", "кредит")) else "asset"
        limit_match = re.search(r"limit(?:\s+is)?\s+(\d+)", lowered)
        name_part = re.split(r",|\bhas\b|\bhad\b|\bi owe\b|\bowe\b|\blimit\b", user_text, maxsplit=1)[0].strip()
        result = {**empty, "done": False, "account_name": name_part, "account_type": account_type, "opening_balance_minor": balance}
        if account_type == "liability" and limit_match:
            result["credit_limit_minor"] = int(limit_match.group(1))
        return result

    if step == "household_settings":
        tz = None
        for needle, zone in (("amsterdam", "Europe/Amsterdam"), ("netherlands", "Europe/Amsterdam"), ("utc", "UTC")):
            if needle in lowered:
                tz = zone
                break
        cur = None
        for needle, code in (("euro", "EUR"), ("eur", "EUR"), ("dollar", "USD"), ("usd", "USD")):
            if needle in lowered:
                cur = code
                break
        if not tz and not cur:
            return {**empty, "status": "question", "question": "What timezone and currency does the household use?"}
        return {**empty, "timezone": tz, "currency": cur}

    if step == "default_payment_account":
        known = (context or {}).get("known_accounts", [])
        for name in known:
            if name.lower() in lowered or lowered in name.lower():
                return {**empty, "account_name": name}
        return {**empty, "status": "question", "question": "Which of your accounts was that?"}

    return {**empty, "status": "question", "question": "Could you say that differently?"}


def compose_capture_text_response(user_text, context):
    # A28's fixture: a deliberately schema-violating response (missing
    # the required inferred_fields array) -- proves the workflow treats
    # an invalid response as unparsed rather than trusting it.
    if "SCHEMA_VIOLATION_TEST" in user_text:
        return {"status": "resolved", "amount_minor": 100}

    known_aliases = (context or {}).get("known_merchant_aliases", {})
    amount = extract_amount_minor(user_text)

    if amount is None:
        history = (context or {}).get("conversation_history", [])
        asked_before = {m["text"] for m in history if m.get("direction") == "outbound"}
        question = "What did you spend?" if "How much was it?" in asked_before else "How much was it?"
        return {
            "status": "question",
            "amount_minor": None,
            "currency": None,
            "original_amount_minor": None,
            "original_currency": None,
            "date": None,
            "merchant": None,
            "category_slug": None,
            "payment_method_hint": None,
            "note": None,
            "question": question,
            "inferred_fields": [],
        }

    payment_hint = extract_payment_hint(user_text)
    if payment_hint is None:
        # A34a/R25a: a remembered preference is consulted, but never
        # overrides what the member actually said this time.
        for note in (context or {}).get("memory", []):
            memory_hint = re.search(r"\buse (cash|card)\b", note, re.IGNORECASE)
            if memory_hint:
                payment_hint = memory_hint.group(1).lower()
                break
    known_accounts = (context or {}).get("known_accounts")
    if payment_hint == "savings" and known_accounts and "savings" not in [a.lower() for a in known_accounts]:
        return {
            "status": "question",
            "amount_minor": None,
            "currency": None,
            "original_amount_minor": None,
            "original_currency": None,
            "date": None,
            "merchant": None,
            "category_slug": None,
            "payment_method_hint": payment_hint,
            "note": None,
            "question": "I don't have a \"savings\" account on file — which of your accounts was this?",
            "inferred_fields": [],
        }

    merchant = find_merchant(user_text, known_aliases)
    inferred = []
    category_slug = None
    if merchant:
        category_slug = (context or {}).get("merchant_default_category", {}).get(merchant)
    if category_slug is None:
        category_slug = "dining"
        inferred.append("category")

    return {
        "status": "resolved",
        "amount_minor": amount,
        "currency": context.get("currency", "EUR") if context else "EUR",
        "original_amount_minor": None,
        "original_currency": None,
        "date": extract_date_hint(user_text),
        "merchant": merchant,
        "category_slug": category_slug,
        "payment_method_hint": payment_hint,
        "note": extract_note(user_text),
        "inferred_fields": inferred,
    }


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        requested_model = body.get("model", "unknown")

        content = "This is the local model gateway stub — no external request was made."
        messages = body.get("messages", [])
        user_messages = [m for m in messages if m.get("role") == "user"]
        if "capture-text" in requested_model and user_messages:
            last = user_messages[-1]
            raw = last.get("content", "")
            try:
                parsed = json.loads(raw)
                user_text = parsed.get("text", "")
                context = parsed.get("context", {})
            except (json.JSONDecodeError, AttributeError):
                user_text = raw
                context = {}
            content = json.dumps(compose_capture_text_response(user_text, context))
        elif "setup-conversation" in requested_model and user_messages:
            last = user_messages[-1]
            raw = last.get("content", "")
            try:
                parsed = json.loads(raw)
                user_text = parsed.get("text", "")
                context = parsed.get("context", {})
            except (json.JSONDecodeError, AttributeError):
                user_text = raw
                context = {}
            content = json.dumps(compose_setup_conversation_response(user_text, context))

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
                        "content": content,
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
