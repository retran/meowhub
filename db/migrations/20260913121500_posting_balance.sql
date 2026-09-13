-- migrate:up

-- The invariant (ADR 0011, spec 0003 T2): a transaction's postings sum to
-- zero. Deferred, not immediate — a transaction is written as several
-- posting rows, and an immediate per-row check would reject the first
-- one every time. Deferred to commit (or SET CONSTRAINTS ALL IMMEDIATE)
-- means the whole write is legal mid-statement and illegal only if it is
-- still unbalanced when it matters.
create function posting_balance_check()
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

create constraint trigger posting_balance_check
  after insert or update or delete on posting
  deferrable initially deferred
  for each row execute function posting_balance_check();

-- migrate:down
drop trigger if exists posting_balance_check on posting;
drop function if exists posting_balance_check();
