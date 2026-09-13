-- migrate:up

-- Content-addressed file storage (ADR 0019, spec 0001 T7). The bytes live on
-- a volume; this table is only the metadata and the hash. Storing the same
-- file twice is free: the unique constraint on sha256 is the deduplication.
create table file (
  id              bigint generated always as identity primary key,
  sha256          text        not null unique,
  media_type      text        not null,
  size_bytes      bigint      not null check (size_bytes >= 0),
  original_name   text,
  uploaded_by     text        not null,   -- a member id, or a named automated process
  created_at      timestamptz not null default now(),
  check (sha256 ~ '^[0-9a-f]{64}$')
);

comment on table file is
  'Metadata for content-addressed files on the storage volume. The path is '
  'derived from sha256 (ab/cd/<sha256>); this row never holds the bytes.';

create trigger file_audit
  after insert or update or delete on file
  for each row execute function audit_log_trigger();

-- migrate:down
drop trigger if exists file_audit on file;
drop table if exists file;
