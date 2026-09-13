-- migrate:up

-- Two more real gaps found while writing this slice's views:
-- v_transaction_detail must say where a category came from (data-model.md's
-- own wording for the view), and v_unconfirmed must say which fields were
-- inferred rather than stated (added to the catalogue during planning).
-- Neither had anywhere to live.
alter table transaction add column category_source text check (category_source in ('merchant_default', 'model', 'manual'));
alter table transaction add column inferred_fields text[] not null default '{}';

comment on column transaction.category_source is
  'Where the category posting''s account came from: the merchant''s established default (no model call, R13), the model''s own guess, or set by hand.';
comment on column transaction.inferred_fields is
  'Which fields the member did not state and the system filled in — amount, merchant, category, account, date. The screens mark these (data-model.md); an empty array means nothing was inferred.';

-- Every view below is WITH (security_invoker = true) (data-model.md's own
-- rule): it runs with the calling role's rights, so it can never show a
-- row that role could not reach directly. R9 already grants
-- hh_member/hh_agent/hh_admin unrestricted read on account/transaction/
-- posting (T3), so nothing is lost by reading through the view instead
-- of the table. hh_report gets none of these yet — its own view-only
-- reporting shape is spec 0004's decision to make, not assumed here.

create view v_account with (security_invoker = true) as
select
  a.id, a.type, a.name, a.currency, a.parent_id, a.active, a.reviewed,
  t.overdraft_limit, t.credit_limit, t.interest_rate, t.payment_amount,
  t.payment_day, t.effective_from as term_effective_from
from account a
left join lateral (
  select * from account_term term
  where term.account_id = a.id and term.effective_from <= current_date
  order by term.effective_from desc
  limit 1
) t on true;

comment on view v_account is 'The chart, each account with its current term (data-model.md).';

create view v_account_balance with (security_invoker = true) as
select
  a.id as account_id, a.name, a.type, a.currency,
  coalesce(sum(p.amount), 0) as balance,
  coalesce(t.overdraft_limit, t.credit_limit) as limit_amount,
  case
    when a.type = 'asset' and t.overdraft_limit is not null
      then t.overdraft_limit + coalesce(sum(p.amount), 0)
    when a.type = 'liability' and t.credit_limit is not null
      then t.credit_limit - coalesce(sum(p.amount), 0)
    else null
  end as headroom
from account a
left join posting p on p.account_id = a.id
left join lateral (
  select * from account_term term
  where term.account_id = a.id and term.effective_from <= current_date
  order by term.effective_from desc
  limit 1
) t on true
group by a.id, a.name, a.type, a.currency, t.overdraft_limit, t.credit_limit;

comment on view v_account_balance is 'Balance, limit and headroom per account (data-model.md). Balance is always derived, never stored (R5).';

create view v_category with (security_invoker = true) as
select
  a.id, a.name as slug, a.parent_id, a.active, a.reviewed,
  tr.language, tr.display_name
from account a
join translation tr on tr.slug = a.name
where a.type = 'expense';

comment on view v_category is 'Expense accounts as categories, with display names per language (data-model.md). A category is an expense account (ADR 0031) — filter by language for one member''s reply.';

create view v_period_spend with (security_invoker = true) as
select
  date_trunc('month', t.date)::date as period_start,
  sum(p.amount) filter (where a.type = 'expense') as spend,
  sum(p.amount) filter (where a.type = 'expense' and t.confirmation_state = 'unconfirmed') as unconfirmed_spend,
  count(*) filter (where a.type = 'expense') as transaction_count
from transaction t
join posting p on p.transaction_id = t.id
join account a on a.id = p.account_id
where a.type = 'expense'
group by 1;

comment on view v_period_spend is 'Spend by month, transfers excluded by construction (a transfer has no expense-type posting), with the unconfirmed share (data-model.md, ADR 0023).';

create view v_transaction_detail with (security_invoker = true) as
select
  t.id, t.date, t.note, t.project_id, t.submitter, t.source,
  t.confirmation_state, t.confirmation_route, t.confirmed_by, t.confirmed_at,
  t.model, t.prompt_version, t.original_amount, t.original_currency,
  t.category_source, t.inferred_fields,
  m.id as merchant_id, m.name as merchant_name,
  (
    select account_id from posting
    where transaction_id = t.id
      and account_id in (select id from account where type = 'expense')
    limit 1
  ) as category_account_id
from transaction t
left join merchant m on m.id = t.merchant_id;

comment on view v_transaction_detail is 'One transaction with its provenance and where its category came from (data-model.md, spec 0004''s "why this category").';

create view v_unconfirmed with (security_invoker = true) as
select
  t.id, t.date, t.submitter, t.merchant_id, t.category_source,
  t.inferred_fields, t.created_at,
  extract(epoch from (now() - t.created_at)) / 3600 as age_hours
from transaction t
where t.confirmation_state = 'unconfirmed';

comment on view v_unconfirmed is 'The review queue (ADR 0023), with which fields were inferred rather than stated.';

create view v_unconfirmed_summary with (security_invoker = true) as
select
  count(*) as unconfirmed_count,
  max(extract(epoch from (now() - created_at)) / 3600) as oldest_age_hours
from transaction
where confirmation_state = 'unconfirmed';

comment on view v_unconfirmed_summary is 'The queue''s count and oldest age (data-model.md) — the ceiling alert reads this.';

grant select on
  v_account, v_account_balance, v_category, v_period_spend,
  v_transaction_detail, v_unconfirmed, v_unconfirmed_summary
to hh_member, hh_agent, hh_admin;

-- migrate:down
revoke select on
  v_account, v_account_balance, v_category, v_period_spend,
  v_transaction_detail, v_unconfirmed, v_unconfirmed_summary
from hh_member, hh_agent, hh_admin;

drop view if exists v_unconfirmed_summary;
drop view if exists v_unconfirmed;
drop view if exists v_transaction_detail;
drop view if exists v_period_spend;
drop view if exists v_category;
drop view if exists v_account_balance;
drop view if exists v_account;

alter table transaction drop column inferred_fields;
alter table transaction drop column category_source;
