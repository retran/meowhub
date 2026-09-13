-- migrate:up

-- A real gap found while writing this migration: nothing in T1 gave a
-- transaction a merchant. R9 extracts one from every capture and R15
-- must be able to correct it, so it is a column, not something derived.
alter table transaction add column merchant_id bigint references merchant (id);

alter table account          enable row level security;
alter table account          force row level security;
alter table account_term     enable row level security;
alter table account_term     force row level security;
alter table transaction      enable row level security;
alter table transaction      force row level security;
alter table posting          enable row level security;
alter table posting          force row level security;
alter table merchant         enable row level security;
alter table merchant         force row level security;
alter table merchant_alias   enable row level security;
alter table merchant_alias   force row level security;
alter table translation      enable row level security;
alter table translation      force row level security;
alter table household_setting enable row level security;
alter table household_setting force row level security;

-- account: everyone reads the chart (R9, spec 0002). Structural writes —
-- opening, renaming, deactivating, re-terming — are always a member's own
-- request and run as that member's own role (ADR 0042's "acts_as"), so
-- they need hh_admin's own grant, never hh_agent's. The one exception is
-- ADR 0031's unprompted case: the agent creates an expense-type category
-- it met and could not place, which is its own composition, not a
-- request — enforced by the guard below, not by the grant alone.
grant select on account to hh_member, hh_agent, hh_admin;
grant insert, update on account to hh_admin;
grant insert on account to hh_agent;

create function account_agent_insert_guard()
returns trigger
language plpgsql
as $$
begin
  if pg_has_role(current_user, 'hh_agent', 'member') and not pg_has_role(current_user, 'hh_admin', 'member') then
    if new.type <> 'expense' or new.reviewed then
      raise exception 'account_agent_insert_guard: the agent may only create an unreviewed expense category unprompted (ADR 0031)';
    end if;
  end if;
  return new;
end;
$$;

create trigger account_agent_insert_guard
  before insert on account
  for each row execute function account_agent_insert_guard();

create policy account_select on account for select to hh_member, hh_agent, hh_admin using (true);
create policy account_admin  on account for all    to hh_admin using (true) with check (true);
create policy account_insert_agent on account for insert to hh_agent with check (true);

-- account_term: append-only for everyone (deny_mutation, T1); a new term
-- is always an admin's own structural request.
grant select on account_term to hh_member, hh_agent, hh_admin;
grant insert on account_term to hh_admin;

create policy account_term_select on account_term for select to hh_member, hh_agent, hh_admin using (true);
create policy account_term_insert on account_term for insert to hh_admin with check (true);

-- transaction: everyone reads the whole ledger (R9, spec 0002). Only the
-- agent inserts a raw one, composing a capture (R13, spec 0002 — no
-- member writes a raw posting under any role, and a transaction is
-- written with its postings as one act). An admin may change or delete
-- any recorded transaction (R10). A member may always reclassify
-- (project_id) and annotate (note) any transaction — that is not a
-- financial fact (R11/R15a, ADR 0021) — and may correct a financial fact
-- or confirm/un-confirm only their own capture while it is still
-- unconfirmed (R12/R7b/R7c). Two rules on overlapping columns, which a
-- policy alone cannot express (a policy sees one row version, not which
-- columns a statement touches) — the guard below is the actual gate; the
-- policy only says hh_member may attempt an update at all.
grant select on transaction to hh_member, hh_agent, hh_admin;
grant insert on transaction to hh_agent;
grant update, delete on transaction to hh_admin;
grant update (project_id, note, confirmation_state, confirmation_route, confirmed_by, confirmed_at, date, merchant_id, model, prompt_version, original_amount, original_currency, source) on transaction to hh_member;

create function transaction_member_update_guard()
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

create trigger transaction_member_update_guard
  before update on transaction
  for each row execute function transaction_member_update_guard();

create policy transaction_select on transaction for select to hh_member, hh_agent, hh_admin using (true);
create policy transaction_insert_agent on transaction for insert to hh_agent with check (true);
create policy transaction_update_member on transaction for update to hh_member using (true) with check (true);
create policy transaction_admin on transaction for all to hh_admin using (true) with check (true);

-- posting: everyone reads (R9); only the agent inserts a raw one (R13);
-- an admin changes or deletes any posting (R10); a member reclassifies
-- (account_id, to another expense-type account) unconditionally, and
-- corrects amount/currency only on their own transaction while it is
-- still unconfirmed — the same shape as transaction, checked against the
-- posting's own transaction row since ownership and confirmation state
-- live there, not on posting itself.
grant select on posting to hh_member, hh_agent, hh_admin;
grant insert on posting to hh_agent;
grant update, delete on posting to hh_admin;
grant update (account_id, amount, currency) on posting to hh_member;

create function posting_member_update_guard()
returns trigger
language plpgsql
as $$
declare
  v_actor bigint;
  v_txn record;
  v_reclassify_only boolean;
begin
  if pg_has_role(current_user, 'hh_admin', 'member') then
    return new;
  end if;

  v_reclassify_only := (new.amount, new.currency) is not distinct from (old.amount, old.currency);

  if v_reclassify_only then
    -- Reclassification only makes sense onto another expense-type account.
    if not exists (select 1 from account where id = new.account_id and type = 'expense') then
      raise exception 'posting_member_update_guard: a member may only reclassify a posting onto an expense-type account';
    end if;
    return new;
  end if;

  v_actor := nullif(current_setting('meowhub.actor', true), '')::bigint;
  select submitter, confirmation_state into v_txn from transaction where id = old.transaction_id;

  if v_txn.submitter is distinct from v_actor then
    raise exception 'posting_member_update_guard: only the capturing member may correct their own posting';
  end if;
  if v_txn.confirmation_state = 'confirmed' then
    raise exception 'posting_member_update_guard: a posting on a confirmed transaction may only be changed by an admin';
  end if;

  return new;
end;
$$;

create trigger posting_member_update_guard
  before update on posting
  for each row execute function posting_member_update_guard();

create policy posting_select on posting for select to hh_member, hh_agent, hh_admin using (true);
create policy posting_insert_agent on posting for insert to hh_agent with check (true);
create policy posting_update_member on posting for update to hh_member using (true) with check (true);
create policy posting_admin on posting for all to hh_admin using (true) with check (true);

-- merchant / merchant_alias: everyone reads; the agent composes a new
-- merchant and its first alias while capturing (R12), and may update a
-- merchant's own learned default category as it captures more; merging
-- and deactivating merchants is always admin-requested (R10).
grant select on merchant to hh_member, hh_agent, hh_admin;
grant insert on merchant to hh_agent, hh_admin;
grant update on merchant to hh_admin;
grant update (default_category_id) on merchant to hh_agent;

create policy merchant_select on merchant for select to hh_member, hh_agent, hh_admin using (true);
create policy merchant_insert_agent on merchant for insert to hh_agent with check (true);
create policy merchant_update_agent on merchant for update to hh_agent using (true) with check (true);
create policy merchant_admin on merchant for all to hh_admin using (true) with check (true);

grant select on merchant_alias to hh_member, hh_agent, hh_admin;
grant insert on merchant_alias to hh_agent, hh_admin;
grant update on merchant_alias to hh_admin;

create policy merchant_alias_select on merchant_alias for select to hh_member, hh_agent, hh_admin using (true);
create policy merchant_alias_insert_agent on merchant_alias for insert to hh_agent with check (true);
create policy merchant_alias_admin on merchant_alias for all to hh_admin using (true) with check (true);

-- translation: everyone reads (every reply needs it); the agent inserts
-- provisional display names for a category it just created (ADR 0031);
-- an admin curates wording for anything, including what the agent
-- proposed.
grant select on translation to hh_member, hh_agent, hh_admin;
grant insert on translation to hh_agent, hh_admin;
grant update on translation to hh_admin;

create policy translation_select on translation for select to hh_member, hh_agent, hh_admin using (true);
create policy translation_insert_agent on translation for insert to hh_agent with check (true);
create policy translation_admin on translation for all to hh_admin using (true) with check (true);

-- household_setting: everyone reads (a member's own reply may depend on
-- the household's timezone or currency); only an admin writes — the
-- setup conversation is always an admin's own request (R0), so it always
-- runs as hh_admin, never hh_agent.
grant select on household_setting to hh_member, hh_agent, hh_admin;
grant insert, update on household_setting to hh_admin;

create policy household_setting_select on household_setting for select to hh_member, hh_agent, hh_admin using (true);
create policy household_setting_admin on household_setting for all to hh_admin using (true) with check (true);

-- migrate:down
drop policy if exists household_setting_admin on household_setting;
drop policy if exists household_setting_select on household_setting;
drop policy if exists translation_admin on translation;
drop policy if exists translation_insert_agent on translation;
drop policy if exists translation_select on translation;
drop policy if exists merchant_alias_admin on merchant_alias;
drop policy if exists merchant_alias_insert_agent on merchant_alias;
drop policy if exists merchant_alias_select on merchant_alias;
drop policy if exists merchant_admin on merchant;
drop policy if exists merchant_update_agent on merchant;
drop policy if exists merchant_insert_agent on merchant;
drop policy if exists merchant_select on merchant;
drop policy if exists posting_admin on posting;
drop policy if exists posting_update_member on posting;
drop policy if exists posting_insert_agent on posting;
drop policy if exists posting_select on posting;
drop trigger if exists posting_member_update_guard on posting;
drop function if exists posting_member_update_guard();
drop policy if exists transaction_admin on transaction;
drop policy if exists transaction_update_member on transaction;
drop policy if exists transaction_insert_agent on transaction;
drop policy if exists transaction_select on transaction;
drop trigger if exists transaction_member_update_guard on transaction;
drop function if exists transaction_member_update_guard();
drop policy if exists account_term_insert on account_term;
drop policy if exists account_term_select on account_term;
drop policy if exists account_insert_agent on account;
drop policy if exists account_admin on account;
drop policy if exists account_select on account;
drop trigger if exists account_agent_insert_guard on account;
drop function if exists account_agent_insert_guard();

alter table household_setting disable row level security;
alter table translation       disable row level security;
alter table merchant_alias    disable row level security;
alter table merchant          disable row level security;
alter table posting           disable row level security;
alter table transaction       disable row level security;
alter table account_term      disable row level security;
alter table account           disable row level security;

alter table transaction drop column merchant_id;
