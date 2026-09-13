-- migrate:up

-- A real bug found running the seed: household_setting's primary key is
-- key (text), but audit_log_trigger() unconditionally reads
-- row_to_json(new)->>'id' — the same shape spec 0002 T7 already hit for
-- member_identity and member_channel. Fixed the same way: a surrogate id
-- primary key, keeping key as an ordinary unique natural key.
alter table household_setting drop constraint household_setting_pkey;
alter table household_setting add column id bigint generated always as identity;
alter table household_setting add primary key (id);
alter table household_setting add constraint household_setting_key_key unique (key);

-- migrate:down
alter table household_setting drop constraint household_setting_key_key;
alter table household_setting drop constraint household_setting_pkey;
alter table household_setting drop column id;
alter table household_setting add primary key (key);
