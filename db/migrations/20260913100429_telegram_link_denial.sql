-- migrate:up

-- An unlinked Telegram id messaging the bot writes nothing to the
-- household's own data (R6c, A18) but the attempt itself must still be
-- logged. audit_log's shape otherwise only ever describes a row change
-- (insert/update/delete) made by a trigger — this is neither, so it gets
-- its own operation value rather than a fabricated row change nobody made.
alter table audit_log drop constraint audit_log_operation_check;
alter table audit_log add constraint audit_log_operation_check
  check (operation in ('insert', 'update', 'delete', 'denied'));

comment on constraint audit_log_operation_check on audit_log is
  '''denied'' records an access attempt with no member behind it (spec 0002 T12, A18) — table_name/row_id name what was attempted, not a row that exists.';

-- migrate:down
alter table audit_log drop constraint audit_log_operation_check;
alter table audit_log add constraint audit_log_operation_check
  check (operation in ('insert', 'update', 'delete'));
