-- pgTAP: the file table (ADR 0019, spec 0001 T7)
begin;
select plan(4);

select has_table('public', 'file', 'file exists');
select has_column('public', 'file', 'sha256', 'file.sha256 exists');
select col_is_unique('public', 'file', 'sha256', 'sha256 is unique — dedup is a lookup, not a heuristic');

select set_config('meowhub.actor', 'test-member-1', false);
insert into file (sha256, media_type, size_bytes, original_name, uploaded_by)
values (repeat('a', 64), 'image/jpeg', 1234, 'receipt.jpg', 'test-member-1');

select throws_ok(
  $$ insert into file (sha256, media_type, size_bytes, original_name, uploaded_by)
     values (repeat('a', 64), 'image/jpeg', 1234, 'receipt.jpg', 'test-member-1') $$,
  '23505',
  null,
  'a second row with the same hash is rejected at the database'
);

select * from finish();
rollback;
