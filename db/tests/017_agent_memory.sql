-- pgTAP: agent_memory exists with the shape ADR 0044 describes — the
-- agent writes, everyone reads, only an admin corrects or removes one.
begin;
select plan(5);

select has_table('public', 'agent_memory', 'agent_memory exists');

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id \gset mem_
insert into member (role) values ('admin') returning id \gset admin_

set role hh_agent;
select set_config('meowhub.actor', :'mem_id', true);
insert into agent_memory (member_id, content) values (:mem_id, 'prefers not to be asked which account') returning id \gset mem_row_
select lives_ok(
  $$ insert into agent_memory (content) values ('household is saving for a car this year') $$,
  'the agent writes a household-wide memory (member_id null)'
);
reset role;

set role hh_member;
select set_config('meowhub.actor', :'mem_id', true);
select is(
  (select count(*)::int from agent_memory), 2,
  'a member reads every memory row, not only their own'
);
select throws_ok(
  format($$ delete from agent_memory where id = %s $$, :'mem_row_id'),
  null, null, 'a member cannot remove a memory row'
);
reset role;

set role hh_admin;
select set_config('meowhub.actor', :'admin_id', true);
select lives_ok(
  format($$ delete from agent_memory where id = %s $$, :'mem_row_id'),
  'an admin removes a stale or wrong memory row'
);
reset role;

select * from finish();
rollback;
