-- migrate:up

-- A real defect, found by scripts/test-restore-verification.sh: a
-- backup of this database would not load back.
--
-- immutable_unaccent (spec 0004 T4) called `unaccent('unaccent', $1)`
-- unqualified. That works in an ordinary session, whose search_path
-- includes public -- but a restore runs with search_path pinned to
-- pg_catalog, and the trigram indexes that call this function are
-- built during the restore. Loading the dump failed with "function
-- unaccent(unknown, text) does not exist", which means the books were
-- backed up but not restorable: the failure ADR 0009 exists to
-- prevent, and the reason its verification is a test rather than a
-- promise.
--
-- Schema-qualifying the call, and pinning the function's own
-- search_path, makes it resolve the same way in every session.
create or replace function immutable_unaccent(text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, public
as $$ select public.unaccent('public.unaccent'::regdictionary, $1) $$;

-- migrate:down
create or replace function immutable_unaccent(text)
returns text
language sql
immutable
parallel safe
as $$ select unaccent('unaccent', $1) $$;
