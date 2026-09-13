-- pgTAP: audit_log accepts a 'denied' entry for an access attempt with no
-- member behind it (spec 0002 T12, A18)
begin;
select plan(2);

select set_config('meowhub.actor', 'telegram-bot', false);

select lives_ok(
  $$ insert into audit_log (table_name, row_id, operation, after_state, actor)
     values ('member_channel', '999999999', 'denied', jsonb_build_object('kind', 'telegram'), 'telegram-bot') $$,
  'a denied access attempt is a valid audit_log row'
);

select throws_ok(
  $$ insert into audit_log (table_name, row_id, operation, actor)
     values ('member_channel', '1', 'refused', 'telegram-bot') $$,
  '23514',
  null,
  'any other made-up operation value is still rejected'
);

select * from finish();
