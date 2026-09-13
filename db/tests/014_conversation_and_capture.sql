-- pgTAP: conversation state and the one-row-per-message capture exchange
-- (spec 0003 T4, R6a, ADR 0038).
begin;
select plan(9);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id \gset a_
insert into member (role) values ('member') returning id \gset b_

select has_table('public', 'conversation', 'conversation exists');
select has_table('public', 'capture', 'capture exists');
select has_table('public', 'correction_request', 'correction_request exists');

set role hh_agent;
select set_config('meowhub.actor', :'a_id', true);

insert into conversation (member_id, kind, step) values (:a_id, 'clarification', 'awaiting_amount') returning id \gset conv_

-- At most one open conversation per member per kind (R0e).
select throws_ok(
  format($$ insert into conversation (member_id, kind, step) values (%s, 'clarification', 'awaiting_amount') $$, :'a_id'),
  null, null, 'a second open conversation of the same kind for the same member is rejected'
);

-- The exchange, in order: inbound (unparsed), outbound (the question),
-- inbound (the answer, still unresolved), outbound (a further question).
insert into capture (member_id, conversation_id, sequence, direction, kind, raw_text, state)
  values (:a_id, :conv_id, 1, 'inbound', 'text', 'that was expensive', 'unparsed') returning id \gset c1_
insert into capture (member_id, conversation_id, sequence, direction, kind, raw_text)
  values (:a_id, :conv_id, 2, 'outbound', 'text', 'How much was it?') returning id \gset c2_
insert into capture (member_id, conversation_id, sequence, direction, kind, raw_text, state)
  values (:a_id, :conv_id, 3, 'inbound', 'text', 'at the shop', 'unparsed') returning id \gset c3_
insert into capture (member_id, conversation_id, sequence, direction, kind, raw_text)
  values (:a_id, :conv_id, 4, 'outbound', 'text', 'What did you spend?') returning id \gset c4_

select is(
  (select array_agg(raw_text order by sequence) from capture where conversation_id = :conv_id),
  array['that was expensive', 'How much was it?', 'at the shop', 'What did you spend?'],
  'every message in the exchange is stored, in order (R6a)'
);

-- A41: the same question is never asked twice — checkable because it is
-- a row, not a flag: a workflow checks for an existing outbound row with
-- the same text before inserting another.
select is(
  (select count(*)::int from capture where conversation_id = :conv_id and direction = 'outbound' and raw_text = 'What did you spend?'),
  1,
  'the same outbound question exists exactly once so far'
);

reset role;

-- A member reads only their own conversation and capture rows.
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select is(
  (select count(*)::int from conversation), 1,
  'member A sees their own open conversation'
);
select set_config('meowhub.actor', :'b_id', true);
select is(
  (select count(*)::int from conversation), 0,
  'member B does not see member A''s conversation'
);
reset role;

-- An admin sees every conversation (for "what still needs setting up"
-- asked about anyone, and for reviewing an unparsed capture).
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id \gset admin_
set role hh_admin;
select set_config('meowhub.actor', :'admin_id', true);
select is(
  (select count(*)::int from conversation), 1,
  'an admin sees every open conversation'
);
reset role;

select * from finish();
rollback;
