-- pgTAP: the six roles from spec 0002 R15b exist, with no more and no
-- fewer, and only authenticator can log in directly (T2).
begin;
select plan(8);

select ok(
  (select count(*) from pg_roles where rolname in
    ('anon', 'hh_member', 'hh_admin', 'hh_agent', 'hh_report', 'authenticator')) = 6,
  'all six roles exist'
);

select ok(not (select rolcanlogin from pg_roles where rolname = 'anon'), 'anon cannot log in directly');
select ok(not (select rolcanlogin from pg_roles where rolname = 'hh_member'), 'hh_member cannot log in directly');
select ok(not (select rolcanlogin from pg_roles where rolname = 'hh_admin'), 'hh_admin cannot log in directly');
select ok(not (select rolcanlogin from pg_roles where rolname = 'hh_agent'), 'hh_agent cannot log in directly');
select ok(not (select rolcanlogin from pg_roles where rolname = 'hh_report'), 'hh_report cannot log in directly');
select ok((select rolcanlogin from pg_roles where rolname = 'authenticator'), 'authenticator can log in — PostgREST''s own connection');

select ok(
  (select count(*) from pg_auth_members m
     join pg_roles r on r.oid = m.roleid
     join pg_roles a on a.oid = m.member
    where a.rolname = 'authenticator'
      and r.rolname in ('anon', 'hh_member', 'hh_admin', 'hh_agent', 'hh_report')) = 5,
  'authenticator can switch into all five other roles'
);

select * from finish();
rollback;
