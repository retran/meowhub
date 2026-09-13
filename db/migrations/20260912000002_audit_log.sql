-- migrate:up

-- The audit skeleton (ADR 0008, spec 0001 T5). Generic on purpose: table name,
-- row id, operation, before/after images, actor, timestamp — so every domain
-- table spec 0003 introduces gets auditing by attaching this trigger, rather
-- than by inventing its own log.

create table audit_log (
  id           bigint generated always as identity primary key,
  table_name   text        not null,
  row_id       text        not null,
  operation    text        not null check (operation in ('insert', 'update', 'delete')),
  before_state jsonb,
  after_state  jsonb,
  actor        text        not null,          -- a member id, or a named automated process; never null
  occurred_at  timestamptz not null default now()
);

comment on table audit_log is
  'Append-only. No application role may update or delete a row here (ADR 0008).';

create index audit_log_table_row_idx on audit_log (table_name, row_id);
create index audit_log_occurred_at_idx on audit_log (occurred_at);

-- The actor is passed through a session-local setting, set by the caller
-- inside the same transaction. A write with no actor set fails rather than
-- defaulting to a system actor (ADR 0008, spec 0002 R15c).
create or replace function audit_log_trigger()
returns trigger
language plpgsql
as $$
declare
  v_actor text;
  v_row_id text;
begin
  begin
    v_actor := current_setting('meowhub.actor');
  exception when others then
    v_actor := null;
  end;

  if v_actor is null or v_actor = '' then
    raise exception 'audit_log_trigger: meowhub.actor must be set for writes to %', TG_TABLE_NAME;
  end if;

  if TG_OP = 'DELETE' then
    v_row_id := (row_to_json(old)->>'id');
  else
    v_row_id := (row_to_json(new)->>'id');
  end if;

  insert into audit_log (table_name, row_id, operation, before_state, after_state, actor)
  values (
    TG_TABLE_NAME,
    v_row_id,
    lower(TG_OP),
    case when TG_OP in ('UPDATE', 'DELETE') then row_to_json(old)::jsonb else null end,
    case when TG_OP in ('UPDATE', 'INSERT') then row_to_json(new)::jsonb else null end,
    v_actor
  );

  if TG_OP = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- Immutability: no application role may modify or remove an audit row.
-- (The owning migration role, used only for schema changes, is exempt.)
create or replace function audit_log_deny_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_log is append-only and may not be updated or deleted';
end;
$$;

create trigger audit_log_immutable_update
  before update on audit_log
  for each row execute function audit_log_deny_mutation();

create trigger audit_log_immutable_delete
  before delete on audit_log
  for each row execute function audit_log_deny_mutation();

-- migrate:down
drop trigger if exists audit_log_immutable_delete on audit_log;
drop trigger if exists audit_log_immutable_update on audit_log;
drop function if exists audit_log_deny_mutation();
drop function if exists audit_log_trigger();
drop table if exists audit_log;
