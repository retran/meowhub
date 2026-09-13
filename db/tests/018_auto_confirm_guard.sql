-- pgTAP: transaction_agent_confirm_guard actually enforces R7c at the
-- database (spec 0003 T12) — a narrow grant alone would let hh_agent
-- confirm anything; this proves the guard, not the grant, is what
-- decides, the same style as db/tests/013's proof for deletion.
begin;
select plan(6);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id \gset admin_
insert into account (type, name) values ('asset', 'Assets:Test') returning id \gset asset_
insert into account (type, name) values ('expense', 'groceries') returning id \gset groceries_
insert into household_setting (key, value, updated_by) values ('auto_confirm_threshold_minor', '2000', :admin_id);
insert into household_setting (key, value, updated_by) values ('auto_confirm_quiet_period_hours', '24', :admin_id);

-- A transaction that meets every one of R7c's conditions: a known
-- merchant's own category, below the threshold, well past the quiet
-- period.
set role hh_agent;
insert into transaction (date, submitter, source, category_source, created_at)
  values (current_date, :admin_id, 'text', 'merchant_default', now() - interval '48 hours') returning id \gset eligible_
insert into posting (transaction_id, account_id, amount, currency) values (:eligible_id, :asset_id, -1500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:eligible_id, :groceries_id, 1500, 'EUR');
reset role;

set role hh_agent;
select lives_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'quiet', confirmed_at = now() where id = %s $$, :'eligible_id'),
  'the agent auto-confirms a transaction meeting every one of R7c''s conditions'
);
reset role;

-- The model's own guess, not the merchant's default — never auto-confirmed.
set role hh_agent;
insert into transaction (date, submitter, source, category_source, created_at)
  values (current_date, :admin_id, 'text', 'model', now() - interval '48 hours') returning id \gset model_guess_
insert into posting (transaction_id, account_id, amount, currency) values (:model_guess_id, :asset_id, -1500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:model_guess_id, :groceries_id, 1500, 'EUR');
reset role;

set role hh_agent;
select throws_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'quiet', confirmed_at = now() where id = %s $$, :'model_guess_id'),
  null, null, 'a model-guessed category is never auto-confirmed, whatever its age or amount (R7c)'
);
reset role;

-- At or over the threshold — never auto-confirmed.
set role hh_agent;
insert into transaction (date, submitter, source, category_source, created_at)
  values (current_date, :admin_id, 'text', 'merchant_default', now() - interval '48 hours') returning id \gset over_threshold_
insert into posting (transaction_id, account_id, amount, currency) values (:over_threshold_id, :asset_id, -2000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:over_threshold_id, :groceries_id, 2000, 'EUR');
reset role;

set role hh_agent;
select throws_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'quiet', confirmed_at = now() where id = %s $$, :'over_threshold_id'),
  null, null, 'an amount at or over the configured threshold is never auto-confirmed (R7c)'
);
reset role;

-- Before the quiet period has elapsed — never auto-confirmed.
set role hh_agent;
insert into transaction (date, submitter, source, category_source, created_at)
  values (current_date, :admin_id, 'text', 'merchant_default', now()) returning id \gset too_recent_
insert into posting (transaction_id, account_id, amount, currency) values (:too_recent_id, :asset_id, -1500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:too_recent_id, :groceries_id, 1500, 'EUR');
reset role;

set role hh_agent;
select throws_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'quiet', confirmed_at = now() where id = %s $$, :'too_recent_id'),
  null, null, 'the quiet period must actually have elapsed (R7c)'
);
reset role;

-- Even a fully-eligible transaction is refused if auto-confirmation is
-- unconfigured — an unset threshold is the same as zero, never a
-- default that quietly confirms everything.
delete from household_setting where key in ('auto_confirm_threshold_minor', 'auto_confirm_quiet_period_hours');

set role hh_agent;
insert into transaction (date, submitter, source, category_source, created_at)
  values (current_date, :admin_id, 'text', 'merchant_default', now() - interval '48 hours') returning id \gset unconfigured_
insert into posting (transaction_id, account_id, amount, currency) values (:unconfigured_id, :asset_id, -1500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:unconfigured_id, :groceries_id, 1500, 'EUR');
reset role;

set role hh_agent;
select throws_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'quiet', confirmed_at = now() where id = %s $$, :'unconfigured_id'),
  null, null, 'an unconfigured threshold behaves exactly like zero: nothing auto-confirms'
);
reset role;

-- hh_admin is unaffected by the guard, as always.
select set_config('meowhub.actor', :'admin_id', true);
set role hh_admin;
select lives_ok(
  format($$ update transaction set confirmation_state = 'confirmed', confirmation_route = 'review', confirmed_by = %s, confirmed_at = now() where id = %s $$, :'admin_id', :'unconfigured_id'),
  'hh_admin confirms unconditionally, unaffected by the agent-only guard'
);
reset role;

select * from finish();
rollback;
