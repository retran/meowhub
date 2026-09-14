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


# --- the agent (spec 0004 T7, ADR 0046) ---------------------------
# A real model answers a tool-calling request either with tool_calls
# or with prose, so the stub must do both, across rounds. Round one
# picks a tool from the question; once tool results are in the
# messages, it writes a sentence out of the rows it was given --
# never a figure it made up, because A14 asserts exactly that.

AGENT_TOOL_RULES = [
    (r"\bmost on\b|\branked\b|\bбольше всего\b|\bon groceries\b|\bна продукты\b|\bby category\b", "spend_by_category"),
    (r"\bwaiting for review\b|\bunconfirmed\b|\bна проверк", "unconfirmed_summary"),
    (r"\bbiggest\b|\blargest\b|\bсамые больш", "largest_expenses"),
    (r"\bhappened on\b|\bmovement\b|\bпо счёту\b", "account_movement"),
    (r"\bowe\b|\bdebt\b|\bдолжны\b", "liability_summary"),
    (r"\bnet position\b|\bin total\b|\bвсего есть\b", "household_position"),
    (r"\bheadroom\b|\bbalance\b|\bwhat'?s in\b|\bна счету\b", "account_balance"),
    (r"\bdid i spend\b|\bя потратил", "spend_by_member"),
    (r"\bdid we spend\b|\bмы потратили\b|\bspend this month\b", "spend_total"),
]

AGENT_REFUSAL_RE = r"\bafford\b|\bforecast\b|\bbudget\b|\bпозволить\b|\bпрогноз"


def _agent_period(lowered):
    if "last month" in lowered or "в том месяце" in lowered:
        return "last_month"
    if "this year" in lowered or "в этом году" in lowered:
        return "this_year"
    if "last week" in lowered:
        return "last_7_days"
    return "this_month"


def _agent_tool_call(name, args):
    return {
        "id": f"call_{name}",
        "type": "function",
        "function": {"name": name, "arguments": json.dumps(args)},
    }


def _money(minor, currency="EUR"):
    return f"{int(minor) / 100:.2f} \u20ac" if currency == "EUR" else f"{int(minor) / 100:.2f} {currency}"


# --- the agent's capture flow -------------------------------------
# Capture is no longer a one-shot extraction: the agent looks the
# merchant up, creates it only when the registry really has nothing,
# looks up the category and the account, and only then records. The
# stub sequences those rounds by reading the tool results it already
# has, which is what a real tool-calling model does.

def _tool_results(messages):
    out = {}
    for m in messages:
        if m.get("role") != "tool":
            continue
        try:
            payload = json.loads(m.get("content") or "{}")
        except (json.JSONDecodeError, TypeError):
            payload = {}
        out.setdefault(m.get("name"), []).append(payload)
    return out


def _agent_context(messages):
    for m in messages:
        if m.get("role") == "system" and str(m.get("content", "")).startswith("Context for this exchange:"):
            try:
                return json.loads(str(m["content"]).split(":", 1)[1].strip())
            except (json.JSONDecodeError, IndexError):
                return {}
    return {}


CURRENCY_WORDS = {"euro", "euros", "eur", "\u20ac", "cents", "cent", "\u0440\u0443\u0431", "\u0440\u0443\u0431\u043b\u0435\u0439"}


def _merchant_candidate(text):
    """Whatever is left after the amount, if it names a shop.

    A real model reads the sentence; the stub takes the tail after the
    amount and rejects it when it is a payment method or a currency
    word, which is the distinction that actually matters here.
    """
    match = re.search(r"(\d+(?:[.,]\d{1,2})?)", text)
    if not match:
        return None
    tail = text[match.end():].strip()
    tail = re.sub(r"^(at|from|in|\u0432|\u0443)\s+", "", tail, flags=re.IGNORECASE).strip()
    tail = re.sub(r"[.,;!]+$", "", tail).strip()
    if not tail:
        return None
    if extract_payment_hint(tail):
        return None
    if tail.lower() in CURRENCY_WORDS:
        return None
    words = [w for w in tail.split() if w.lower() not in CURRENCY_WORDS]
    if not words:
        return None
    return " ".join(words)


def compose_agent_capture(messages, user_text, context):
    results = _tool_results(messages)
    amount = extract_amount_minor(user_text)
    merchant_name = _merchant_candidate(user_text)
    payment_hint = extract_payment_hint(user_text)
    if payment_hint is None:
        for note in context.get("memory", []) or []:
            hit = re.search(r"\buse (cash|card)\b", note, re.IGNORECASE)
            if hit:
                payment_hint = hit.group(1).lower()
                break
    account_wanted = payment_hint or context.get("default_payment_account") or "current"

    # Round 4: the transaction exists. Say what was understood, not
    # what the member already typed (agent-persona.md).
    if "record_transaction" in results:
        recorded = results["record_transaction"][0]
        if recorded.get("error"):
            return {"content": "Не смог записать это." if _is_ru(user_text) else "I couldn't record that."}
        slug = _chosen_category(results)
        shown = _money(amount or 0)
        if merchant_name:
            return {"content": f"{shown} \u2014 {merchant_name} ({slug})."}
        return {"content": f"{shown} ({slug})."}

    # Round 3: everything looked up. Record it.
    if "find_category" in results:
        category_rows = results["find_category"][0].get("rows") or []
        account_rows = (results.get("find_account") or [{}])[0].get("rows") or []
        if not category_rows or not account_rows:
            return {"content": _cannot_place(user_text, account_wanted, bool(account_rows))}
        merchant_id = _chosen_merchant_id(results)
        source = "merchant_default" if _merchant_default_used(results) else "model"
        return {"tool_calls": [_agent_tool_call("record_transaction", {
            "member_id": context.get("member_id"),
            "date": context.get("today"),
            "amount_minor": amount,
            "currency": context.get("currency", "EUR"),
            "account_id": account_rows[0].get("account_id") or account_rows[0].get("id"),
            "category_account_id": category_rows[0].get("id"),
            "merchant_id": merchant_id,
            "category_source": source,
            "source": "text",
            "note": extract_note(user_text),
            "prompt_version": "agent@1",
        })]}

    # Round 2: the registry has answered. Create the merchant if it
    # genuinely has nothing, and look up the category either way.
    if "find_merchant" in results or "find_account" in results:
        account_rows = (results.get("find_account") or [{}])[0].get("rows") or []
        if not account_rows:
            return {"content": _cannot_place(user_text, account_wanted, False)}
        calls = []
        merchant_rows = (results.get("find_merchant") or [{}])[0].get("rows") or []
        if merchant_name and not merchant_rows and "create_merchant" not in results:
            calls.append(_agent_tool_call("create_merchant", {"name": merchant_name}))
        slug = _merchant_default_slug(results) or _guess_category(user_text)
        calls.append(_agent_tool_call("find_category", {"text": slug}))
        return {"tool_calls": calls}

    # Round 1: look before deciding anything.
    calls = [_agent_tool_call("find_account", {"text": account_wanted})]
    if merchant_name:
        calls.append(_agent_tool_call("find_merchant", {"text": merchant_name}))
    return {"tool_calls": calls}


def _is_ru(text):
    return any(ord(ch) > 127 for ch in text)


def _guess_category(text):
    lowered = text.lower()
    for needle, slug in (("grocer", "groceries"), ("продукт", "groceries"), ("transport", "transport"), ("train", "transport")):
        if needle in lowered:
            return slug
    return "dining"


def _merchant_default_slug(results):
    rows = (results.get("find_merchant") or [{}])[0].get("rows") or []
    for row in rows:
        if row.get("default_category_slug"):
            return row["default_category_slug"]
    return None


def _merchant_default_used(results):
    return _merchant_default_slug(results) is not None


def _chosen_merchant_id(results):
    rows = (results.get("find_merchant") or [{}])[0].get("rows") or []
    if rows:
        return rows[0].get("merchant_id")
    created = (results.get("create_merchant") or [{}])[0].get("rows") or []
    if created:
        return created[0].get("id")
    return None


def _chosen_category(results):
    rows = (results.get("find_category") or [{}])[0].get("rows") or []
    return rows[0].get("slug") if rows else "uncategorised"


def _cannot_place(user_text, account_wanted, have_account):
    # A31: an account the household does not have is a question, never
    # an invented account.
    if not have_account:
        if _is_ru(user_text):
            return f"Не вижу счёта «{account_wanted}» \u2014 с какого счёта это оплачено?"
        return f'I don\'t have a "{account_wanted}" account on file -- which of your accounts was this?'
    return "Не могу разобрать категорию \u2014 на что это?" if _is_ru(user_text) else "I couldn't place that -- what was it for?"


# --- corrections, conveniences and the queue (spec 0004 T9b) -------
# Each is a tool call the agent makes against the transaction it first
# looked up, rather than a workflow of its own with its own regexes.

CORRECT_AMOUNT_RE = r"\bit was\s+(\d+(?:[.,]\d{1,2})?)\s*,?\s*(?:not|instead of|rather than)\s+\d+"
DELETE_RE = r"\b(?:delete|remove) (?:it|that|this)\b|\bудали"
CLASSIFY_RE = r"\b(?:put (?:it|that) under|category (?:is|should be)|that'?s actually)\s+([a-z][\w ]*?)\s*$"
CONFIRM_CALLBACK_RE = r"^confirm:(\d+)$"
CONFIRM_TYPED_RE = r"^\s*(?:confirm|approve)\b(?!\s+all)|^\s*подтверд"
CONFIRM_ALL_RE = r"^\s*confirm all\b|^\s*подтвердить все"
QUEUE_RE = r"\bunconfirmed\b|\bqueue\b|неподтвержд"
UNDO_RE = r"^\s*undo\b|^\s*отмен"
REMEMBER_RE = r"^(?:remember|запомни)[:\s]+(.+)$"
SAME_AGAIN_RE = r"как обычно|same again|\bas usual\b"
RECENT_RE = r"\brecent (?:captures|expenses)\b|\bmy (?:recent|last) expenses\b|\blast few\b"
FIXCAT_RE = r"^fixcat:(\d+)$"


def _target_transaction(results):
    rows = (results.get("find_recent_transaction") or [{}])[0].get("rows") or []
    return rows[0].get("id") if rows else None


def compose_agent_actions(messages, user_text, context):
    """Returns a response dict, or None when this is not an action."""
    results = _tool_results(messages)
    lowered = user_text.lower()
    is_ru = _is_ru(user_text)

    # A tapped button carries its own target, so nothing needs looking up.
    tapped = re.match(CONFIRM_CALLBACK_RE, user_text.strip(), re.IGNORECASE)
    if tapped:
        if "confirm_transaction" in results:
            return {"content": _confirm_reply(results, is_ru)}
        return {"tool_calls": [_agent_tool_call("confirm_transaction", {"transaction_id": int(tapped.group(1))})]}

    if re.match(FIXCAT_RE, user_text.strip(), re.IGNORECASE):
        return {"content": "Какая категория?" if is_ru else "Which category?"}

    if re.search(REMEMBER_RE, user_text, re.IGNORECASE):
        if "remember" in results:
            return {"content": "Запомнил." if is_ru else "Noted."}
        content = re.search(REMEMBER_RE, user_text, re.IGNORECASE).group(1).strip()
        return {"tool_calls": [_agent_tool_call("remember", {"content": content})]}

    if re.search(RECENT_RE, lowered):
        if "list_recent_captures" in results:
            rows = results["list_recent_captures"][0].get("rows") or []
            if not rows:
                return {"content": "Пока ничего нет." if is_ru else "Nothing recorded yet."}
            return {"content": ("Последние: " if is_ru else "Recent: ") + ", ".join(f"#{r['id']} {r['date']}" for r in rows[:5]) + "."}
        return {"tool_calls": [_agent_tool_call("list_recent_captures", {"limit": 5})]}

    # The queue: list it, or drain it one confirmation at a time so the
    # database refuses each one it should.
    if re.search(CONFIRM_ALL_RE, lowered):
        if "confirm_transaction" in results:
            confirmed = sum(1 for r in results["confirm_transaction"] if not r.get("error"))
            refused = sum(1 for r in results["confirm_transaction"] if r.get("error"))
            if confirmed and not refused:
                return {"content": "Всё подтверждено." if is_ru else "All confirmed."}
            if confirmed:
                return {"content": (f"Подтверждено: {confirmed}." if is_ru else f"Confirmed {confirmed}; the rest aren't mine to confirm.")}
            return {"content": "Это может подтвердить только администратор." if is_ru else "Only an admin can confirm the whole queue."}
        if "list_unconfirmed" in results:
            rows = results["list_unconfirmed"][0].get("rows") or []
            if not rows:
                return {"content": "Очередь пуста." if is_ru else "The queue is empty."}
            return {"tool_calls": [_agent_tool_call("confirm_transaction", {"transaction_id": r["id"]}) for r in rows]}
        return {"tool_calls": [_agent_tool_call("list_unconfirmed", {"limit": 50})]}

    if re.search(QUEUE_RE, lowered):
        if "list_unconfirmed" in results:
            rows = results["list_unconfirmed"][0].get("rows") or []
            if not rows:
                return {"content": "Очередь пуста." if is_ru else "The queue is empty."}
            listed = ", ".join(f"#{r['id']} {r['date']}" for r in rows[:10])
            tail = ' Reply "confirm all" to confirm them all.' if not is_ru else ' Напишите "confirm all", чтобы подтвердить все.'
            return {"content": (f"Не подтверждено ({len(rows)}): {listed}." if is_ru else f"Unconfirmed ({len(rows)}): {listed}.") + tail}
        return {"tool_calls": [_agent_tool_call("list_unconfirmed", {"limit": 50})]}

    if re.search(UNDO_RE, lowered):
        if "undo_last_action" in results:
            outcome = results["undo_last_action"][0]
            if outcome.get("error"):
                return {"content": "Нечего отменять." if is_ru else "There's nothing of yours to undo."}
            return {"content": "Отменено — записал компенсирующую проводку." if is_ru else "Undone -- a compensating entry was recorded."}
        return {"tool_calls": [_agent_tool_call("undo_last_action", {"member_id": context.get("member_id")})]}

    if re.search(SAME_AGAIN_RE, lowered):
        if "record_transaction" in results:
            return {"content": "Записал как обычно." if is_ru else "Recorded, same as usual."}
        if "transaction_lines" in results:
            lines = results["transaction_lines"][0].get("rows") or []
            expense = next((l for l in lines if (l.get("amount_minor") or 0) > 0), None)
            payment = next((l for l in lines if (l.get("amount_minor") or 0) < 0), None)
            if not expense or not payment:
                return {"content": "Нечего повторять." if is_ru else "There's nothing to repeat."}
            return {"tool_calls": [_agent_tool_call("record_transaction", {
                "member_id": context.get("member_id"), "date": context.get("today"),
                "amount_minor": expense["amount_minor"], "currency": expense.get("currency", "EUR"),
                "account_id": payment["account_id"], "category_account_id": expense["account_id"],
                "category_source": "model", "source": "manual", "prompt_version": "agent@1",
            })]}
        if "find_recent_transaction" in results:
            target = _target_transaction(results)
            if not target:
                return {"content": "Нечего повторять." if is_ru else "There's nothing to repeat."}
            return {"tool_calls": [_agent_tool_call("transaction_lines", {"transaction_id": target})]}
        return {"tool_calls": [_agent_tool_call("find_recent_transaction", {"mine_only": True, "limit": 1})]}

    typed_confirm = re.search(CONFIRM_TYPED_RE, lowered)
    correcting = re.search(CORRECT_AMOUNT_RE, user_text, re.IGNORECASE)
    classifying = re.search(CLASSIFY_RE, user_text, re.IGNORECASE)
    deleting = re.search(DELETE_RE, lowered)

    if not (typed_confirm or correcting or classifying or deleting):
        return None

    # Everything below acts on a transaction, so look it up first.
    if "find_recent_transaction" not in results:
        return {"tool_calls": [_agent_tool_call("find_recent_transaction", {
            "mine_only": bool(typed_confirm or correcting),
            "unconfirmed_only": bool(typed_confirm),
            "limit": 1,
        })]}

    target = _target_transaction(results)
    if not target:
        return {"content": "Не нашёл, что исправлять." if is_ru else "I don't have a recent transaction for that."}

    if typed_confirm:
        if "confirm_transaction" in results:
            return {"content": _confirm_reply(results, is_ru)}
        return {"tool_calls": [_agent_tool_call("confirm_transaction", {"transaction_id": target})]}

    if deleting:
        if "delete_transaction" in results:
            outcome = results["delete_transaction"][0]
            if outcome.get("error"):
                return {"content": "Только администратор может удалить запись." if is_ru else "Only an admin can delete a record."}
            return {"content": "Удалено." if is_ru else "Deleted."}
        return {"tool_calls": [_agent_tool_call("delete_transaction", {"transaction_id": target})]}

    if correcting:
        amount = extract_amount_minor(correcting.group(1))
        # R16a: refused by the database means asking an admin, not
        # giving up and not pretending it worked.
        if "correct_transaction" in results:
            outcome = results["correct_transaction"][0]
            if not outcome.get("error"):
                return {"content": "Исправлено." if is_ru else "Corrected."}
            if "request_correction" not in results:
                return {"tool_calls": [_agent_tool_call("request_correction", {
                    "transaction_id": target, "requested_change": {"amount_minor": amount},
                })]}
        if "request_correction" in results:
            return {"content": (
                "Не могу изменить сам — запрос отправлен администраторам."
                if is_ru else
                "I can't change that myself -- the request has gone to the admins."
            )}
        return {"tool_calls": [_agent_tool_call("correct_transaction", {"transaction_id": target, "amount_minor": amount})]}

    if classifying:
        wanted = classifying.group(1).strip()
        if "classify_transaction" in results:
            outcome = results["classify_transaction"][0]
            if outcome.get("error"):
                return {"content": "Не получилось переклассифицировать." if is_ru else "I couldn't reclassify that."}
            return {"content": "Исправлено." if is_ru else "Corrected."}
        if "find_category" in results:
            rows = results["find_category"][0].get("rows") or []
            if not rows:
                return {"content": "Не нашёл такую категорию." if is_ru else "I don't have that category."}
            return {"tool_calls": [_agent_tool_call("classify_transaction", {
                "transaction_id": target, "category_account_id": rows[0]["id"],
            })]}
        return {"tool_calls": [_agent_tool_call("find_category", {"text": wanted})]}

    return None


def _confirm_reply(results, is_ru):
    outcome = results["confirm_transaction"][0]
    if outcome.get("error"):
        return "Это не моя запись для подтверждения." if is_ru else "That one isn't mine to confirm."
    return "Подтверждено." if is_ru else "Confirmed."


# --- setup and structural changes (spec 0004 T9c) -----------------
# There is no step machine any more: setting the books up is a
# conversation the agent has with the tools it already has. What makes
# it resumable is that the exchange is stored (ADR 0038) -- the agent
# reads it back and carries on.

SETUP_TRIGGER_RE = r"\bset ?up\b|\bsettings\b|настро"
SETUP_DONE_RE = r"\bthat'?s all\b|\bdone\b|готово|\bвсё\b"
WHATS_LEFT_RE = r"what.*(?:left|remain)|что.*(?:осталось|осталась)"
OPEN_ACCOUNT_RE = r"\bopen (?:a |an |new )?(.+?)\s+account\b"
MERGE_RE = r"\bmerge\b\s+(?:the\s+)?([\w -]+?)\s+(?:and|into|with)\s+([\w -]+?)\s*$"
AGREE_RE = r"\b(yes|yep|correct|right|confirm|agreed|do it)\b|\bда\b|верно"

SETUP_FIRST_QUESTION = "Say \"done\" when that is all of them. What is the first account -- its name, what kind it is, and what it holds today?"
SETUP_SETTINGS_QUESTION = "What timezone and currency does the household use?"
SETUP_DEFAULT_QUESTION = "Which account should be your own default for spending?"


def _account_from_text(text):
    """Name, kind and opening balance from one sentence."""
    balance = extract_amount_minor(text)
    lowered = text.lower()
    kind = "liability" if re.search(r"credit card|\bcard\b|\bloan\b|кредит|owe", lowered) else "asset"
    name = re.split(r",|\bhas\b|\bhad\b|\bi owe\b|\bowe\b|\blimit\b", text, maxsplit=1)[0].strip()
    limit = None
    hit = re.search(r"limit(?:\s+is)?\s+(\d+)", lowered)
    if hit:
        limit = int(hit.group(1))
    return name, kind, balance, limit


def _setup_stage(context):
    """What the exchange still needs, read from the books themselves."""
    if not context.get("timezone_set"):
        return "settings"
    if not context.get("default_payment_account"):
        return "default_account"
    return "accounts"


def compose_agent_setup(messages, user_text, context):
    """Returns a response dict, or None when this is not setup."""
    results = _tool_results(messages)
    lowered = user_text.lower()
    is_ru = _is_ru(user_text)
    asked = context.get("questions_already_asked") or []
    in_setup = bool(asked) and any(
        q in (SETUP_FIRST_QUESTION, SETUP_SETTINGS_QUESTION, SETUP_DEFAULT_QUESTION) for q in asked
    )

    # "What still needs setting up?" (R29) reports and advances nothing.
    if re.search(WHATS_LEFT_RE, lowered):
        remaining = []
        if not context.get("timezone_set"):
            remaining.append("the timezone and currency" if not is_ru else "часовой пояс и валюту")
        if not context.get("default_payment_account"):
            remaining.append("your default account" if not is_ru else "счёт по умолчанию")
        if not remaining:
            return {"content": "Всё настроено." if is_ru else "Everything is set up."}
        joined = ", ".join(remaining)
        # Ends as a question so the exchange stays open: reporting what
        # is left settles nothing, and R29 asks that it be resumable
        # from there.
        return {"content": (f"Осталось: {joined}. Продолжим?" if is_ru
                            else f"Still to do: {joined}. Shall we carry on?")}

    if not in_setup and not re.search(SETUP_TRIGGER_RE, lowered):
        return None

    # Starting the interview: ask, do not act.
    if not in_setup:
        return {"content": SETUP_FIRST_QUESTION}

    # The interview is under way. What the member just said decides what
    # happens next; what is already true decides what to ask after it.
    if re.search(SETUP_DONE_RE, lowered) and extract_amount_minor(user_text) is None:
        return {"content": SETUP_SETTINGS_QUESTION}

    if "set_household_setting" in results:
        outcomes = results["set_household_setting"]
        if any(o.get("error") for o in outcomes):
            return {"content": "Только администратор может менять настройки." if is_ru else "Only an admin can change the household's settings."}
        return {"content": SETUP_DEFAULT_QUESTION}

    if "set_default_payment_account" in results:
        outcome = results["set_default_payment_account"][0]
        if outcome.get("error"):
            return {"content": "Не получилось." if is_ru else "That didn't work."}
        return {"content": "Готово! Можно записывать траты." if is_ru else "All set -- you can start recording expenses."}

    # Timezone and currency in one answer.
    timezone = None
    for needle, zone in (("amsterdam", "Europe/Amsterdam"), ("netherlands", "Europe/Amsterdam"), ("utc", "UTC")):
        if needle in lowered:
            timezone = zone
            break
    currency = None
    for needle, code in (("euro", "EUR"), ("eur", "EUR"), ("dollar", "USD"), ("usd", "USD")):
        if needle in lowered:
            currency = code
            break
    if (timezone or currency) and extract_amount_minor(user_text) is None:
        calls = []
        if timezone:
            calls.append(_agent_tool_call("set_household_setting", {"key": "timezone", "value": timezone}))
        if currency:
            calls.append(_agent_tool_call("set_household_setting", {"key": "default_currency", "value": currency}))
        return {"tool_calls": calls}

    # Naming an existing account answers "which is your default?".
    awaiting_default = bool(asked) and asked[-1] == SETUP_DEFAULT_QUESTION
    if "find_account" in results and awaiting_default:
        rows = results["find_account"][0].get("rows") or []
        if not rows:
            return {"content": "Не нашёл такой счёт — как он называется?" if is_ru else "I couldn't find that account -- what's it called?"}
        return {"tool_calls": [_agent_tool_call("set_default_payment_account", {"account_id": rows[0].get("account_id") or rows[0].get("id")})]}

    # An account, its kind and what it holds.
    name, kind, balance, limit = _account_from_text(user_text)

    if "record_transaction" in results or ("open_account" in results and balance is None):
        return {"content": (f"Добавил «{name}». Ещё счета? Или напишите «готово»."
                            if is_ru else f'Added "{name}". Another account, or say "done"?')}

    if "open_account" in results:
        opened = results["open_account"][0]
        if opened.get("error"):
            return {"content": "Только администратор может добавлять счета." if is_ru else "Only an admin can add accounts."}
        rows = opened.get("rows") or []
        account_id = rows[0]["id"] if rows else None
        equity_rows = (results.get("find_account") or [{}])[-1].get("rows") or []
        equity_id = next((r.get("account_id") or r.get("id") for r in equity_rows if r.get("type") == "equity"), None)
        calls = []
        if limit is not None:
            calls.append(_agent_tool_call("amend_account", {"account_id": account_id, "credit_limit": limit}))
        if account_id and equity_id and balance:
            # An opening balance is a real transaction (R3). Which side
            # the account sits on is what makes a liability read as
            # owed rather than held (ADR 0011's sign convention).
            if kind == "liability":
                calls.append(_agent_tool_call("record_transaction", {
                    "member_id": context.get("member_id"), "date": context.get("today"),
                    "amount_minor": balance, "currency": context.get("currency", "EUR"),
                    "account_id": account_id, "category_account_id": equity_id,
                    "source": "manual", "category_source": "manual", "prompt_version": "agent@1",
                }))
            else:
                calls.append(_agent_tool_call("record_transaction", {
                    "member_id": context.get("member_id"), "date": context.get("today"),
                    "amount_minor": balance, "currency": context.get("currency", "EUR"),
                    "account_id": equity_id, "category_account_id": account_id,
                    "source": "manual", "category_source": "manual", "prompt_version": "agent@1",
                }))
        if calls:
            return {"tool_calls": calls}
        return {"content": (f"Добавил «{name}». Ещё счета?" if is_ru else f'Added "{name}". Another account, or say "done"?')}

    if balance is not None or re.search(r"account|счёт|card|карт", lowered):
        return {"tool_calls": [
            _agent_tool_call("open_account", {"type": kind, "name": name}),
            _agent_tool_call("find_account", {"type": "equity"}),
        ]}

    # An account name on its own, at the point the default is wanted.
    return {"tool_calls": [_agent_tool_call("find_account", {"text": user_text.strip()})]}


def compose_agent_structural(messages, user_text, context):
    """Opening an account or merging categories, outside setup."""
    results = _tool_results(messages)
    is_ru = _is_ru(user_text)
    asked = context.get("questions_already_asked") or []

    opening = re.search(OPEN_ACCOUNT_RE, user_text, re.IGNORECASE)
    merging = re.search(MERGE_RE, user_text, re.IGNORECASE)
    restated = next((q for q in asked if "open a " in q.lower() or "merge the " in q.lower()), None)

    # R0b: restate a structural change, then apply it once agreed.
    if restated and re.search(AGREE_RE, user_text, re.IGNORECASE):
        if "open_account" in results:
            outcome = results["open_account"][0]
            if outcome.get("error"):
                return {"content": "Только администратор может добавлять счета." if is_ru else "Only an admin can add accounts."}
            return {"content": "Готово." if is_ru else "Opened."}
        if "merge_category" in results:
            outcome = results["merge_category"][0]
            if outcome.get("error"):
                return {"content": "Только администратор может объединять категории." if is_ru else "Only an admin can merge categories."}
            return {"content": "Категории объединены." if is_ru else "Categories merged."}
        if "find_category" in results:
            rows = results["find_category"][0].get("rows") or []
            if len(rows) < 2:
                return {"content": "Не нашёл одну из категорий." if is_ru else "I couldn't find one of those categories."}
            return {"tool_calls": [_agent_tool_call("merge_category", {
                "from_account_id": rows[0]["id"], "into_account_id": rows[1]["id"],
            })]}
        name = restated.split('"')[1] if '"' in restated else "Savings"
        kind = "liability" if re.search(r"credit card|card|loan", restated, re.IGNORECASE) else "asset"
        return {"tool_calls": [_agent_tool_call("open_account", {"type": kind, "name": name})]}

    if opening:
        name = opening.group(1).strip()
        kind = "liability" if re.search(r"credit card|card|loan|кредит", name, re.IGNORECASE) else "asset"
        return {"content": f'Can you confirm -- open a "{name}" account ({kind})?'}

    if merging:
        return {"content": f'Can you confirm -- merge the "{merging.group(1).strip()}" category into "{merging.group(2).strip()}"?'}

    return None


CAPTURE_TOOLS = {"find_account", "find_merchant", "find_category", "create_merchant", "record_transaction"}


REPORT_TOOLS = {"search_transactions", "why_category", "export_period"}


def compose_agent_reports(messages, user_text, context):
    """Search, "why this category" and export (R19, R20, R21).

    They are ordinary tools like any other -- what is special here is
    only that a stub has to recognise the three questions and then say
    something sensible about rows the generic renderer would call
    "Done.". Every figure below comes out of the tool result.
    """
    lowered = user_text.lower()
    results = _tool_results(messages)
    is_ru = _is_ru(user_text)

    if "search_transactions" in results:
        rows = (results["search_transactions"][-1] or {}).get("rows") or []
        if not rows:
            return {"content": "Ничего не нашлось." if is_ru else "Nothing matched."}
        named = "; ".join(
            f"{r['date']} {r.get('merchant_name') or r.get('note') or ''} "
            f"{_money(r['amount_minor'], r.get('currency') or 'EUR')}".strip()
            for r in rows[:5]
            if r.get("amount_minor") is not None
        )
        return {"content": (f"Нашёл: {named}." if is_ru else f"Found: {named}.")}

    if "why_category" in results:
        rows = (results["why_category"][-1] or {}).get("rows") or []
        if not rows:
            return {"content": "Такой записи нет." if is_ru else "There's no such record."}
        row = rows[0]
        source = row.get("category_source")
        if source == "model":
            return {"content": (
                f"Это выбрала модель {row.get('model')}, промпт {row.get('prompt_version')}."
                if is_ru else
                f"The model {row.get('model')} chose it, prompt {row.get('prompt_version')}."
            )}
        if source == "merchant_default":
            return {"content": (
                f"Это категория по умолчанию для продавца {row.get('merchant_name')}."
                if is_ru else
                f"That's the merchant default for {row.get('merchant_name')}."
            )}
        return {"content": (
            "Категорию выбрали вручную." if is_ru else "Somebody chose that category by hand."
        )}

    if "export_period" in results:
        res = results["export_period"][-1] or {}
        if res.get("error"):
            return {"content": "Такой период я не знаю." if is_ru else "I don't know that period."}
        return {"content": (
            f"Выгрузил {res.get('posting_count')} строк за {(res.get('period') or {}).get('period_start')} — "
            f"{(res.get('period') or {}).get('period_end')}, расходы {_money(res.get('expense_total_minor') or 0)}."
            if is_ru else
            f"Exported {res.get('posting_count')} rows for {(res.get('period') or {}).get('period_start')} to "
            f"{(res.get('period') or {}).get('period_end')}, expenses {_money(res.get('expense_total_minor') or 0)}."
        )}

    if "set_digest_preference" in results:
        res = results["set_digest_preference"][-1] or {}
        if res.get("error"):
            return {"content": "Не вышло это изменить." if is_ru else "I couldn't change that."}
        return {"content": "Больше не буду присылать." if is_ru else "I'll stop sending those."}

    if re.search(r"\bdigest\b|\bсводк", lowered) and re.search(r"\bstop\b|\boff\b|\bне (надо|присылай)\b|\bотключ", lowered):
        which = {}
        if re.search(r"\bweekly\b|\bнедел", lowered):
            which["weekly"] = False
        if re.search(r"\bmonthly\b|\bмесяч", lowered):
            which["monthly"] = False
        if not which:
            which = {"weekly": False, "monthly": False}
        return {"tool_calls": [_agent_tool_call("set_digest_preference", which)]}

    if re.search(r"\bexport\b|\bcsv\b|\bвыгруз", lowered):
        return {"tool_calls": [_agent_tool_call("export_period", {"period": _agent_period(lowered)})]}

    if re.search(r"\bwhy\b.*\bcategor|почему.*категор", lowered):
        match = re.search(r"#(\d+)", user_text)
        if match:
            return {"tool_calls": [_agent_tool_call("why_category", {"transaction_id": int(match.group(1))})]}

    if re.search(r"\bsearch\b|\bfind the\b|\blook up\b|\bнайди\b|\bпоищи\b", lowered):
        term = re.search(r"(?:for|про|по)\s+[\"«]?([\w\u0400-\u04ff-]+)", user_text, re.IGNORECASE)
        if not term:
            term = re.search(r"[\"«]([^\"»]+)[\"»]", user_text)
        if term:
            return {"tool_calls": [_agent_tool_call("search_transactions", {"query": term.group(1)})]}

    return None


def compose_agent_response(messages, user_text):
    lowered = user_text.lower()
    tool_messages = [m for m in messages if m.get("role") == "tool"]
    context = _agent_context(messages)
    results = _tool_results(messages)

    # A stubbed model that only ever calls tools: proves the round cap
    # is what stops the loop, not the model's good manners.
    if "LOOP_FOREVER_TEST" in user_text:
        return {"tool_calls": [_agent_tool_call("find_category", {"text": "anything"})]}

    # A28: a response the loop cannot use. The first round asks for a
    # tool that does not exist; the second gives up honestly, and
    # nothing is written either way.
    if "SCHEMA_VIOLATION_TEST" in user_text:
        if "not_a_real_tool" in results:
            return {"content": "I couldn't make sense of that one."}
        return {"tool_calls": [_agent_tool_call("not_a_real_tool", {})]}

    # Structural changes and setup are conversations of their own, and
    # they own phrases ("open a Savings account") that would otherwise
    # look like nothing in particular.
    structural = compose_agent_structural(messages, user_text, context)
    if structural is not None:
        return structural

    setup = compose_agent_setup(messages, user_text, context)
    if setup is not None:
        return setup

    # Searching, "why this category" and an export name themselves in
    # the message ("search for", "why", "export"), so they are settled
    # before the action rules, which would otherwise read "why is #12 in
    # that category" as a request to recategorise it.
    reports = compose_agent_reports(messages, user_text, context)
    if reports is not None:
        return reports

    # Actions come first. "put it under transport" names a category and
    # "it was 35 not 350" carries an amount, so either would otherwise
    # be taken for a question or a fresh capture.
    action = compose_agent_actions(messages, user_text, context)
    if action is not None:
        return action

    # A capture already under way stays a capture: the question rules
    # below would otherwise steal it, since "groceries 24,40" mentions
    # a category and a question about groceries does too.
    if set(results) & CAPTURE_TOOLS:
        return compose_agent_capture(messages, user_text, context)

    # An amount is what makes a message a capture rather than a question.
    if not tool_messages and extract_amount_minor(user_text) is not None and not re.search(r"how much|what did|сколько|что мы", lowered):
        return compose_agent_capture(messages, user_text, context)

    if tool_messages:
        try:
            payload = json.loads(tool_messages[-1].get("content") or "{}")
        except (json.JSONDecodeError, TypeError):
            payload = {}
        rows = payload.get("rows") or []
        is_ru = any(ord(ch) > 127 for ch in user_text)
        if payload.get("error"):
            return {"content": "Мне это не разрешено." if is_ru else "I'm not allowed to do that."}
        if not rows:
            return {"content": "За этот период ничего нет." if is_ru else "There's nothing recorded for that period."}

        row = rows[0]
        currency = row.get("currency") or "EUR"
        # Every figure below comes out of a row the database returned.
        if "amount_minor" in row and "category_slug" in row:
            named = ", ".join(
                f"{r['category_slug']} {_money(r['amount_minor'], currency)}" for r in rows[:3]
            )
            share = row.get("unconfirmed_share")
            tail = ""
            if share is not None:
                tail = (
                    f" Не подтверждено: {_money(row.get('unconfirmed_amount_minor') or 0, currency)}."
                    if is_ru else
                    f" Unconfirmed: {_money(row.get('unconfirmed_amount_minor') or 0, currency)}."
                )
            prev = row.get("previous_amount_minor")
            prev_tail = ""
            if prev is not None:
                prev_tail = (
                    f" В прошлом периоде: {_money(prev, currency)}."
                    if is_ru else
                    f" Previous period: {_money(prev, currency)}."
                )
            head = f"{row.get('period', '')}: {named}."
            return {"content": head + prev_tail + tail}

        if "amount_minor" in row:
            share_tail = ""
            if row.get("unconfirmed_amount_minor") is not None:
                share_tail = (
                    f" Не подтверждено: {_money(row['unconfirmed_amount_minor'], currency)}."
                    if is_ru else
                    f" Unconfirmed: {_money(row['unconfirmed_amount_minor'], currency)}."
                )
            prev_tail = ""
            if row.get("previous_amount_minor") is not None:
                prev_tail = (
                    f" В прошлом периоде: {_money(row['previous_amount_minor'], currency)}."
                    if is_ru else
                    f" Previous period: {_money(row['previous_amount_minor'], currency)}."
                )
            period = row.get("period", "")
            head = (
                f"{period}: потрачено {_money(row['amount_minor'], currency)}."
                if is_ru else
                f"{period}: {_money(row['amount_minor'], currency)} spent."
            )
            return {"content": head + prev_tail + share_tail}

        if "balance" in row:
            limit = row.get("limit_amount")
            headroom = row.get("headroom")
            text = f"{row.get('name', '')}: {_money(row['balance'], currency)}."
            if headroom is not None and limit is not None:
                text += (
                    f" Свободно {_money(headroom, currency)} из лимита {_money(limit, currency)}."
                    if is_ru else
                    f" Headroom {_money(headroom, currency)} against a limit of {_money(limit, currency)}."
                )
            return {"content": text}

        if "net_position_minor" in row:
            return {"content": (
                f"Всего {_money(row['holdings_minor'])}, должны {_money(row['owed_minor'])}, итого {_money(row['net_position_minor'])}."
                if is_ru else
                f"Holdings {_money(row['holdings_minor'])}, owed {_money(row['owed_minor'])}, net {_money(row['net_position_minor'])}."
            )}

        if "balance_minor" in row:
            total = [r for r in rows if r.get("account_id") is None]
            pick = total[0] if total else row
            return {"content": (
                f"Должны {_money(pick['balance_minor'])}."
                if is_ru else
                f"Owed {_money(pick['balance_minor'])}."
            )}

        if "unconfirmed_count" in row:
            return {"content": (
                f"Ждут проверки: {row['unconfirmed_count']}."
                if is_ru else
                f"{row['unconfirmed_count']} waiting for review."
            )}

        return {"content": "Готово." if is_ru else "Done."}

    if re.search(AGENT_REFUSAL_RE, lowered):
        is_ru = any(ord(ch) > 127 for ch in user_text)
        return {"content": (
            "Пока не умею — могу сказать траты за период, по категориям, по продавцам, баланс счетов или сколько мы должны."
            if is_ru else
            "I can't answer that yet -- I can give you spend for a period, by category, by merchant, account balances, or what's owed."
        )}

    for pattern, tool in AGENT_TOOL_RULES:
        if re.search(pattern, lowered):
            args = {}
            if tool in ("spend_total", "spend_by_category", "spend_by_merchant", "spend_by_member", "account_movement", "largest_expenses"):
                args["period"] = _agent_period(lowered)
            if tool == "spend_by_member":
                args["member_scope"] = "self" if re.search(r"\bi\b|\bя\b", lowered) else "everyone"
            if tool in ("account_balance", "account_movement"):
                args["account_name"] = "ICS Credit Card" if ("credit card" in lowered or "карт" in lowered) else "ABN AMRO"
            if tool == "spend_by_category" and ("grocer" in lowered or "продукт" in lowered):
                args["category_slug"] = "groceries"
            return {"tool_calls": [_agent_tool_call(tool, args)]}

    # R17: no recoverable amount and no question we can answer. Ask the
    # one thing that would unblock it -- and never the same one twice.
    asked = context.get("questions_already_asked") or []
    if _is_ru(user_text):
        question = "На что это было?" if "Сколько это стоило?" in asked else "Сколько это стоило?"
    else:
        question = "What did you spend?" if "How much was it?" in asked else "How much was it?"
    return {"content": question}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        requested_model = body.get("model", "unknown")

        content = "This is the local model gateway stub — no external request was made."
        messages = body.get("messages", [])
        user_messages = [m for m in messages if m.get("role") == "user"]
        agent_message = None
        if "agent" in requested_model and user_messages:
            # The agent's own turn: either tool calls or a finished
            # sentence, which is the shape a real tool-calling model
            # returns (ADR 0046).
            composed = compose_agent_response(messages, user_messages[-1].get("content", "") or "")
            agent_message = {"role": "assistant", "content": composed.get("content")}
            if composed.get("tool_calls"):
                agent_message["tool_calls"] = composed["tool_calls"]
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

        message = agent_message if agent_message is not None else {"role": "assistant", "content": content}
        response = {
            "id": "stub-completion",
            "provider": "meowhub-local-stub",
            "model": requested_model,
            "choices": [
                {
                    "index": 0,
                    "finish_reason": "tool_calls" if message.get("tool_calls") else "stop",
                    "message": message,
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
