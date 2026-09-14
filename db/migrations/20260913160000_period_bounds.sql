-- migrate:up

-- ADR 0045: a period is chosen from a fixed vocabulary and resolved to
-- date bounds by SQL alone -- the model never produces or reasons
-- about a date, and no workflow computes a period-over-period delta.
-- Bounds are inclusive on both ends, in the household's own timezone.
create function period_bounds(p_period text, p_tz text)
returns table (period text, period_start date, period_end date, previous_start date, previous_end date)
language plpgsql
as $$
declare
  v_today date := (now() at time zone p_tz)::date;
  v_start date;
  v_end date;
  v_prev_start date;
  v_prev_end date;
  v_month text;
begin
  if p_period = 'this_month' then
    v_start := date_trunc('month', v_today)::date;
    v_end := (date_trunc('month', v_today) + interval '1 month - 1 day')::date;
    v_prev_start := (v_start - interval '1 month')::date;
    v_prev_end := (v_start - interval '1 day')::date;

  elsif p_period = 'last_month' then
    v_start := (date_trunc('month', v_today) - interval '1 month')::date;
    v_end := (date_trunc('month', v_today) - interval '1 day')::date;
    v_prev_start := (v_start - interval '1 month')::date;
    v_prev_end := (v_start - interval '1 day')::date;

  elsif p_period like 'month_of:%' then
    v_month := substring(p_period from 10);
    v_start := to_date(v_month || '-01', 'YYYY-MM-DD');
    v_end := (v_start + interval '1 month - 1 day')::date;
    v_prev_start := (v_start - interval '1 month')::date;
    v_prev_end := (v_start - interval '1 day')::date;

  elsif p_period = 'this_year' then
    v_start := date_trunc('year', v_today)::date;
    v_end := (date_trunc('year', v_today) + interval '1 year - 1 day')::date;
    v_prev_start := (v_start - interval '1 year')::date;
    v_prev_end := (v_start - interval '1 day')::date;

  elsif p_period = 'last_year' then
    v_start := (date_trunc('year', v_today) - interval '1 year')::date;
    v_end := (date_trunc('year', v_today) - interval '1 day')::date;
    v_prev_start := (v_start - interval '1 year')::date;
    v_prev_end := (v_start - interval '1 day')::date;

  elsif p_period = 'last_7_days' then
    v_end := v_today;
    v_start := (v_today - interval '6 days')::date;
    v_prev_end := (v_start - interval '1 day')::date;
    v_prev_start := (v_prev_end - interval '6 days')::date;

  elsif p_period = 'last_30_days' then
    v_end := v_today;
    v_start := (v_today - interval '29 days')::date;
    v_prev_end := (v_start - interval '1 day')::date;
    v_prev_start := (v_prev_end - interval '29 days')::date;

  else
    raise exception 'period_bounds: % is not a period this household can be asked about', p_period;
  end if;

  return query select p_period, v_start, v_end, v_prev_start, v_prev_end;
end;
$$;

comment on function period_bounds(text, text) is
  'ADR 0045: the one place a reporting period becomes date bounds, in the household''s own timezone, including the matching previous period.';

-- The six fixed periods plus the last 25 calendar months (this month
-- back through 24 prior) as month_of:YYYY-MM rows -- bounded and
-- cheap, so every spend view can join this once rather than call
-- period_bounds per question. A month older than that is a refusal
-- (R6, ADR 0045's own accepted tradeoff), not a guess.
create view v_reporting_period with (security_invoker = true) as
select pb.*
from household_setting hs
cross join lateral (
  values ('this_month'), ('last_month'), ('this_year'), ('last_year'), ('last_7_days'), ('last_30_days')
) as fixed(period)
cross join lateral period_bounds(fixed.period, hs.value #>> '{}') as pb
where hs.key = 'timezone'
union all
select pb.*
from household_setting hs
cross join lateral generate_series(0, 24) as months_back
cross join lateral (
  select 'month_of:' || to_char(date_trunc('month', (now() at time zone (hs.value #>> '{}'))::date) - (months_back || ' months')::interval, 'YYYY-MM')
) as m(period)
cross join lateral period_bounds(m.period, hs.value #>> '{}') as pb
where hs.key = 'timezone';

comment on view v_reporting_period is
  'ADR 0045: every period this household can currently be asked about, with its bounds and its previous period''s bounds, joined once rather than resolved per question.';

grant select on v_reporting_period to hh_member, hh_agent, hh_admin;

-- migrate:down
revoke select on v_reporting_period from hh_member, hh_agent, hh_admin;
drop view v_reporting_period;
drop function period_bounds(text, text);
