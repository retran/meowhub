-- migrate:up

-- member_identity and member_channel were given composite primary keys and
-- no plain id column (T1) — but audit_log_trigger() (spec 0001 ADR 0008)
-- reads row_to_json(new)->>'id' for every audited table, unconditionally.
-- Any write to either table failed outright: a real bug, found only by
-- actually inserting a row through the trigger (spec 0002 T7). Every other
-- table in this schema already follows the "id bigint generated always as
-- identity" convention; these two now do too, with their natural keys
-- kept as ordinary unique constraints instead of the primary key.
alter table member_identity add column id bigint generated always as identity;
alter table member_identity drop constraint member_identity_pkey;
alter table member_identity add primary key (id);
-- provider_subject's own uniqueness (R4) already implies (member_id,
-- provider_subject) uniqueness — nothing else to re-add.

alter table member_channel add column id bigint generated always as identity;
alter table member_channel drop constraint member_channel_pkey;
alter table member_channel add primary key (id);
alter table member_channel add constraint member_channel_kind_external_id_key unique (kind, external_id);

-- migrate:down
alter table member_channel drop constraint member_channel_kind_external_id_key;
alter table member_channel drop constraint member_channel_pkey;
alter table member_channel drop column id;
alter table member_channel add primary key (kind, external_id);

alter table member_identity drop constraint member_identity_pkey;
alter table member_identity drop column id;
alter table member_identity add primary key (member_id, provider_subject);
