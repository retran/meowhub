-- migrate:up

-- A real bug found deleting a transaction outside a test's own rollback:
-- posting_balance_check compared sum(amount) to 0 with IS DISTINCT FROM,
-- which treats "no postings remain at all" (NULL, once every posting for
-- a deleted transaction is gone) as distinct from zero and raises. Every
-- pgTAP test that proved a delete "lives_ok" never actually hit this,
-- because pgTAP rolls back before a deferred constraint trigger ever
-- fires at a real commit. A transaction with zero postings left is not
-- unbalanced — there is nothing left to balance — so this is a false
-- positive, not the invariant working.
create or replace function posting_balance_check()
returns trigger
language plpgsql
as $$
declare
  v_transaction_id bigint;
  v_sum bigint;
begin
  v_transaction_id := coalesce(new.transaction_id, old.transaction_id);
  select sum(amount) into v_sum from posting where transaction_id = v_transaction_id;
  if v_sum is not null and v_sum <> 0 then
    raise exception 'posting_balance_check: transaction % has postings summing to % instead of 0', v_transaction_id, v_sum;
  end if;
  return null;
end;
$$;

-- migrate:down
create or replace function posting_balance_check()
returns trigger
language plpgsql
as $$
declare
  v_transaction_id bigint;
  v_sum bigint;
begin
  v_transaction_id := coalesce(new.transaction_id, old.transaction_id);
  select sum(amount) into v_sum from posting where transaction_id = v_transaction_id;
  if v_sum is distinct from 0 then
    raise exception 'posting_balance_check: transaction % has postings summing to % instead of 0', v_transaction_id, v_sum;
  end if;
  return null;
end;
$$;
