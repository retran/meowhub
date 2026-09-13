-- migrate:up

comment on column posting.amount is
  'Signed, minor units. Asset and expense postings are positive when the household has or spends more; income, equity and liability postings are the mirror — negative when income arrives, an opening balance is set, or debt increases; positive when income is spent from, an opening entry is offset, or debt is paid down. Sums to zero per transaction (posting_balance_check). v_account_balance presents liability balances with the conventional positive-means-owed sign (ADR 0011) — the raw sign here is not that sign.';

-- A real bug found writing the seed: v_account_balance's headroom
-- formula for a liability subtracted the raw posting sum, which is only
-- correct if a liability's raw postings accumulate positively as debt
-- grows. They do not, and cannot, under this schema's single
-- signed-amount convention (ADR 0011): a card purchase posts the same
-- amount to the expense account (which must be positive, "spent more")
-- and to the card liability, and the two must sum to zero. The
-- liability posting is therefore negative when debt increases and
-- positive when it is paid down — the mirror of an asset, and the same
-- shape income and equity already use (a salary posts negative to
-- Income, an opening balance posts negative to Equity, both already
-- correct in the seed before this fix).
--
-- ADR 0011's stated convention ("positive = the household owes it") is
-- about the *displayed* balance, not the raw posting sign — so
-- v_account_balance now negates the raw sum for a liability row, and
-- headroom adds the raw sum (a more negative raw sum is more debt,
-- which correctly shrinks headroom).
create or replace view v_account_balance with (security_invoker = true) as
select
  a.id as account_id, a.name, a.type, a.currency,
  case when a.type = 'liability' then -coalesce(sum(p.amount), 0) else coalesce(sum(p.amount), 0) end as balance,
  coalesce(t.overdraft_limit, t.credit_limit) as limit_amount,
  case
    when a.type = 'asset' and t.overdraft_limit is not null
      then t.overdraft_limit + coalesce(sum(p.amount), 0)
    when a.type = 'liability' and t.credit_limit is not null
      then t.credit_limit + coalesce(sum(p.amount), 0)
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

comment on view v_account_balance is 'Balance, limit and headroom per account (data-model.md). Balance is always derived, never stored (R5). A liability''s raw postings accumulate negatively as debt grows; balance and headroom present the conventional positive-means-owed sign.';

-- migrate:down
create or replace view v_account_balance with (security_invoker = true) as
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
