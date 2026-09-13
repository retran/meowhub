-- migrate:up

-- A real gap found by spec 0003 T10's A3: account and account_term were
-- the only ledger tables T1 never gave an audit_log_trigger -- every
-- other table (transaction, posting, merchant, ...) got one in the same
-- migration. R0b requires a structural change (opening an account,
-- re-terming it) to record the asking admin as the actor; without this
-- trigger there was no audit row to check at all.
create trigger account_audit
  after insert or update or delete on account
  for each row execute function audit_log_trigger();

-- insert only: account_term is append-only (deny_mutation denies any
-- update or delete), so there is never a before/after pair to log.
create trigger account_term_audit
  after insert on account_term
  for each row execute function audit_log_trigger();

-- migrate:down
drop trigger account_term_audit on account_term;
drop trigger account_audit on account;
