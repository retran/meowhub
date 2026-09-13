-- migrate:up

-- Conversation state lives in PostgreSQL, never in the workflow engine
-- (ADR 0038). One row per exchange in progress; at most one open
-- conversation per member per kind, which is what makes "what still
-- needs setting up" answerable (R0e).
create table conversation (
  id               bigint      generated always as identity primary key,
  member_id        bigint      not null references member (id),
  kind             text        not null check (kind in ('setup', 'clarification', 'structural_change', 'correction')),
  step             text        not null,
  payload          jsonb       not null default '{}',
  opened_at        timestamptz not null default now(),
  last_touched_at  timestamptz not null default now(),
  closed_at        timestamptz
);

comment on table conversation is
  'A multi-turn exchange in progress (ADR 0038). Never the ledger: nothing in payload is a financial fact until it becomes a transaction.';

create unique index conversation_one_open_per_kind
  on conversation (member_id, kind)
  where closed_at is null;

create trigger conversation_audit
  after insert or update or delete on conversation
  for each row execute function audit_log_trigger();

-- One row per message, inbound and outbound (R6a) — the whole exchange
-- that produced a record, in order. A single-message capture that
-- resolves immediately has conversation_id null and sequence 1; a
-- multi-turn one (an unparsed capture asking a question) gets a
-- conversation row of kind = 'clarification', and every message in it —
-- including the agent's own question — is a row here, ordered by
-- sequence. That ordering is what makes A41 ("not asked twice")
-- checkable: a duplicate question is a duplicate outbound row.
create table capture (
  id                 bigint      generated always as identity primary key,
  member_id          bigint      not null references member (id),
  conversation_id    bigint      references conversation (id),
  sequence           int         not null default 1,
  direction          text        not null check (direction in ('inbound', 'outbound')),
  kind               text        not null check (kind in ('text', 'photo', 'voice')),
  channel_message_id text,
  raw_text           text,
  file_id            bigint      references file (id),
  extracted_payload  jsonb,
  state              text        check (state in ('unparsed', 'resolved')),
  transaction_id     bigint      references transaction (id),
  created_at         timestamptz not null default now()
);

comment on table capture is
  'One row per message (R6a) — the exchange that produced a record, in order. state is meaningful on inbound rows only: null on an outbound question.';

create index capture_conversation_sequence on capture (conversation_id, sequence);

create trigger capture_audit
  after insert or update or delete on capture
  for each row execute function audit_log_trigger();

-- A member asking an admin for a change they may not make themselves
-- (R14/R16a): created by the bot, closed by the admin.
create table correction_request (
  id               bigint      generated always as identity primary key,
  transaction_id   bigint      not null references transaction (id),
  requested_by     bigint      not null references member (id),
  requested_change jsonb       not null,
  status           text        not null default 'open' check (status in ('open', 'closed')),
  created_at       timestamptz not null default now(),
  closed_at        timestamptz
);

comment on table correction_request is
  'A non-admin''s requested correction to a financial fact (R14) — the admins are notified, the transaction is unchanged until an admin acts.';

create trigger correction_request_audit
  after insert or update or delete on correction_request
  for each row execute function audit_log_trigger();

-- RLS: conversation and capture are the agent's own working state,
-- composing on a member's behalf — the member can see their own, an
-- admin sees all (for "what still needs setting up" asked about anyone,
-- and for reviewing an unparsed capture). correction_request is created
-- by the agent, read by the member who asked and by every admin, closed
-- only by an admin.
alter table conversation       enable row level security;
alter table conversation       force row level security;
alter table capture            enable row level security;
alter table capture            force row level security;
alter table correction_request enable row level security;
alter table correction_request force row level security;

grant select, insert, update on conversation to hh_agent;
grant select, update on conversation to hh_admin;
grant select on conversation to hh_member;

create policy conversation_select_own on conversation for select to hh_member using (member_id = current_setting('meowhub.actor', true)::bigint);
create policy conversation_agent on conversation for all to hh_agent using (true) with check (true);
create policy conversation_admin on conversation for all to hh_admin using (true) with check (true);

grant select, insert on capture to hh_agent;
grant select, update on capture to hh_admin;
grant select on capture to hh_member;

create policy capture_select_own on capture for select to hh_member using (member_id = current_setting('meowhub.actor', true)::bigint);
create policy capture_agent on capture for all to hh_agent using (true) with check (true);
create policy capture_admin on capture for all to hh_admin using (true) with check (true);

grant select, insert on correction_request to hh_agent;
grant select, update on correction_request to hh_admin;
grant select on correction_request to hh_member;

create policy correction_request_select_own on correction_request for select to hh_member using (requested_by = current_setting('meowhub.actor', true)::bigint);
create policy correction_request_agent on correction_request for all to hh_agent using (true) with check (true);
create policy correction_request_admin on correction_request for all to hh_admin using (true) with check (true);

-- migrate:down
drop policy if exists correction_request_admin on correction_request;
drop policy if exists correction_request_agent on correction_request;
drop policy if exists correction_request_select_own on correction_request;
drop policy if exists capture_admin on capture;
drop policy if exists capture_agent on capture;
drop policy if exists capture_select_own on capture;
drop policy if exists conversation_admin on conversation;
drop policy if exists conversation_agent on conversation;
drop policy if exists conversation_select_own on conversation;

drop trigger if exists correction_request_audit on correction_request;
drop table if exists correction_request;
drop trigger if exists capture_audit on capture;
drop table if exists capture;
drop trigger if exists conversation_audit on conversation;
drop table if exists conversation;
