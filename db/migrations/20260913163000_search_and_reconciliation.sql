-- migrate:up

-- spec 0004 T4: search over notes, merchants and raw capture text
-- (R19), and the reconciliation-status stub spec 0007 gives something
-- real to read (R17). unaccent+pg_trgm rather than a per-language
-- stemmer: a transaction does not record which language it was
-- written in, the household writes in two and mixes them, and
-- merchant names are neither language (plan.md).
create extension if not exists unaccent;
create extension if not exists pg_trgm;

-- unaccent() itself is only STABLE (Postgres can't prove a dictionary
-- never changes), so it cannot appear in an index expression directly
-- -- this wrapper pins the dictionary and is genuinely immutable for
-- this repository's purposes, the standard pattern for accent-
-- insensitive trigram search.
create or replace function immutable_unaccent(text)
returns text
language sql
immutable
parallel safe
as $$ select unaccent('unaccent', $1) $$;

create index transaction_note_trgm_idx on transaction using gin (immutable_unaccent(coalesce(note, '')) gin_trgm_ops);
create index merchant_name_trgm_idx on merchant using gin (immutable_unaccent(name) gin_trgm_ops);
create index capture_raw_text_trgm_idx on capture using gin (immutable_unaccent(coalesce(raw_text, '')) gin_trgm_ops);

create view v_transaction_search with (security_invoker = true) as
select
  t.id as transaction_id, t.date, t.note, m.name as merchant_name,
  immutable_unaccent(
    coalesce(t.note, '') || ' ' || coalesce(m.name, '') || ' ' ||
    coalesce((select string_agg(c.raw_text, ' ') from capture c where c.transaction_id = t.id), '')
  ) as searchable_text
from transaction t
left join merchant m on m.id = t.merchant_id;

comment on view v_transaction_search is
  'One row per transaction with everything free-text about it concatenated (its note, its merchant, every capture message that produced or touched it) -- filter with `searchable_text ilike ...` or `%` similarity, both backed by the trigram indexes above (R19).';

grant select on v_transaction_search to hh_member, hh_agent, hh_admin;

-- v_period_reconciliation exists from this slice but reports "not
-- reconciled" everywhere until spec 0007 gives it something to read --
-- stated in every answer as such, never omitted (R17).
create view v_period_reconciliation with (security_invoker = true) as
select rp.period, rp.period_start, rp.period_end, false as reconciled
from v_reporting_period rp;

comment on view v_period_reconciliation is
  'Whether a period is reconciled, per the reporting period vocabulary (ADR 0045). Always false until spec 0007 adds statement reconciliation -- stated, never omitted (R17).';

grant select on v_period_reconciliation to hh_member, hh_agent, hh_admin;

-- migrate:down
revoke select on v_period_reconciliation from hh_member, hh_agent, hh_admin;
drop view v_period_reconciliation;
revoke select on v_transaction_search from hh_member, hh_agent, hh_admin;
drop view v_transaction_search;
drop index capture_raw_text_trgm_idx;
drop index merchant_name_trgm_idx;
drop index transaction_note_trgm_idx;
drop function immutable_unaccent(text);
