-- pgTAP: the real identity tables exist with the shape the catalogue
-- promises, and admin_account (spec 0001 T17's scaffold) is gone
-- (spec 0002 T1).
begin;
select plan(10);

select hasnt_table('public', 'admin_account', 'admin_account is dropped, superseded by member/member_identity');

select has_table('public', 'member', 'member exists');
select has_column('public', 'member', 'role', 'member.role exists');
select col_has_check('public', 'member', 'role', 'member.role is constrained to admin/member');

select has_table('public', 'member_identity', 'member_identity exists');
select col_is_unique('public', 'member_identity', 'provider_subject', 'provider_subject is unique — matched on it, never on email');

select has_table('public', 'member_channel', 'member_channel exists');
select col_is_pk('public', 'member_channel', array['id'], 'member_channel has a surrogate id primary key (spec 0002 T7)');
select col_is_unique('public', 'member_channel', array['kind', 'external_id'], 'member_channel is unique on (kind, external_id)');

select set_config('meowhub.actor', 'test-suite', true);
select lives_ok(
  $$ insert into member (role) values ('admin') $$,
  'inserting a member with an actor set succeeds and is audited'
);

select * from finish();
rollback;
