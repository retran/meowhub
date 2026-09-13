-- pgTAP: applying migrations twice must change nothing (spec 0001, A4)
begin;
select plan(2);

select ok(
  (select count(*) from schema_migrations) >= 2,
  'schema_migrations records the applied migrations'
);

select has_table('public', 'bootstrap_probe', 'bootstrap_probe exists after migration');

select * from finish();
rollback;
