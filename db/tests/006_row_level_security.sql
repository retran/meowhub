-- pgTAP: row-level security proven by impersonation, never by reading the
-- policy text (ADR 0015, spec 0002 T3). SET ROLE genuinely subjects this
-- session to the target role's own permissions and RLS policies — this is
-- not the superuser bypassing anything.
begin;
select plan(20);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id \gset admin_
insert into member (role) values ('member') returning id \gset member_

-- anon: nothing at all (R14, A14).
set role anon;
select throws_ok($$ select * from member $$, null, null, 'anon cannot read member');
select throws_ok($$ select * from file $$, null, null, 'anon cannot read file');
select throws_ok($$ select * from audit_log $$, null, null, 'anon cannot read audit_log');
select throws_ok($$ select * from member_identity $$, null, null, 'anon cannot read member_identity');
select throws_ok($$ select * from member_channel $$, null, null, 'anon cannot read member_channel');
reset role;

-- hh_member: reads the roster, files and the audit log; writes neither
-- membership nor identity linkage (R9, R10).
set role hh_member;
select lives_ok($$ select * from member $$, 'hh_member reads member');
select lives_ok($$ select * from file $$, 'hh_member reads file');
select lives_ok($$ select * from audit_log $$, 'hh_member reads audit_log');
select throws_ok($$ select * from member_identity $$, null, null, 'hh_member cannot read member_identity');
select throws_ok($$ select * from member_channel $$, null, null, 'hh_member cannot read member_channel');
select throws_ok(
  format($$ update member set language = 'en' where id = %s $$, :'member_id'),
  null, null, 'hh_member cannot write member'
);
select throws_ok($$ insert into member_channel (member_id, kind, external_id, linked_by) values (1, 'telegram', 'x', 1) $$,
  null, null, 'hh_member cannot create a channel link');
reset role;

-- hh_agent: resolves who is speaking (member, member_channel) and captures
-- files, but never links a channel itself — only an admin does (R6c).
set role hh_agent;
select lives_ok($$ select * from member $$, 'hh_agent reads member');
select lives_ok($$ select * from member_channel $$, 'hh_agent reads member_channel');
select throws_ok($$ select * from member_identity $$, null, null, 'hh_agent cannot read member_identity');
select throws_ok($$ insert into member_channel (member_id, kind, external_id, linked_by) values (1, 'telegram', 'y', 1) $$,
  null, null, 'hh_agent cannot create a channel link');
reset role;

-- hh_admin: the roles above, plus membership and identity linkage (R10).
set role hh_admin;
select lives_ok($$ select * from member_identity $$, 'hh_admin reads member_identity');
select lives_ok($$ select * from member_channel $$, 'hh_admin reads member_channel');
select lives_ok(
  format($$ update member set language = 'en' where id = %s $$, :'member_id'),
  'hh_admin can write member'
);
reset role;

-- R15c: a write with no acting member set fails, on any role, on any
-- audited table — not just the ledger tables T4 adds.
select set_config('meowhub.actor', '', true);
set role hh_admin;
select throws_ok(
  format($$ update member set language = 'ru' where id = %s $$, :'member_id'),
  null, null, 'a write with no acting member set fails, even for hh_admin'
);
reset role;

select * from finish();
rollback;
