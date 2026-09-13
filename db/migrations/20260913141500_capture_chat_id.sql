-- migrate:up

-- A shared group chat means shared context, not merely shared visibility
-- (ADR 0043): composing a reply considers recent messages from the whole
-- chat, across every member in it, not only the sending member's own
-- prior messages. chat_id (the Telegram chat, distinct from the sender)
-- is what a query for "what else was said here" filters on.
alter table capture add column chat_id text;

comment on column capture.chat_id is
  'The Telegram chat this message arrived in — a member''s own private chat, or the one shared household group (ADR 0043). Distinct from member_id (the sender): a query for shared context filters on this, a query for whose bookkeeping this is filters on member_id.';

create index capture_chat_id on capture (chat_id, created_at);

-- migrate:down
drop index if exists capture_chat_id;
alter table capture drop column chat_id;
