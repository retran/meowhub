-- pgTAP: the views this slice needs, proven by impersonation as
-- security-invoker (spec 0003 T5) — A5 (cash is a real account, a
-- withdrawal never moves spend) and A27 (a category's display name
-- follows the reading member's language).
begin;
select plan(11);

select has_view('public', 'v_account', 'v_account exists');
select has_view('public', 'v_account_balance', 'v_account_balance exists');
select has_view('public', 'v_category', 'v_category exists');
select has_view('public', 'v_period_spend', 'v_period_spend exists');
select has_view('public', 'v_transaction_detail', 'v_transaction_detail exists');
select has_view('public', 'v_unconfirmed', 'v_unconfirmed exists');
select has_view('public', 'v_unconfirmed_summary', 'v_unconfirmed_summary exists');

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id \gset admin_
insert into member (role) values ('member') returning id \gset mem_
insert into account (type, name) values ('asset', 'Assets:Bank') returning id \gset bank_
insert into account (type, name) values ('asset', 'Assets:Cash') returning id \gset cash_
insert into account (type, name) values ('expense', 'groceries') returning id \gset groceries_
insert into translation (slug, language, display_name) values ('groceries', 'en', 'Groceries');
insert into translation (slug, language, display_name) values ('groceries', 'ru', 'Продукты');
-- v_reporting_period (ADR 0045) has no rows without a household
-- timezone -- every spend view is empty without one, not wrong.
insert into household_setting (key, value, updated_by) values ('timezone', '"Europe/Amsterdam"', :admin_id);

-- A withdrawal: bank down, cash up. No expense-type posting at all, so
-- v_period_spend must not move (R22: cash is tracked, not spent on
-- withdrawal).
set role hh_agent;
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'text') returning id \gset withdraw_
insert into posting (transaction_id, account_id, amount, currency) values (:withdraw_id, :bank_id, -5000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:withdraw_id, :cash_id, 5000, 'EUR');

select is(
  (select amount_minor from v_period_spend where period = 'this_month'),
  0::numeric,
  'a withdrawal (transfer) leaves v_period_spend at zero for the month (A5)'
);

-- Spending the cash is what moves it.
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'text') returning id \gset spend_
insert into posting (transaction_id, account_id, amount, currency) values (:spend_id, :cash_id, -1200, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:spend_id, :groceries_id, 1200, 'EUR');
reset role;

select is(
  (select amount_minor from v_period_spend where period = 'this_month'),
  1200::numeric,
  'spending the withdrawn cash is what moves v_period_spend (A5)'
);

-- A27: the same slug renders each member's language via v_category.
select is(
  (select display_name from v_category where slug = 'groceries' and language = 'en'),
  'Groceries',
  'v_category renders the English display name'
);
select is(
  (select display_name from v_category where slug = 'groceries' and language = 'ru'),
  'Продукты',
  'v_category renders the Russian display name for the same slug (A27)'
);

select * from finish();
rollback;
