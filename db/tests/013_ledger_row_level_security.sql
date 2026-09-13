-- pgTAP: R9-R13 (spec 0002)'s write shape, proven against the real ledger
-- by impersonation (spec 0003 T3) — the rules ledger_probe proved do not
-- change, only what they are proved on (spec 0002 T4 was explicit that
-- this table would supersede it).
begin;
select plan(15);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin')  returning id \gset admin_
insert into member (role) values ('member') returning id \gset a_
insert into member (role) values ('member') returning id \gset b_
insert into account (type, name) values ('asset', 'Assets:Test') returning id \gset asset_
insert into account (type, name) values ('expense', 'groceries') returning id \gset groceries_
insert into account (type, name) values ('expense', 'transport') returning id \gset transport_

-- R13 (spec 0002): no member writes a raw posting under any role.
set role hh_member;
select throws_ok(
  format($$ insert into transaction (date, submitter, source) values (current_date, %s, 'manual') $$, :'a_id'),
  null, null, 'hh_member cannot insert a raw transaction (R13)'
);
reset role;
set role hh_admin;
select throws_ok(
  format($$ insert into transaction (date, submitter, source) values (current_date, %s, 'manual') $$, :'a_id'),
  null, null, 'hh_admin cannot insert a raw transaction either — only the agent composes one (R13)'
);
reset role;

-- The agent composes a capture on member A's behalf (ADR 0042).
select set_config('meowhub.actor', :'a_id', true);
set role hh_agent;
insert into transaction (date, submitter, source, merchant_id)
  values (current_date, :a_id, 'text', null) returning id \gset txn_
insert into posting (transaction_id, account_id, amount, currency) values (:txn_id, :asset_id, -350, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:txn_id, :groceries_id, 350, 'EUR') returning id \gset post_
reset role;

-- A11 (spec 0002): only an admin deletes a recorded transaction.
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select throws_ok(
  format($$ delete from transaction where id = %s $$, :'txn_id'),
  null, null, 'hh_member cannot delete a recorded transaction (R10)'
);
reset role;

-- R11/R15a: any member reclassifies any transaction's project, including
-- one they did not submit — unconditional, no confirmation-state check.
set role hh_member;
select set_config('meowhub.actor', :'b_id', true);
select lives_ok(
  format($$ update transaction set project_id = 999 where id = %s $$, :'txn_id'),
  'member B reclassifies (project_id) member A''s transaction, unconditionally (R15a)'
);
select lives_ok(
  format($$ update posting set account_id = %s where id = %s $$, :'transport_id', :'post_id'),
  'member B reclassifies (account_id) the same transaction''s category posting, unconditionally (R15a)'
);
reset role;

-- R12/R7b negative: member B (not the capturer) cannot confirm A's row.
set role hh_member;
select throws_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'review', confirmed_by = %s, confirmed_at = now() where id = %s $$, :'b_id', :'txn_id'),
  null, null, 'member B cannot confirm member A''s unconfirmed transaction (R12)'
);
reset role;

-- R12/R7b positive: member A, the capturer, confirms their own unconfirmed row.
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select lives_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'review', confirmed_by = %s, confirmed_at = now() where id = %s $$, :'a_id', :'txn_id'),
  'member A confirms their own unconfirmed transaction (R12)'
);

-- Once confirmed, a financial fact (here: the date) cannot be changed by
-- the member who captured it — R12's "while it is unconfirmed" gate
-- covers correcting too, not just confirming. Reclassification stays
-- unconditional (proven above, before confirmation, and the guard does
-- not distinguish confirmed/unconfirmed for project_id/note at all).
select throws_ok(
  format($$ update transaction set date = current_date - 1 where id = %s $$, :'txn_id'),
  null, null, 'a confirmed transaction''s date cannot be corrected by the member who captured it'
);
reset role;

-- A30/R9: every member reads the same whole ledger.
set role hh_member;
select is(
  (select count(*)::int from transaction), 1,
  'member A reads the whole ledger'
);
reset role;
select set_config('meowhub.actor', :'b_id', true);
set role hh_member;
select is(
  (select count(*)::int from transaction), 1,
  'member B reads the same whole ledger — asserted equal, not assumed'
);
reset role;

-- hh_admin corrects and deletes unconditionally, including a confirmed
-- transaction — R10's own authority, unaffected by the member guard.
select set_config('meowhub.actor', :'admin_id', true);
set role hh_admin;
select lives_ok(
  format($$ update transaction set date = current_date - 1 where id = %s $$, :'txn_id'),
  'admin corrects a confirmed transaction''s date (R10)'
);
select lives_ok(
  format($$ delete from transaction where id = %s $$, :'txn_id'),
  'admin deletes the transaction (R10) — postings cascade'
);
select is(
  (select count(*)::int from posting where transaction_id = :txn_id), 0,
  'deleting the transaction cascades to delete its postings'
);
reset role;

-- ADR 0031: the agent may create an unreviewed expense category
-- unprompted, but nothing else — the account_agent_insert_guard.
select set_config('meowhub.actor', :'a_id', true);
set role hh_agent;
select lives_ok(
  $$ insert into account (type, name, reviewed) values ('expense', 'new-category', false) $$,
  'the agent creates an unreviewed expense category unprompted (ADR 0031)'
);
select throws_ok(
  $$ insert into account (type, name) values ('asset', 'Assets:Sneaky') $$,
  null, null, 'the agent cannot create a non-expense account unprompted (ADR 0031)'
);
reset role;

select * from finish();
rollback;
