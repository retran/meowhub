-- migrate:up

-- A scaffold standing in for the real ledger, deliberately (spec 0002 T4):
-- spec 0003 brings the real transaction/posting tables and their own
-- policies, but R9-R13's write-shape rules — everyone reads, only an
-- admin does anything structural, any member reclassifies, a member
-- confirms only their own unconfirmed capture, no raw posting survives
-- under any role — need something real to impersonate against now, not a
-- promise to test later. Not a product table: dropped outright once spec
-- 0003 lands, the same way admin_account was dropped by this spec.
create table ledger_probe (
  id          bigint generated always as identity primary key,
  captured_by bigint      not null references member (id),
  category    text,
  confirmed   boolean     not null default false,
  created_at  timestamptz not null default now()
);

comment on table ledger_probe is
  'Scaffold only (spec 0002 T4). Superseded by spec 0003''s real transaction/posting tables and policies.';

create trigger ledger_probe_audit
  after insert or update or delete on ledger_probe
  for each row execute function audit_log_trigger();

alter table ledger_probe enable row level security;
alter table ledger_probe force row level security;

-- Reclassifying (category) is always allowed, on any row, for any member
-- (R11); confirming or correcting anything else requires it being the
-- member's own capture, still unconfirmed (R12) — two rules that overlap
-- on the same columns, which RLS policies alone cannot express (a policy
-- sees one row version at a time, not which columns a statement touches).
-- The trigger is the actual gate; the policy below only says hh_member may
-- attempt an update at all.
create or replace function ledger_probe_member_update_guard()
returns trigger
language plpgsql
as $$
begin
  if pg_has_role(current_user, 'hh_admin', 'member') then
    return new;
  end if;

  if new.confirmed is distinct from old.confirmed
     or new.captured_by is distinct from old.captured_by then
    if old.confirmed or old.captured_by <> current_setting('meowhub.actor')::bigint then
      raise exception 'ledger_probe_member_update_guard: only the capturing member may confirm or correct their own unconfirmed record';
    end if;
  end if;

  return new;
end;
$$;

create trigger ledger_probe_member_update_guard
  before update on ledger_probe
  for each row execute function ledger_probe_member_update_guard();

grant select on ledger_probe to hh_member;
grant select, insert on ledger_probe to hh_agent;
grant select, insert, update, delete on ledger_probe to hh_admin;
grant update (category, confirmed) on ledger_probe to hh_member;

create policy ledger_probe_select_member on ledger_probe for select to hh_member using (true);
create policy ledger_probe_select_agent  on ledger_probe for select to hh_agent  using (true);
create policy ledger_probe_insert_agent  on ledger_probe for insert to hh_agent  with check (true);
create policy ledger_probe_update_member on ledger_probe for update to hh_member using (true) with check (true);
create policy ledger_probe_admin         on ledger_probe for all    to hh_admin  using (true) with check (true);

-- migrate:down
drop policy if exists ledger_probe_admin on ledger_probe;
drop policy if exists ledger_probe_update_member on ledger_probe;
drop policy if exists ledger_probe_insert_agent on ledger_probe;
drop policy if exists ledger_probe_select_agent on ledger_probe;
drop policy if exists ledger_probe_select_member on ledger_probe;
drop trigger if exists ledger_probe_member_update_guard on ledger_probe;
drop function if exists ledger_probe_member_update_guard();
drop trigger if exists ledger_probe_audit on ledger_probe;
drop table if exists ledger_probe;
