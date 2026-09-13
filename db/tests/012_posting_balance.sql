-- pgTAP: the postings-sum-to-zero invariant (ADR 0011, spec 0003 A6),
-- attacked directly — never through a workflow — and A30 (no write
-- without an acting member, under every writing role).
begin;
select plan(5);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id \gset mem_
insert into account (type, name) values ('asset', 'Assets:Test3') returning id \gset asset_
insert into account (type, name) values ('expense', 'groceries') returning id \gset exp_

-- A6: two postings summing to zero is legal, even written as two
-- separate statements — the deferred check only fires at commit (here,
-- forced early with SET CONSTRAINTS so the assertion can run inside this
-- test's own transaction).
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'manual') returning id \gset ok_txn_
insert into posting (transaction_id, account_id, amount, currency) values (:ok_txn_id, :asset_id, -350, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:ok_txn_id, :exp_id, 350, 'EUR');

select lives_ok(
  $$ set constraints all immediate $$,
  'two postings summing to zero are accepted once the deferred check fires'
);
set constraints all deferred;

-- A6: two postings that do NOT sum to zero are rejected.
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'manual') returning id \gset bad_txn_
insert into posting (transaction_id, account_id, amount, currency) values (:bad_txn_id, :asset_id, -100, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:bad_txn_id, :exp_id, 50, 'EUR');

select throws_ok(
  $$ set constraints all immediate $$,
  'P0001',
  null,
  'two postings summing to -50 are rejected at commit, attacked directly'
);
set constraints all deferred;
-- Clean up the still-unbalanced rows: left in place, this violation
-- would re-fire on every later SET CONSTRAINTS ALL IMMEDIATE in this
-- same transaction, since nothing about catching it once removes it.
delete from posting where transaction_id = :bad_txn_id;
delete from transaction where id = :bad_txn_id;
set constraints all immediate;
set constraints all deferred;

-- A30: no write to transaction or posting succeeds with no actor set —
-- the generic audit trigger's own rule (spec 0001), inherited here with
-- no changes. Tested role-neutral: T3 adds the grants that let hh_agent,
-- hh_member and hh_admin reach these tables at all, and re-proves this
-- same rule under each of them once that exists.
select set_config('meowhub.actor', '', true);
select throws_ok(
  format($$ insert into transaction (date, submitter, source) values (current_date, %s, 'manual') $$, :'mem_id'),
  'P0001', null, 'a transaction cannot be written with no actor set (A30)'
);

select set_config('meowhub.actor', :'mem_id', true);
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'manual') returning id \gset noactor_txn_
select set_config('meowhub.actor', '', true);
select throws_ok(
  format($$ insert into posting (transaction_id, account_id, amount, currency) values (%s, %s, -1, 'EUR') $$, :'noactor_txn_id', :'asset_id'),
  'P0001', null, 'a posting cannot be written with no actor set (A30)'
);

-- A real bug this test exists specifically to catch again: deleting
-- every posting for a transaction (as a full delete does) must not
-- itself trip the invariant. `SET CONSTRAINTS ALL IMMEDIATE` forces the
-- deferred check to run right here, inside this test's own transaction
-- — the same thing a real commit would do, which is exactly what let
-- this bug hide behind every other test in this file (they all prove
-- the good case with `lives_ok`/`throws_ok`, which never force the
-- deferred check at all, and pgTAP's own rollback means a real commit
-- checking it never happens either).
select set_config('meowhub.actor', :'mem_id', true);
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'manual') returning id \gset del_txn_
insert into posting (transaction_id, account_id, amount, currency) values (:del_txn_id, :asset_id, -700, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:del_txn_id, :exp_id, 700, 'EUR');
set constraints all immediate;
set constraints all deferred;
delete from posting where transaction_id = :del_txn_id;
delete from transaction where id = :del_txn_id;
select lives_ok(
  $$ set constraints all immediate $$,
  'deleting every posting for a transaction (a full delete) does not trip the invariant — no postings left is not unbalanced'
);
set constraints all deferred;

select * from finish();
rollback;
