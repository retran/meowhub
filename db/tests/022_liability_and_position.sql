-- pgTAP: v_liability_summary and v_household_position (spec 0004 T3),
-- A5 (balance equals the independent sum of postings) and A5a
-- (holdings, owed, net position and headroom each answered from their
-- own view, headroom naming the limit it is measured against).
begin;
select plan(6);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id \gset admin_
insert into account (type, name) values ('asset', 'Assets:Checking') returning id \gset checking_
insert into account (type, name) values ('liability', 'Liabilities:Card') returning id \gset card_
insert into account (type, name) values ('expense', 'groceries') returning id \gset groceries_
insert into account (type, name) values ('equity', 'Opening Balances') returning id \gset equity_
insert into account_term (account_id, credit_limit, effective_from) values (:card_id, 300000, current_date);

set role hh_agent;

-- Opening balances: 200000 in checking, nothing owed yet.
insert into transaction (date, submitter, source) values (current_date, :admin_id, 'manual') returning id \gset open_
insert into posting (transaction_id, account_id, amount, currency) values (:open_id, :checking_id, 200000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:open_id, :equity_id, -200000, 'EUR');

-- A card purchase: 5000 owed on the card.
insert into transaction (date, submitter, source) values (current_date, :admin_id, 'text') returning id \gset purchase_
insert into posting (transaction_id, account_id, amount, currency) values (:purchase_id, :card_id, -5000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:purchase_id, :groceries_id, 5000, 'EUR');

reset role;

-- A5: v_account_balance's own figure equals the independent sum of postings.
select is(
  (select sum(amount)::numeric from posting where account_id = :'checking_id'),
  (select balance::numeric from v_account_balance where account_id = :'checking_id'),
  'v_account_balance''s checking balance equals the independent sum of its postings (A5)'
);

-- A5a: per-liability and total-owed, both from v_liability_summary.
select is(
  (select balance_minor from v_liability_summary where account_id = :'card_id'),
  5000::numeric,
  'v_liability_summary states what is owed on the one liability (A5a)'
);
select is(
  (select balance_minor from v_liability_summary where account_id is null),
  5000::numeric,
  'v_liability_summary''s total row equals the sum across liabilities (A5a)'
);

-- A5a: headroom names the limit it is measured against (300000 limit, 5000 owed -> 295000 headroom).
select is(
  (select headroom_minor from v_liability_summary where account_id = :'card_id'),
  295000::numeric,
  'the headroom figure is measured against the card''s own 300000 limit (A5a)'
);

-- A5a: holdings, owed and net position from v_household_position.
select is(
  (select holdings_minor from v_household_position),
  200000::numeric,
  'v_household_position states what the household holds in total (A5a)'
);
select is(
  (select net_position_minor from v_household_position),
  195000::numeric,
  'v_household_position''s net position is holdings minus what is owed (A5a)'
);

select * from finish();
rollback;
