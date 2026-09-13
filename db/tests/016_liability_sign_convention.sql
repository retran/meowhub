-- pgTAP: a liability's raw postings accumulate negatively as debt grows
-- (spec 0003, found via the seed) — v_account_balance must still present
-- the conventional positive-means-owed sign (ADR 0011), and headroom
-- must shrink as debt grows, not the reverse.
begin;
select plan(4);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id \gset mem_
insert into account (type, name) values ('liability', 'Liabilities:Test Card') returning id \gset card_
insert into account (type, name) values ('expense', 'dining') returning id \gset dining_
insert into account (type, name) values ('asset', 'Assets:Test Bank') returning id \gset bank_
insert into account_term (account_id, credit_limit, effective_from) values (:card_id, 100000, current_date);

set role hh_agent;

-- A purchase: the expense is positive (spent more); the card posting is
-- negative (owe more) — the mirror, not the same sign.
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'text') returning id \gset purchase_
insert into posting (transaction_id, account_id, amount, currency) values (:purchase_id, :card_id, -3000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:purchase_id, :dining_id, 3000, 'EUR');

select is(
  (select balance from v_account_balance where account_id = :card_id),
  3000::numeric,
  'a 30.00 purchase shows as 30.00 owed, the conventional positive sign (ADR 0011)'
);
select is(
  (select headroom from v_account_balance where account_id = :card_id),
  97000::numeric,
  'headroom shrinks by the purchase amount'
);

-- A payment: the bank posting is negative (paid out); the card posting
-- is positive (owes less) — reducing debt is the opposite raw sign.
insert into transaction (date, submitter, source) values (current_date, :mem_id, 'text') returning id \gset payment_
insert into posting (transaction_id, account_id, amount, currency) values (:payment_id, :bank_id, -1000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:payment_id, :card_id, 1000, 'EUR');

select is(
  (select balance from v_account_balance where account_id = :card_id),
  2000::numeric,
  'paying 10.00 toward the card reduces what is owed to 20.00'
);
select is(
  (select headroom from v_account_balance where account_id = :card_id),
  98000::numeric,
  'headroom grows back as the debt is paid down'
);

reset role;
select * from finish();
rollback;
