-- pgTAP: the spend-view family (spec 0004 T2) -- every figure checked
-- against an aggregation written independently in this file, never
-- against the view's own SQL (ADR 0015), covering A4 (figures match),
-- A6 (unconfirmed share correct) and A17 (previous period present).
begin;
select plan(9);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id \gset admin_
insert into member (role) values ('member') returning id \gset a_
insert into member (role) values ('member') returning id \gset b_
insert into household_setting (key, value, updated_by) values ('timezone', '"Europe/Amsterdam"', :admin_id);
insert into account (type, name) values ('asset', 'Assets:Test') returning id \gset asset_
insert into account (type, name) values ('expense', 'groceries') returning id \gset groceries_
insert into account (type, name) values ('expense', 'transport') returning id \gset transport_
insert into merchant (name) values ('Test Shop') returning id \gset shop_

set role hh_agent;

-- This month: two confirmed groceries transactions (member A), one
-- unconfirmed transport transaction (member B), all at the same
-- merchant so v_merchant_spend has something real to aggregate too.
insert into transaction (date, submitter, source, merchant_id, confirmation_state, confirmation_route)
  values (current_date, :a_id, 'text', :shop_id, 'confirmed', 'review') returning id \gset t1_
insert into posting (transaction_id, account_id, amount, currency) values (:t1_id, :asset_id, -1000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:t1_id, :groceries_id, 1000, 'EUR');

insert into transaction (date, submitter, source, merchant_id, confirmation_state, confirmation_route)
  values (current_date, :a_id, 'text', :shop_id, 'confirmed', 'review') returning id \gset t2_
insert into posting (transaction_id, account_id, amount, currency) values (:t2_id, :asset_id, -500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:t2_id, :groceries_id, 500, 'EUR');

insert into transaction (date, submitter, source, merchant_id)
  values (current_date, :b_id, 'text', :shop_id) returning id \gset t3_
insert into posting (transaction_id, account_id, amount, currency) values (:t3_id, :asset_id, -300, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:t3_id, :transport_id, 300, 'EUR');

-- Last month: one groceries transaction, so this_month has a real
-- previous_amount_minor to check (A17), not just a zero default.
insert into transaction (date, submitter, source, merchant_id, confirmation_state, confirmation_route)
  values (date_trunc('month', current_date)::date - interval '5 days', :a_id, 'text', :shop_id, 'confirmed', 'review') returning id \gset t4_
insert into posting (transaction_id, account_id, amount, currency) values (:t4_id, :asset_id, -700, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:t4_id, :groceries_id, 700, 'EUR');

reset role;

-- A4/A6: v_period_spend's this_month total is 1000+500+300=1800, of
-- which 300 is unconfirmed -- checked against a hand-written sum, not
-- against the view's own logic.
select is(
  (select amount_minor from v_period_spend where period = 'this_month'),
  1800::numeric,
  'v_period_spend''s this_month total equals the sum written by hand (A4)'
);
select is(
  (select unconfirmed_amount_minor from v_period_spend where period = 'this_month'),
  300::numeric,
  'v_period_spend''s unconfirmed_amount_minor is exactly the one unconfirmed transaction (A6)'
);
select is(
  (select unconfirmed_share from v_period_spend where period = 'this_month'),
  round(300::numeric / 1800, 4),
  'v_period_spend''s unconfirmed_share is unconfirmed over total, computed by hand (A6)'
);

-- A17: last month's own total (700) appears as this month's previous_amount_minor.
select is(
  (select previous_amount_minor from v_period_spend where period = 'this_month'),
  700::numeric,
  'v_period_spend''s previous_amount_minor equals last month''s own figure (A17)'
);
select is(
  (select amount_minor from v_period_spend where period = 'last_month'),
  700::numeric,
  'v_period_spend''s last_month total matches independently (A4)'
);

-- A4: per-category, per-merchant and per-member breakdowns for the
-- same this_month total, each checked by hand.
select is(
  (select amount_minor from v_category_spend where period = 'this_month' and category_slug = 'groceries'),
  1500::numeric,
  'v_category_spend: groceries this month is 1000+500 (A4)'
);
select is(
  (select amount_minor from v_category_spend where period = 'this_month' and category_slug = 'transport'),
  300::numeric,
  'v_category_spend: transport this month is the one unconfirmed transaction (A4)'
);
select is(
  (select amount_minor from v_merchant_spend where period = 'this_month' and merchant_name = 'Test Shop'),
  1800::numeric,
  'v_merchant_spend: the one merchant''s this-month total matches the household total (A4)'
);
select is(
  (select amount_minor from v_member_spend where period = 'this_month' and member_id = :a_id),
  1500::numeric,
  'v_member_spend: member A''s own this-month total excludes member B''s spending (A4)'
);

select * from finish();
rollback;
