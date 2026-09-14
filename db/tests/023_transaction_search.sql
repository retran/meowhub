-- pgTAP: v_transaction_search (spec 0004 T4), A18 -- a word from a
-- transaction's note, or from the raw capture message that produced
-- it, finds that transaction.
begin;
select plan(4);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id \gset a_
insert into account (type, name) values ('asset', 'Assets:Test') returning id \gset asset_
insert into account (type, name) values ('expense', 'groceries') returning id \gset groceries_
insert into merchant (name) values ('Albert Heijn') returning id \gset merchant_

set role hh_agent;
insert into transaction (date, submitter, source, merchant_id, note)
  values (current_date, :a_id, 'text', :merchant_id, 'подарок Маше') returning id \gset noted_
insert into posting (transaction_id, account_id, amount, currency) values (:noted_id, :asset_id, -350, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:noted_id, :groceries_id, 350, 'EUR');
insert into capture (member_id, chat_id, kind, direction, sequence, raw_text, state, transaction_id)
  values (:a_id, '123', 'text', 'inbound', 1, 'coffee 350, gift for the office', 'resolved', :noted_id);

insert into transaction (date, submitter, source, merchant_id)
  values (current_date, :a_id, 'text', :merchant_id) returning id \gset unrelated_
insert into posting (transaction_id, account_id, amount, currency) values (:unrelated_id, :asset_id, -1200, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:unrelated_id, :groceries_id, 1200, 'EUR');
reset role;

-- A18: a word from the note finds the transaction (accent-insensitive:
-- the note is Russian, the search below is typed without it mattering).
select is(
  (select transaction_id from v_transaction_search where searchable_text ilike '%маше%'),
  :noted_id::bigint,
  'a word from the transaction''s own note finds it (A18)'
);

-- A18: a word from the raw capture message finds the same transaction.
select is(
  (select transaction_id from v_transaction_search where searchable_text ilike '%office%'),
  :noted_id::bigint,
  'a word from the raw capture message that produced the transaction finds it (A18)'
);

-- The merchant name finds every transaction at it, not only the noted one.
select is(
  (select count(*)::int from v_transaction_search where searchable_text ilike '%albert heijn%'),
  2,
  'the merchant name finds every transaction at it'
);

-- A word present nowhere finds nothing.
select is(
  (select count(*)::int from v_transaction_search where searchable_text ilike '%nonexistentword%'),
  0,
  'a word present in nothing returns nothing'
);

select * from finish();
rollback;
