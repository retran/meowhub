-- pgTAP: R9-R13's write shape, proven against the scaffold standing in for
-- the real ledger (spec 0002 T4) — everyone reads, only an admin deletes,
-- any member reclassifies any row, a member confirms only their own
-- unconfirmed capture, no member inserts a raw row.
begin;
select plan(10);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin')  returning id \gset admin_
insert into member (role) values ('member') returning id \gset a_
insert into member (role) values ('member') returning id \gset b_

-- hh_agent captures on member A's behalf — the acting member is the
-- capturing member, not a generic process name (R15c).
select set_config('meowhub.actor', :'a_id', true);
set role hh_agent;
insert into ledger_probe (captured_by, category) values (:'a_id', 'groceries') returning id \gset row_
reset role;

-- A24: an agent insert with no acting member set fails.
select set_config('meowhub.actor', '', true);
set role hh_agent;
select throws_ok(
  format($$ insert into ledger_probe (captured_by, category) values (%s, 'x') $$, :'a_id'),
  null, null, 'hh_agent insert with no acting member set fails'
);
reset role;

-- A13: no member may write a raw row under any role.
select set_config('meowhub.actor', :'a_id', true);
set role hh_member;
select throws_ok(
  format($$ insert into ledger_probe (captured_by, category) values (%s, 'x') $$, :'a_id'),
  null, null, 'hh_member cannot insert a raw row (A13)'
);

-- A11: only an admin deletes a recorded row.
select throws_ok(
  format($$ delete from ledger_probe where id = %s $$, :'row_id'),
  null, null, 'hh_member cannot delete a recorded row (A11)'
);

-- A12: any member reclassifies any row, including one they did not capture.
select set_config('meowhub.actor', :'b_id', true);
select lives_ok(
  format($$ update ledger_probe set category = 'transport' where id = %s $$, :'row_id'),
  'member B reclassifies member A''s row (A12)'
);

-- A31 negative: member B (not the capturer) cannot confirm A's row.
select throws_ok(
  format($$ update ledger_probe set confirmed = true where id = %s $$, :'row_id'),
  null, null, 'member B cannot confirm member A''s unconfirmed row (A31)'
);

-- A31 positive: member A, the capturer, confirms their own unconfirmed row.
select set_config('meowhub.actor', :'a_id', true);
select lives_ok(
  format($$ update ledger_probe set confirmed = true where id = %s $$, :'row_id'),
  'member A confirms their own unconfirmed row (A31)'
);

-- Once confirmed, it cannot be un-confirmed by the member who captured it —
-- R12's "while it is unconfirmed" gate covers confirming itself, not just
-- other fields. R11's category/project rule is deliberately unconditional
-- (see the lives_ok above): "any transaction" has no unconfirmed clause.
select throws_ok(
  format($$ update ledger_probe set confirmed = false where id = %s $$, :'row_id'),
  null, null, 'a confirmed row cannot be un-confirmed by the member who captured it'
);
reset role;

-- A30: every member reads the same whole ledger.
set role hh_member;
select is(
  (select count(*)::int from ledger_probe), 1,
  'member A reads the whole ledger'
);
reset role;
select set_config('meowhub.actor', :'b_id', true);
set role hh_member;
select is(
  (select count(*)::int from ledger_probe), 1,
  'member B reads the same whole ledger — asserted equal, not assumed (A30)'
);
reset role;

-- hh_admin can delete unconditionally, unlike a member.
select set_config('meowhub.actor', :'admin_id', true);
set role hh_admin;
select lives_ok(
  format($$ delete from ledger_probe where id = %s $$, :'row_id'),
  'hh_admin deletes the row'
);
reset role;

select * from finish();
rollback;
