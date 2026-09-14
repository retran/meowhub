-- migrate:up

-- spec 0004 T3: what the household owes, and its net position. Both
-- read straight off v_account_balance (spec 0003 T5), which already
-- carries the conventional positive-means-owed sign and the derived
-- headroom -- neither view stores a figure, both derive it, same as
-- R5 already requires everywhere else.
create view v_liability_summary with (security_invoker = true) as
select account_id, name, balance as balance_minor, limit_amount as limit_minor, headroom as headroom_minor
from v_account_balance
where type = 'liability'
union all
select null, 'Total', sum(balance), sum(limit_amount), sum(headroom)
from v_account_balance
where type = 'liability';

comment on view v_liability_summary is
  'What is owed, per liability and in total (the row with account_id null) -- R2''s "what it owes" and "headroom" questions.';

create view v_household_position with (security_invoker = true) as
select
  coalesce(sum(balance) filter (where type = 'asset'), 0) as holdings_minor,
  coalesce(sum(balance) filter (where type = 'liability'), 0) as owed_minor,
  coalesce(sum(balance) filter (where type = 'asset'), 0) - coalesce(sum(balance) filter (where type = 'liability'), 0) as net_position_minor
from v_account_balance;

comment on view v_household_position is
  'What the household holds in total, what it owes in total, and its net position -- one row, R2''s "state of the accounts" questions.';

grant select on v_liability_summary, v_household_position to hh_member, hh_agent, hh_admin;

-- migrate:down
revoke select on v_liability_summary, v_household_position from hh_member, hh_agent, hh_admin;
drop view v_household_position;
drop view v_liability_summary;
