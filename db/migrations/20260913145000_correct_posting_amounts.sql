-- migrate:up

-- Correcting an amount touches both legs of a transaction at once, in
-- one commit -- posting_balance_check is deferred to commit, so two
-- separate PostgREST PATCH requests (each its own transaction) commit
-- the first leg alone, sees an unbalanced transaction at ITS OWN
-- commit, and fails right there (a real bug found writing spec 0003
-- T11's test). Not SECURITY DEFINER: each update below still runs as
-- the calling role, so posting_admin/posting_update_member and
-- posting_member_update_guard apply exactly as they do to a direct
-- PATCH -- this only makes the two writes atomic, it grants nothing.
create function correct_posting_amounts(p_transaction_id bigint, p_new_amount_minor bigint)
returns void
language plpgsql
as $$
declare
  r record;
begin
  for r in select id, amount from posting where transaction_id = p_transaction_id loop
    if r.amount < 0 then
      update posting set amount = -p_new_amount_minor where id = r.id;
    else
      update posting set amount = p_new_amount_minor where id = r.id;
    end if;
  end loop;
end;
$$;

comment on function correct_posting_amounts(bigint, bigint) is
  'Corrects both legs of a transaction to a new magnitude in one commit (R15). Not SECURITY DEFINER -- RLS and posting_member_update_guard still apply per row, as the calling role.';

grant execute on function correct_posting_amounts(bigint, bigint) to hh_admin, hh_member;

-- migrate:down
revoke execute on function correct_posting_amounts(bigint, bigint) from hh_admin, hh_member;
drop function correct_posting_amounts(bigint, bigint);
