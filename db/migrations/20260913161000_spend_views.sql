-- migrate:up

-- spec 0004 T2: the spend-view family, rebuilt on ADR 0045's period
-- vocabulary. Every row carries amount_minor, previous_amount_minor
-- (a column, never a second query -- R18), delta_minor, and the
-- unconfirmed share (R3). Transfers are excluded by construction: a
-- transfer has no expense-type posting at all, so filtering to
-- expense postings *is* the exclusion, never a flag checked by the
-- caller.
drop view v_period_spend;

create view v_period_spend with (security_invoker = true) as
select
  rp.period, rp.period_start, rp.period_end,
  coalesce(cur.amount_minor, 0) as amount_minor,
  coalesce(prev.amount_minor, 0) as previous_amount_minor,
  coalesce(cur.amount_minor, 0) - coalesce(prev.amount_minor, 0) as delta_minor,
  coalesce(cur.unconfirmed_amount_minor, 0) as unconfirmed_amount_minor,
  case when coalesce(cur.amount_minor, 0) = 0 then 0
       else round(coalesce(cur.unconfirmed_amount_minor, 0)::numeric / cur.amount_minor, 4)
  end as unconfirmed_share
from v_reporting_period rp
left join lateral (
  select sum(p.amount) as amount_minor,
         sum(p.amount) filter (where t.confirmation_state = 'unconfirmed') as unconfirmed_amount_minor
  from transaction t
  join posting p on p.transaction_id = t.id
  join account a on a.id = p.account_id
  where a.type = 'expense' and t.date between rp.period_start and rp.period_end
) cur on true
left join lateral (
  select sum(p.amount) as amount_minor
  from transaction t
  join posting p on p.transaction_id = t.id
  join account a on a.id = p.account_id
  where a.type = 'expense' and t.date between rp.previous_start and rp.previous_end
) prev on true;

comment on view v_period_spend is
  'Household spend for every period this household can be asked about (ADR 0045), transfers excluded by construction, with the previous period and the unconfirmed share as columns (R3, R18).';

create view v_category_spend with (security_invoker = true) as
select
  rp.period, rp.period_start, rp.period_end,
  cat.id as category_id, cat.name as category_slug,
  coalesce(cur.amount_minor, 0) as amount_minor,
  coalesce(prev.amount_minor, 0) as previous_amount_minor,
  coalesce(cur.amount_minor, 0) - coalesce(prev.amount_minor, 0) as delta_minor,
  coalesce(cur.unconfirmed_amount_minor, 0) as unconfirmed_amount_minor,
  case when coalesce(cur.amount_minor, 0) = 0 then 0
       else round(coalesce(cur.unconfirmed_amount_minor, 0)::numeric / cur.amount_minor, 4)
  end as unconfirmed_share
from v_reporting_period rp
cross join account cat
left join lateral (
  select sum(p.amount) as amount_minor,
         sum(p.amount) filter (where t.confirmation_state = 'unconfirmed') as unconfirmed_amount_minor
  from posting p
  join transaction t on t.id = p.transaction_id
  where p.account_id = cat.id and t.date between rp.period_start and rp.period_end
) cur on true
left join lateral (
  select sum(p.amount) as amount_minor
  from posting p
  join transaction t on t.id = p.transaction_id
  where p.account_id = cat.id and t.date between rp.previous_start and rp.previous_end
) prev on true
where cat.type = 'expense';

comment on view v_category_spend is
  'Spend per category for every reporting period (R2''s "by category" and "ranked" questions -- rank by ordering amount_minor descending, never a separate view).';

create view v_category_spend_by_month with (security_invoker = true) as
select
  cat.id as category_id, cat.name as category_slug,
  date_trunc('month', t.date)::date as month,
  sum(p.amount) as amount_minor,
  sum(p.amount) filter (where t.confirmation_state = 'unconfirmed') as unconfirmed_amount_minor
from account cat
join posting p on p.account_id = cat.id
join transaction t on t.id = p.transaction_id
where cat.type = 'expense'
group by cat.id, cat.name, date_trunc('month', t.date);

comment on view v_category_spend_by_month is
  'One category''s spend across every calendar month it has any -- the trend a period-scoped question cannot answer.';

create view v_merchant_spend with (security_invoker = true) as
select
  rp.period, rp.period_start, rp.period_end,
  m.id as merchant_id, m.name as merchant_name,
  coalesce(cur.amount_minor, 0) as amount_minor,
  coalesce(prev.amount_minor, 0) as previous_amount_minor,
  coalesce(cur.amount_minor, 0) - coalesce(prev.amount_minor, 0) as delta_minor,
  coalesce(cur.unconfirmed_amount_minor, 0) as unconfirmed_amount_minor,
  case when coalesce(cur.amount_minor, 0) = 0 then 0
       else round(coalesce(cur.unconfirmed_amount_minor, 0)::numeric / cur.amount_minor, 4)
  end as unconfirmed_share
from v_reporting_period rp
cross join merchant m
left join lateral (
  select sum(p.amount) as amount_minor,
         sum(p.amount) filter (where t.confirmation_state = 'unconfirmed') as unconfirmed_amount_minor
  from transaction t
  join posting p on p.transaction_id = t.id
  join account a on a.id = p.account_id
  where t.merchant_id = m.id and a.type = 'expense' and t.date between rp.period_start and rp.period_end
) cur on true
left join lateral (
  select sum(p.amount) as amount_minor
  from transaction t
  join posting p on p.transaction_id = t.id
  join account a on a.id = p.account_id
  where t.merchant_id = m.id and a.type = 'expense' and t.date between rp.previous_start and rp.previous_end
) prev on true;

comment on view v_merchant_spend is 'Spend per merchant for every reporting period.';

create view v_merchant_spend_by_month with (security_invoker = true) as
select
  m.id as merchant_id, m.name as merchant_name,
  date_trunc('month', t.date)::date as month,
  sum(p.amount) as amount_minor,
  sum(p.amount) filter (where t.confirmation_state = 'unconfirmed') as unconfirmed_amount_minor
from merchant m
join transaction t on t.merchant_id = m.id
join posting p on p.transaction_id = t.id
join account a on a.id = p.account_id
where a.type = 'expense'
group by m.id, m.name, date_trunc('month', t.date);

comment on view v_merchant_spend_by_month is 'One merchant''s spend across every calendar month it has any.';

create view v_member_spend with (security_invoker = true) as
select
  rp.period, rp.period_start, rp.period_end,
  mem.id as member_id,
  coalesce(cur.amount_minor, 0) as amount_minor,
  coalesce(prev.amount_minor, 0) as previous_amount_minor,
  coalesce(cur.amount_minor, 0) - coalesce(prev.amount_minor, 0) as delta_minor,
  coalesce(cur.unconfirmed_amount_minor, 0) as unconfirmed_amount_minor,
  case when coalesce(cur.amount_minor, 0) = 0 then 0
       else round(coalesce(cur.unconfirmed_amount_minor, 0)::numeric / cur.amount_minor, 4)
  end as unconfirmed_share
from v_reporting_period rp
cross join member mem
left join lateral (
  select sum(p.amount) as amount_minor,
         sum(p.amount) filter (where t.confirmation_state = 'unconfirmed') as unconfirmed_amount_minor
  from transaction t
  join posting p on p.transaction_id = t.id
  join account a on a.id = p.account_id
  where t.submitter = mem.id and a.type = 'expense' and t.date between rp.period_start and rp.period_end
) cur on true
left join lateral (
  select sum(p.amount) as amount_minor
  from transaction t
  join posting p on p.transaction_id = t.id
  join account a on a.id = p.account_id
  where t.submitter = mem.id and a.type = 'expense' and t.date between rp.previous_start and rp.previous_end
) prev on true;

comment on view v_member_spend is 'Spend per member (who submitted it) for every reporting period (ADR 0016: any member may ask about the whole household, this is what a "what did I spend" question filters to their own row).';

create view v_member_spend_by_month with (security_invoker = true) as
select
  mem.id as member_id,
  date_trunc('month', t.date)::date as month,
  sum(p.amount) as amount_minor,
  sum(p.amount) filter (where t.confirmation_state = 'unconfirmed') as unconfirmed_amount_minor
from member mem
join transaction t on t.submitter = mem.id
join posting p on p.transaction_id = t.id
join account a on a.id = p.account_id
where a.type = 'expense'
group by mem.id, date_trunc('month', t.date);

comment on view v_member_spend_by_month is 'One member''s spend across every calendar month they have any.';

grant select on
  v_period_spend, v_category_spend, v_category_spend_by_month,
  v_merchant_spend, v_merchant_spend_by_month, v_member_spend, v_member_spend_by_month
to hh_member, hh_agent, hh_admin;

-- migrate:down
revoke select on
  v_period_spend, v_category_spend, v_category_spend_by_month,
  v_merchant_spend, v_merchant_spend_by_month, v_member_spend, v_member_spend_by_month
from hh_member, hh_agent, hh_admin;

drop view v_member_spend_by_month;
drop view v_member_spend;
drop view v_merchant_spend_by_month;
drop view v_merchant_spend;
drop view v_category_spend_by_month;
drop view v_category_spend;
drop view v_period_spend;

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

grant select on v_period_spend to hh_member, hh_agent, hh_admin;
