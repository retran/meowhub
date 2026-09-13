-- pgTAP: the audit trigger (ADR 0008, spec 0001 T5)
begin;
select plan(5);

select has_table('public', 'audit_log', 'audit_log exists');
select has_function('public', 'audit_log_trigger', 'audit_log_trigger() exists');

-- attach the generic trigger to the probe table, as a domain table would
create trigger bootstrap_probe_audit
  after insert or update or delete on bootstrap_probe
  for each row execute function audit_log_trigger();

-- 1. a write with no actor set must fail
select throws_ok(
  $$ insert into bootstrap_probe default values $$,
  'P0001',
  'audit_log_trigger: meowhub.actor must be set for writes to bootstrap_probe',
  'write with no actor set is rejected'
);

-- 2. a write with an actor set succeeds and is audited
select set_config('meowhub.actor', 'test-member-1', false);
insert into bootstrap_probe default values;

select is(
  (select count(*)::int from audit_log
    where table_name = 'bootstrap_probe' and operation = 'insert' and actor = 'test-member-1'),
  1,
  'the insert is recorded in audit_log with the correct actor'
);

-- 3. audit_log itself is immutable to application roles
select throws_ok(
  $$ update audit_log set actor = 'hacked' where true $$,
  'P0001',
  'audit_log is append-only and may not be updated or deleted',
  'audit_log rows cannot be updated'
);

select * from finish();
rollback;
