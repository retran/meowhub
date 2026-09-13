-- migrate:up

-- Default deny (R14, R15b): row-level security on every table that exists
-- so far, with FORCE so even the table owner is subject to it — a table
-- with no policy is unreachable, not open. file and audit_log (spec 0001)
-- were reachable with no policy at all until now, which was only safe
-- because nothing had authenticated yet.
alter table member          enable row level security;
alter table member          force row level security;
alter table member_identity enable row level security;
alter table member_identity force row level security;
alter table member_channel  enable row level security;
alter table member_channel  force row level security;
alter table file            enable row level security;
alter table file            force row level security;
alter table audit_log       enable row level security;
alter table audit_log       force row level security;

-- member: everyone reads the roster; only an admin changes membership (R10).
grant select on member to hh_member, hh_agent;
grant select, insert, update, delete on member to hh_admin;

create policy member_select on member for select to hh_member, hh_agent, hh_admin using (true);
create policy member_write  on member for all    to hh_admin                     using (true) with check (true);

-- member_identity and member_channel carry the identity provider's own
-- linkage (ADR 0030) — nobody's product need requires a member to see a
-- fellow member's raw provider subject or channel binding, so these stay
-- admin-only for read as well as write. hh_agent gets read on
-- member_channel only, to resolve an incoming message's sender (spec 0002
-- T12); it may never create a link itself (R6c: a member must never claim
-- one by self-service).
grant select, insert, update, delete on member_identity to hh_admin;
create policy member_identity_admin on member_identity for all to hh_admin using (true) with check (true);

grant select on member_channel to hh_agent;
grant select, insert, update, delete on member_channel to hh_admin;
create policy member_channel_select_agent on member_channel for select to hh_agent using (true);
create policy member_channel_admin        on member_channel for all    to hh_admin using (true) with check (true);

-- file: part of the ledger's own record (attachments to captures) — every
-- member reads it (R9); hh_agent inserts what it captures; only an admin
-- corrects or removes one (R10).
grant select on file to hh_member;
grant select, insert on file to hh_agent;
grant select, insert, update, delete on file to hh_admin;

create policy file_select_member on file for select to hh_member using (true);
create policy file_select_agent  on file for select to hh_agent  using (true);
create policy file_insert_agent  on file for insert to hh_agent  with check (true);
create policy file_admin         on file for all    to hh_admin  using (true) with check (true);

-- audit_log: append-only to every role that can trigger a write elsewhere
-- (the shared trigger inserts with the caller's own privileges, not the
-- owner's — a role able to write an audited table must also be able to
-- insert here, or its write fails). Update and delete are granted to
-- nobody; the table's own deny triggers (ADR 0008) enforce that
-- independently of any grant, belt and suspenders.
grant select, insert on audit_log to hh_member, hh_admin, hh_agent;

create policy audit_log_select on audit_log for select to hh_member, hh_admin, hh_agent using (true);
create policy audit_log_insert on audit_log for insert to hh_member, hh_admin, hh_agent with check (true);

-- migrate:down
drop policy if exists audit_log_insert on audit_log;
drop policy if exists audit_log_select on audit_log;
drop policy if exists file_admin on file;
drop policy if exists file_insert_agent on file;
drop policy if exists file_select_agent on file;
drop policy if exists file_select_member on file;
drop policy if exists member_channel_admin on member_channel;
drop policy if exists member_channel_select_agent on member_channel;
drop policy if exists member_identity_admin on member_identity;
drop policy if exists member_write on member;
drop policy if exists member_select on member;

alter table audit_log       disable row level security;
alter table file            disable row level security;
alter table member_channel  disable row level security;
alter table member_identity disable row level security;
alter table member          disable row level security;
