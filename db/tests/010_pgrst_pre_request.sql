-- pgTAP: pgrst_pre_request() sets meowhub.actor from a JWT's member_id
-- claim the same way a caller would set it directly (spec 0002 T12) —
-- proven by simulating what PostgREST does: setting request.jwt.claims,
-- then calling the function, then writing to an audited table with no
-- other actor set.
begin;
select plan(2);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id \gset admin_

set role hh_admin;
select set_config('request.jwt.claims', json_build_object('role', 'hh_admin', 'member_id', :admin_id)::text, true);
select pgrst_pre_request();

select lives_ok(
  $$ insert into member (role) values ('member') $$,
  'a write succeeds with no explicit set_config call, once pgrst_pre_request has run'
);

select is(
  (select actor from audit_log where table_name = 'member' order by id desc limit 1),
  :'admin_id',
  'the actor recorded is the JWT''s own member_id claim'
);

reset role;
select * from finish();
