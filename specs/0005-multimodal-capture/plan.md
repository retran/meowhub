---
spec: 0005
created: 2026-09-13
updated: 2026-09-13
---

# 0005 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

Spec 0003 already built the capture contour: normalise, extract against a
declared schema, resolve the merchant, apply the member's defaults, write a
balanced transaction, reply. This slice changes only the **front** of that
contour — what arrives and which prompt reads it — and reuses everything behind
it. Anything that turns out to need a second copy of spec 0003's logic is a
sign the shared step belongs in a sub-workflow (ADR 0040), not in this slice.

1. **The audio probe, before anything else (R18).** One deliberate call to the
   real gateway with a real voice note, recorded with its date and result. Voice
   capture is the only requirement here that could turn out to be undeliverable,
   and finding that out after building the file path and the prompts would be
   finding it out too late. Both outcomes are planned for below.
2. **An ingest boundary that n8n can actually reach.** Content-addressed storage
   exists (ADR 0019, spec 0001 T7), but only as `scripts/file-store.sh` on the
   host: n8n mounts neither the volume nor a path to the database for it. A small
   `file-store` service — one file, no published port, the same shape as the
   token bridge (ADR 0041) — accepts bytes, hashes them, writes the blob and the
   `file` row, and answers with the hash and whether it was already held.
3. **Two prompts, two workflows, one shared tail.** `prompts/capture-receipt/`
   and `prompts/capture-voice/` (ADR 0025), read by `capture-photo` and
   `capture-voice` (ADR 0040's naming). Both dispatch from the entry point that
   already exists and already carries `has_photo` and `has_voice`.
4. **The rules that differ from text, made explicit rather than inherited**:
   never auto-confirm (R9), the receipt's date wins over the send date (R6), the
   caption is a hint that outranks the model (R8), and a cost ceiling that
   refuses before the call rather than reporting after it (R19).
5. **Multi-page and "show me the receipt" last**, because both are conversational
   rather than extractive and depend on the capture path being right first.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| A small `file-store` HTTP service n8n calls | One implementation of hashing and the `file` row, shared by the host script and the workflows; no published port; the token bridge already establishes the shape | One more container | **chosen** |
| Mount the file volume into n8n and write from a Code node | No new service | Needs `fs` in `NODE_FUNCTION_ALLOW_BUILTIN`, puts storage logic inside workflow JSON where it cannot be reviewed or tested (ADR 0010), and duplicates the hashing rule | rejected |
| Store the bytes in PostgreSQL and move them to the volume later | Simplest to wire | Exactly what ADR 0019 rejected: every nightly dump then carries every receipt | rejected |
| A separate speech-to-text service in front of the voice prompt | Works even if the gateway cannot carry audio | ADR 0029 rejected it outright: a dependency to run and pay for when a multimodal model reads audio natively. Kept only as the documented fallback if the R18 probe fails | rejected unless R18 forces it |
| One multimodal prompt for photo and voice | Fewer files | ADR 0025's "one task, one prompt": receipts and speech fail differently and would be tuned against each other | rejected |
| Reuse spec 0003's text prompt, describing the image in a preamble | No new schema | Couples receipt quality to text-capture quality and hides which prompt version read what | rejected |
| Dedup a re-sent photo silently, recording one transaction | No question to answer | Two sends of the same receipt can legitimately be two expenses; the house rule is to ask rather than assume (R12) | rejected |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `file-store/` | New service: `POST` bytes, get back the SHA-256, the media type recorded, and whether it was already stored | spec 0007 uses the same endpoint for statement files |
| `compose.yaml` | The `file-store` service, mounting `FILE_STORAGE_PATH`; the multimodal model ids and per-task cost ceilings in n8n's environment (ADR 0034) | spec 0007 adds the statement task's ceiling |
| `prompts/` | `capture-receipt/` and `capture-voice/`: system prompt, output schema, examples in both languages (ADR 0025). First content in a directory that has been mounted and empty since spec 0001 | spec 0007's statement prompt |
| `workflows/` | `capture-photo`, `capture-voice`, `send-receipt`; the entry point gains two dispatch branches on flags it already computes | spec 0007 |
| `db/migrations/` | `capture.kind` gains `photo` and `voice`; the extracted payload (line items, transcript) stored on the capture; the auto-confirm predicate excludes photo- and voice-sourced transactions | spec 0007 adds `statement_import` |
| `model-gateway/docker/server.py` | Canned responses selected by the SHA-256 of the image or audio the request carries, read from a committed fixtures directory. The stub keeps stamping its own `provider`, so a test still cannot mistake it for a real call | every later slice that stubs a model |
| `i18n/` | The reply that echoes what was read, the "type the amount instead" refusal, the one-receipt-or-two question | every slice |
| `docs/guides/talking-to-meow.md` | Send a photo, send a voice note, ask to see a receipt | spec 0007 |

## Contracts and data

- **`file-store`**: `POST /` with the bytes and a media type; responds
  `{sha256, stored|duplicate, size}`. It never serves files — reading goes
  through the authenticated path (ADR 0019), which for this slice is the bot
  replying with bytes it fetched itself.
- **`capture`** (already catalogued in `docs/architecture/data-model.md`) carries
  `kind` (`text`, `photo`, `voice`), the `file` it arrived as, and the model's
  full structured response — which is where R16's line items and R17's transcript
  live. Line items are stored and read by nothing this slice.
- **Prompts** declare their output schema as JSON (ADR 0025). The receipt schema
  requires total, date and merchant, and permits currency and line items; the
  voice schema requires amount and merchant and carries the transcript. A
  response failing its schema is an unparsed capture, never a partial write.
- **Cost ceilings** are `MODEL_CEILING_<TASK>_EUR` environment variables, read
  per call (ADR 0034). The projected cost is an estimate from the payload's size
  and the task's configured rate — honestly an estimate, which is why the ceiling
  is set well below the point where being wrong matters.
- **No new views.** Every figure this slice touches already has one:
  `v_transaction_detail` carries the transaction's file and where its category
  came from, which is what R20 and A15 read.
- **Two entities the catalogue does not yet have**, both owed by spec 0003 rather
  than invented here: the **model-exchange log** ADR 0008 requires (prompt, model,
  response, latency, cost per *attempt* — an attempt that produces no transaction
  still has a cost, so this cannot be columns on `transaction`), and the
  **extracted-payload column** on `capture`. This slice is the first to depend on
  both; if spec 0003 lands without them, they are added here and
  `data-model.md` is updated in the same change.

## Migration and compatibility

- Additive only. `capture.kind` gains two values, `capture` gains a payload
  column, and the auto-confirm predicate gains an exclusion — no existing row
  changes meaning, and every migration has a `down`.
- **Existing text captures keep auto-confirming** exactly as spec 0003 defined:
  R9's prohibition is scoped to the two new kinds, and the predicate says so by
  naming them rather than by naming text.
- The `file-store` service is stateless and additive; `scripts/file-store.sh`
  keeps working for the host path and is refactored to call the same service
  rather than reimplementing the hash, so the two cannot drift.
- Reversible: removing the two dispatch branches from the entry point disables
  photo and voice capture entirely without touching text.

## Verification strategy

Everything except A13 runs against the stub, with no external request and no
cost, exactly as spec 0001 T18 built it to. The stub selects its canned response
by hashing the image or audio bytes it was sent, so the workflow cannot tell it
apart from the real gateway and the fixture and its expected extraction are
committed together. A13 is the only criterion that needs a real model, and ADR
0015 already says the golden set runs on demand and never in CI.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | `scripts/test-capture-photo.sh`: a committed receipt fixture through the real `capture-photo` workflow; assert the transaction's total, date and merchant, that its postings sum to zero, and that it is unconfirmed |
| A2 | The same script, second fixture: canned extraction dated three days before the send; assert the transaction's date is the receipt's, not today's |
| A3 | `scripts/test-capture-voice.sh`: an audio fixture through `capture-voice`; assert the resulting transaction matches the canned extraction |
| A4 | The same script with a member whose `language` is `ru`; assert the transaction is identical and the reply matches the Russian catalogue key, not a literal string |
| A5 | Both scripts assert the reply names amount, merchant, date and category, is one message, and resolves from `i18n/` |
| A6 | `test-capture-photo.sh`: the same fixture sent with a caption naming a category; assert the transaction's category is the caption's and not the canned response's |
| A7 | pgTAP over the auto-confirm predicate: a photo-sourced and a voice-sourced transaction at a known merchant below the threshold, with the quiet period elapsed; assert both are still unconfirmed, and a text-sourced control is not |
| A8 | `test-capture-photo.sh`: fixture whose canned response fails its schema; assert no transaction, a `file` row and blob present, the capture unparsed, and exactly one question asked |
| A9 | The same photo sent twice: assert one blob on the volume and one `file` row (extending what `scripts/test-file-storage.sh` already proves), and that the second send is surfaced as a question rather than recorded as a second expense |
| A10 | Two updates sharing a `media_group_id`: assert one question asked, no transaction written, and the open `conversation` row that holds it (ADR 0038) |
| A11 | pgTAP: for each capture kind, assert the `file` is linked to the transaction and the model id, prompt version and cost are recorded on the attempt |
| A12 | `docker compose stop model-gateway-stub`, then send a photo: assert the file is stored, the capture is unparsed, the member is told it will be handled, and nothing is lost |
| A13 | `task golden-set` — fixtures for both kinds with their expected extractions, run deliberately against the real gateway, scores recorded in the change (ADR 0025). Not in CI, and the only criterion here that costs money |
| A14 | Set the task's ceiling to zero; send a photo: assert no request reached the stub at all (it counts them), no model-exchange row exists, and the member was asked to type the amount |
| A15 | `scripts/test-send-receipt.sh`: ask for a transaction's receipt; assert the outbound call carries the bytes whose hash matches the linked `file` row |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The gateway cannot carry audio to the chosen model (R18) | medium | Probed first, before any voice work. If a second multimodal model also fails, voice capture is deferred and recorded as such — ADR 0029's fallback for voice is an unparsed capture, and a separate speech-to-text service is a decision to reopen, not one to make quietly inside a task |
| Receipt extraction is right too rarely to be worth using | medium | This is what the golden set measures, and the measure is in the spec's own "Why". A weak score is a prompt and model problem solved by ADR 0029's routing table — one configuration line — not by rebuilding anything here |
| Model spend becomes material, which is exactly what this slice risks | medium | The ceiling refuses before the call (R19), every attempt's cost is recorded (R15), and the daily threshold alert from ADR 0029 already exists. A known merchant still costs nothing in the text path; photos always cost |
| Receipt fixtures in the repository are photographs of real household life | medium | Fixtures are the household's own receipts, anonymised, or synthesised — the same rule spec 0007 R25 sets for statements |
| The review queue grows because nothing here ever auto-confirms | high, by design | Named in the spec's own ergonomic cost; drained by spec 0007's reconciliation, bounded meanwhile by the ceiling alert from ADR 0023 |
| A file larger than the model accepts | medium | Downscaled before sending; the original is what is stored (the spec's own edge case), so the stored evidence is never the degraded copy |

## ADRs required

None. Every decision here is an application of one that exists: ADR 0029 for the
routing and the ceiling, ADR 0025 for the prompts, ADR 0019 for the storage,
ADR 0023 for the confirmation rule, ADR 0040 for the workflow shape. The one
decision that could outlive this slice — whether a separate speech-to-text
service is ever acceptable — is deliberately left to ADR 0029 to reopen if the
R18 probe fails, rather than settled here by a task that discovered a problem.
