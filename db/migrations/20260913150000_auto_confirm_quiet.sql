-- migrate:up

-- transaction_member_update_guard (T3) never anticipated hh_agent
-- having its own UPDATE path at all -- it assumes any non-admin actor
-- is an hh_member with a numeric meowhub.actor, and the auto-confirm
-- token below deliberately carries no member_id (no member is asking,
-- ADR 0042's "compose" shape). transaction_agent_confirm_guard, added
-- below, is what actually validates an hh_agent write; this guard
-- should step aside for hh_agent exactly as it already does for
-- hh_admin.
create or replace function transaction_member_update_guard()
returns trigger
language plpgsql
as $$
declare
  v_reclassify_only boolean;
  v_actor bigint;
begin
  if pg_has_role(current_user, 'hh_admin', 'member') or pg_has_role(current_user, 'hh_agent', 'member') then
    return new;
  end if;

  v_actor := nullif(current_setting('meowhub.actor', true), '')::bigint;

  -- project_id and note are never financial facts (R15a, R25): always
  -- allowed regardless of ownership or confirmation state.
  v_reclassify_only :=
    (new.date, new.merchant_id, new.model, new.prompt_version, new.original_amount,
     new.original_currency, new.source, new.confirmation_state, new.confirmation_route)
    is not distinct from
    (old.date, old.merchant_id, old.model, old.prompt_version, old.original_amount,
     old.original_currency, old.source, old.confirmation_state, old.confirmation_route);

  if v_reclassify_only then
    return new;
  end if;

  -- Anything else touches a financial fact or the confirmation state:
  -- only the capturing member, only while it is still unconfirmed
  -- (R7b/R7c/R12), and never to un-confirm what is already confirmed.
  if old.submitter is distinct from v_actor then
    raise exception 'transaction_member_update_guard: only the capturing member may correct or confirm their own transaction';
  end if;
  if old.confirmation_state = 'confirmed' then
    raise exception 'transaction_member_update_guard: a confirmed transaction may only be changed by an admin';
  end if;

  return new;
end;
$$;

-- R7c: a known merchant, its own category (not the model's guess),
-- below a configured threshold, past a configured quiet period — the
-- one case the agent may confirm on its own, without any member
-- asking (ADR 0042's "compose" shape, the same reasoning that already
-- lets hh_agent insert an unreviewed expense category unprompted,
-- ADR 0031). A narrow grant alone would let the agent confirm
-- anything; the guard below is what actually enforces R7c's own
-- conditions, re-checked at the database regardless of what the
-- calling workflow computed.
grant update (confirmation_state, confirmation_route, confirmed_at) on transaction to hh_agent;

create function transaction_agent_confirm_guard()
returns trigger
language plpgsql
as $$
declare
  v_threshold bigint;
  v_quiet_hours bigint;
  v_expense_amount bigint;
begin
  if pg_has_role(current_user, 'hh_agent', 'member') and not pg_has_role(current_user, 'hh_admin', 'member') then
    if old.confirmation_state <> 'unconfirmed'
      or new.confirmation_state <> 'confirmed'
      or new.confirmation_route <> 'quiet'
      or old.category_source is distinct from 'merchant_default'
    then
      raise exception 'transaction_agent_confirm_guard: the agent may only auto-confirm a known merchant''s own category, from unconfirmed to confirmed via the quiet route (R7c)';
    end if;

    select (value #>> '{}')::bigint into v_threshold
      from household_setting where key = 'auto_confirm_threshold_minor';
    select (value #>> '{}')::bigint into v_quiet_hours
      from household_setting where key = 'auto_confirm_quiet_period_hours';

    -- An unset threshold is the same as zero (spec 0003's own edge
    -- case: "An auto-confirm threshold set to zero: nothing
    -- auto-confirms") — never a default that quietly confirms
    -- everything just because the household never configured it.
    if v_threshold is null or v_threshold <= 0 or v_quiet_hours is null then
      raise exception 'transaction_agent_confirm_guard: auto-confirmation is not configured (R7c)';
    end if;

    select abs(amount) into v_expense_amount
      from posting where transaction_id = old.id and amount > 0
      order by amount desc limit 1;

    if v_expense_amount is null or v_expense_amount >= v_threshold then
      raise exception 'transaction_agent_confirm_guard: amount is not below the configured threshold (R7c)';
    end if;

    if old.created_at > now() - (v_quiet_hours || ' hours')::interval then
      raise exception 'transaction_agent_confirm_guard: the quiet period has not elapsed (R7c)';
    end if;
  end if;
  return new;
end;
$$;

create trigger transaction_agent_confirm_guard
  before update on transaction
  for each row execute function transaction_agent_confirm_guard();

comment on function transaction_agent_confirm_guard() is
  'The database, not the calling workflow, is what actually enforces R7c''s conditions on an hh_agent-driven auto-confirmation.';

-- The grant above is column-narrow already; this policy is broad on
-- purpose, the same shape as account_agent_insert_guard (ADR 0031) —
-- the guard trigger is what actually narrows what hh_agent may do.
create policy transaction_update_agent on transaction for update to hh_agent using (true) with check (true);

-- migrate:down
drop policy transaction_update_agent on transaction;
drop trigger transaction_agent_confirm_guard on transaction;
drop function transaction_agent_confirm_guard();
revoke update (confirmation_state, confirmation_route, confirmed_at) on transaction from hh_agent;

create or replace function transaction_member_update_guard()
returns trigger
language plpgsql
as $$
declare
  v_reclassify_only boolean;
  v_actor bigint;
begin
  if pg_has_role(current_user, 'hh_admin', 'member') then
    return new;
  end if;

  v_actor := nullif(current_setting('meowhub.actor', true), '')::bigint;

  v_reclassify_only :=
    (new.date, new.merchant_id, new.model, new.prompt_version, new.original_amount,
     new.original_currency, new.source, new.confirmation_state, new.confirmation_route)
    is not distinct from
    (old.date, old.merchant_id, old.model, old.prompt_version, old.original_amount,
     old.original_currency, old.source, old.confirmation_state, old.confirmation_route);

  if v_reclassify_only then
    return new;
  end if;

  if old.submitter is distinct from v_actor then
    raise exception 'transaction_member_update_guard: only the capturing member may correct or confirm their own transaction';
  end if;
  if old.confirmation_state = 'confirmed' then
    raise exception 'transaction_member_update_guard: a confirmed transaction may only be changed by an admin';
  end if;

  return new;
end;
$$;
