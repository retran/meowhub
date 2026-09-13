-- migrate:up

-- Identity is ours; the provider and every channel are links to it, never
-- the identity itself (ADR 0030, spec 0002 R4/R6a/R6b/R7). Replaces spec
-- 0001 T17's admin_account outright — that table was built explicitly to
-- be superseded here, not carried forward.
drop table if exists admin_account;

create table member (
  id          bigint generated always as identity primary key,
  role        text        not null check (role in ('admin', 'member')),
  language    text        not null default 'ru',
  theme       text        not null default 'dark',
  active      boolean     not null default true,
  created_at  timestamptz not null default now()
);

comment on table member is
  'The person. Role is a property of the member, not of a person (R7). default_payment_account_id arrives with spec 0003''s accounts.';

-- The identity provider's stable subject — matched on this, never on an
-- email address, which is a login identifier and may change (R4).
create table member_identity (
  member_id        bigint      not null references member (id),
  provider_subject text        not null unique,
  created_at       timestamptz not null default now(),
  primary key (member_id, provider_subject)
);

comment on table member_identity is
  'One member, several sign-in methods (ADR 0032, R3a): a passkey and an Apple ID both attach here, never a second member.';

-- A channel binding — Telegram today (R6a). linked_by names the admin who
-- performed the link: a member never claims one by self-service (R6c).
create table member_channel (
  member_id   bigint      not null references member (id),
  kind        text        not null check (kind in ('telegram')),
  external_id text        not null,
  linked_by   bigint      not null references member (id),
  linked_at   timestamptz not null default now(),
  primary key (kind, external_id)
);

comment on table member_channel is
  'Attribution references the member, never the channel id (R6d): re-linking to a different account leaves past history''s member_id unchanged.';

create trigger member_audit
  after insert or update or delete on member
  for each row execute function audit_log_trigger();

create trigger member_identity_audit
  after insert or update or delete on member_identity
  for each row execute function audit_log_trigger();

create trigger member_channel_audit
  after insert or update or delete on member_channel
  for each row execute function audit_log_trigger();

-- migrate:down
drop trigger if exists member_channel_audit on member_channel;
drop trigger if exists member_identity_audit on member_identity;
drop trigger if exists member_audit on member;
drop table if exists member_channel;
drop table if exists member_identity;
drop table if exists member;
