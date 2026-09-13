-- migrate:up

-- The six roles from spec 0002 R15b, created bare: no grants yet (T3 gives
-- each exactly what R15b names, no more). Only authenticator ever logs in
-- directly — PostgREST connects as it and switches into the role a
-- verified JWT names via SET ROLE, the standard PostgREST pattern; the
-- other five are never authenticated to directly.
--
-- Roles are cluster-wide, not per-database (unlike everything else a
-- migration creates) — a guard against re-creating one is required here
-- specifically, so this migration replays cleanly against a second,
-- throwaway database in the same cluster (scripts/test-db.sh does exactly
-- this on every run).
do $$
begin
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'hh_member') then
    create role hh_member nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'hh_admin') then
    create role hh_admin nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'hh_agent') then
    create role hh_agent nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'hh_report') then
    create role hh_report nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'authenticator') then
    create role authenticator noinherit login;
  end if;
end
$$;

grant anon to authenticator;
grant hh_member to authenticator;
grant hh_admin to authenticator;
grant hh_agent to authenticator;
grant hh_report to authenticator;

comment on role authenticator is
  'PostgREST''s own connection (R15b). Its password is set outside migrations, by scripts/set-authenticator-password.sh, from DB_ROLE_AUTHENTICATOR_PASSWORD — never committed.';

-- migrate:down
-- Roles are cluster-wide: dropping them here would also break whichever
-- other database in this cluster still depends on them (again, exactly
-- the throwaway test database's situation). Down is a no-op by design;
-- nothing else in this migration is per-database state to unwind.
