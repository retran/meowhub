-- pgTAP: A42 -- for every tool declared in tools/*.json (spec 0003
-- T7-T13), a member without its declared permission fails at the
-- database, and the database's own constraints reject malformed
-- input regardless of who sends it. Several of these are already
-- proven elsewhere (record_transaction, correct_transaction,
-- confirm_transaction, classify_transaction, delete_transaction in
-- db/tests/013; posting balance in 012; auto-confirm in 018) -- this
-- file covers the tools and constraints those did not already reach:
-- open_account, amend_account, merge_category's underlying grants,
-- remember, request_correction, and two malformed-input constraints.
begin;
select plan(11);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin')  returning id \gset admin_
insert into member (role) values ('member') returning id \gset a_
insert into member (role) values ('member') returning id \gset b_
insert into account (type, name) values ('asset', 'Assets:Test') returning id \gset asset_
insert into account (type, name) values ('expense', 'groceries-tool-test') returning id \gset groceries_
insert into account (type, name) values ('expense', 'transport-tool-test') returning id \gset transport_

-- tools/open_account.json: "acts_as"/hh_admin.
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select throws_ok(
  $$ insert into account (type, name) values ('asset', 'Assets:Sneaky2') $$,
  null, null, 'open_account: hh_member has no grant to open an account at all'
);
reset role;

set role hh_admin;
select set_config('meowhub.actor', :'admin_id', true);
select lives_ok(
  $$ insert into account (type, name) values ('asset', 'Assets:ByAdmin') $$,
  'open_account: hh_admin opens an account, as declared'
);
-- Malformed input: an account type outside the fixed five is rejected
-- by the check constraint regardless of who sends it (ADR 0031 --
-- account types are fixed, the accounts themselves are data).
select throws_ok(
  $$ insert into account (type, name) values ('imaginary', 'Assets:Bogus') $$,
  null, null, 'open_account: a type outside the fixed five is rejected by the check constraint'
);
reset role;

-- tools/amend_account.json: "acts_as"/hh_admin -- setting new terms.
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select throws_ok(
  format($$ insert into account_term (account_id, credit_limit, effective_from) values (%s, 100000, current_date) $$, :'asset_id'),
  null, null, 'amend_account: hh_member has no grant to set new terms on an account'
);
reset role;

set role hh_admin;
select set_config('meowhub.actor', :'admin_id', true);
select lives_ok(
  format($$ insert into account_term (account_id, overdraft_limit, effective_from) values (%s, 50000, current_date) $$, :'asset_id'),
  'amend_account: hh_admin sets new terms, as declared'
);
reset role;

-- tools/merge_category.json: "acts_as"/hh_admin -- the merged-away
-- category is deactivated (repointing postings is R15a's own
-- unconditional reclassification, already proven in 013).
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select throws_ok(
  format($$ update account set active = false where id = %s $$, :'groceries_id'),
  null, null, 'merge_category: hh_member cannot deactivate the merged-away category'
);
reset role;

set role hh_admin;
select set_config('meowhub.actor', :'admin_id', true);
select lives_ok(
  format($$ update account set active = false where id = %s $$, :'groceries_id'),
  'merge_category: hh_admin deactivates the merged-away category, as declared'
);
reset role;

-- tools/remember.json: "composes"/hh_agent -- never a member's own
-- write, whatever member_id the memory is scoped to.
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select throws_ok(
  format($$ insert into agent_memory (member_id, content) values (%s, 'sneaky memory') $$, :'a_id'),
  null, null, 'remember: hh_member has no grant to write agent_memory directly'
);
reset role;

set role hh_agent;
select set_config('meowhub.actor', :'a_id', true);
select lives_ok(
  format($$ insert into agent_memory (member_id, content) values (%s, 'a real memory') $$, :'a_id'),
  'remember: hh_agent composes a memory row, as declared'
);
reset role;

-- tools/request_correction.json: "acts_as"/hh_member -- fixed in this
-- same slice (spec 0003 T14): the tool's own declared permission is
-- hh_member, not hh_agent, and the row is tied to the requesting
-- member's own actor identity.
set role hh_agent;
select set_config('meowhub.actor', :'a_id', true);
insert into transaction (date, submitter, source) values (current_date, :a_id, 'text') returning id \gset req_txn_
reset role;

set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select lives_ok(
  format($$ insert into correction_request (transaction_id, requested_by, requested_change) values (%s, %s, '{"amount_minor": 100}'::jsonb) $$, :'req_txn_id', :'a_id'),
  'request_correction: hh_member requests a correction against their own actor id, as declared'
);
select throws_ok(
  format($$ insert into correction_request (transaction_id, requested_by, requested_change) values (%s, %s, '{"amount_minor": 100}'::jsonb) $$, :'req_txn_id', :'b_id'),
  null, null, 'request_correction: a member cannot file a request attributed to someone else'
);
reset role;

select * from finish();
rollback;
