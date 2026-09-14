-- migrate:up

-- spec 0004 T7: R2's "movement" questions -- what changed on an account
-- over a period, and what the largest expenses in a period were.
-- Neither is answerable from v_transaction_detail, which carries one
-- row per transaction with no account and no amount: a movement
-- question is about postings, and the tools that claimed to read it
-- could not have worked.
--
-- One view serves both, because they are the same query with a
-- different filter and order: movement filters by account name and
-- orders by date; largest expenses filters to expense postings and
-- orders by amount.
create view v_account_movement with (security_invoker = true) as
select
  p.id as posting_id,
  p.transaction_id,
  t.date,
  p.account_id,
  a.name as account_name,
  a.type as account_type,
  p.amount as amount_minor,
  p.currency,
  t.note,
  m.name as merchant_name,
  t.submitter,
  t.confirmation_state
from posting p
join transaction t on t.id = p.transaction_id
join account a on a.id = p.account_id
left join merchant m on m.id = t.merchant_id;

comment on view v_account_movement is
  'One row per posting with its account, date, amount and merchant: R2''s "what changed on this account" and "what were the largest expenses" questions. Filter by account_name and date for the first, by account_type = expense and amount for the second.';

grant select on v_account_movement to hh_member, hh_agent, hh_admin;

-- migrate:down
revoke select on v_account_movement from hh_member, hh_agent, hh_admin;
drop view v_account_movement;
