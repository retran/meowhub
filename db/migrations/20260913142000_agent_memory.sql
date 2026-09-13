-- migrate:up

-- A household-visible standing fact the agent writes and reads on its
-- own, distinct from the ledger and from conversation (ADR 0044).
create table agent_memory (
  id         bigint      generated always as identity primary key,
  member_id  bigint      references member (id),
  content    text        not null,
  created_at timestamptz not null default now()
);

comment on table agent_memory is
  'A standing fact the agent keeps across conversations (ADR 0044) — member_id null means household-wide. Never a financial fact: informs a question or a default, never a transaction''s own state.';

create trigger agent_memory_audit
  after insert or update or delete on agent_memory
  for each row execute function audit_log_trigger();

alter table agent_memory enable row level security;
alter table agent_memory force row level security;

-- Everyone reads (it may explain a reply); the agent writes its own
-- observations (ADR 0044's "composes" shape, like an unprompted
-- category); only an admin corrects or removes a wrong or stale one.
grant select on agent_memory to hh_member, hh_agent, hh_admin;
grant insert on agent_memory to hh_agent;
grant update, delete on agent_memory to hh_admin;

create policy agent_memory_select on agent_memory for select to hh_member, hh_agent, hh_admin using (true);
create policy agent_memory_insert_agent on agent_memory for insert to hh_agent with check (true);
create policy agent_memory_admin on agent_memory for all to hh_admin using (true) with check (true);

-- migrate:down
drop policy if exists agent_memory_admin on agent_memory;
drop policy if exists agent_memory_insert_agent on agent_memory;
drop policy if exists agent_memory_select on agent_memory;
drop trigger if exists agent_memory_audit on agent_memory;
drop table if exists agent_memory;
