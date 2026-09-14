-- migrate:up

-- R19 asks for matching transactions "with their dates and amounts", and
-- the search view was returning dates without amounts -- which makes the
-- agent either answer half the question or reach for a second tool to
-- finish it. The amount belongs in the row that is already being read.
--
-- The amount is the expense side of the transaction, the same side
-- v_period_spend totals, so a searched figure and a reported one are the
-- same number by construction. A transfer has no expense posting and so
-- reports null rather than a misleading zero.
drop view v_transaction_search;

create view v_transaction_search with (security_invoker = true) as
select
  t.id as transaction_id, t.date, t.note, m.name as merchant_name,
  (
    select sum(p.amount) from posting p
    join account a on a.id = p.account_id
    where p.transaction_id = t.id and a.type = 'expense'
  ) as amount_minor,
  (
    select p.currency from posting p
    join account a on a.id = p.account_id
    where p.transaction_id = t.id and a.type = 'expense'
    limit 1
  ) as currency,
  immutable_unaccent(
    coalesce(t.note, '') || ' ' || coalesce(m.name, '') || ' ' ||
    coalesce((select string_agg(c.raw_text, ' ') from capture c where c.transaction_id = t.id), '')
  ) as searchable_text
from transaction t
left join merchant m on m.id = t.merchant_id;

comment on view v_transaction_search is
  'One row per transaction with everything free-text about it concatenated (its note, its merchant, every capture message that produced or touched it) and the expense amount it came to -- filter with `searchable_text ilike ...` or `%` similarity, both backed by the trigram indexes (R19).';

grant select on v_transaction_search to hh_member, hh_agent, hh_admin;

-- migrate:down
drop view v_transaction_search;

create view v_transaction_search with (security_invoker = true) as
select
  t.id as transaction_id, t.date, t.note, m.name as merchant_name,
  immutable_unaccent(
    coalesce(t.note, '') || ' ' || coalesce(m.name, '') || ' ' ||
    coalesce((select string_agg(c.raw_text, ' ') from capture c where c.transaction_id = t.id), '')
  ) as searchable_text
from transaction t
left join merchant m on m.id = t.merchant_id;

grant select on v_transaction_search to hh_member, hh_agent, hh_admin;
