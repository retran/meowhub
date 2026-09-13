-- pgTAP: A23 — each role's actual grants, checked against the database
-- itself (information_schema.role_table_grants), not against what a
-- migration file claims to do.
begin;
select plan(5);

select ok(
  (select count(*) from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public') = 0,
  'anon holds no table grant at all (R15b)'
);

select ok(
  (select count(*) from information_schema.role_table_grants
    where grantee = 'hh_report' and table_schema = 'public') = 0,
  'hh_report holds no table grant yet — select on views only, and no view exists (R15b)'
);

select ok(
  (select array_agg(distinct privilege_type::text order by privilege_type::text)
     from information_schema.role_table_grants
    where grantee = 'hh_member' and table_schema = 'public' and table_name = 'member')
    = array['SELECT'],
  'hh_member holds exactly SELECT on member'
);

select ok(
  (select array_agg(distinct privilege_type::text order by privilege_type::text)
     from information_schema.role_table_grants
    where grantee = 'hh_admin' and table_schema = 'public' and table_name = 'member')
    = array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'hh_admin holds full CRUD on member'
);

select ok(
  (select array_agg(distinct privilege_type::text order by privilege_type::text)
     from information_schema.role_table_grants
    where grantee = 'hh_agent' and table_schema = 'public' and table_name = 'member_identity')
    is null,
  'hh_agent holds no grant on member_identity at all'
);

select * from finish();
rollback;
