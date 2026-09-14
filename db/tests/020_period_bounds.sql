-- pgTAP: period_bounds and v_reporting_period (spec 0004 T1, ADR 0045).
-- Bounds are checked by hand against a fixed "now" via a non-UTC
-- timezone, and against a household whose own timezone setting drives
-- the view -- never against the function's own output.
begin;
select plan(9);

-- A household on a timezone west of UTC, so a naive UTC-only
-- implementation would resolve the wrong calendar day near midnight.
set local timezone to 'UTC';

select is(
  (select period_start from period_bounds('this_month', 'America/New_York') where (now() at time zone 'America/New_York')::date >= '2026-01-01'),
  (date_trunc('month', (now() at time zone 'America/New_York')::date))::date,
  'this_month starts on the 1st in the household''s own timezone, not UTC''s'
);

select is(
  (select period_end from period_bounds('this_month', 'America/New_York')),
  (date_trunc('month', (now() at time zone 'America/New_York')::date) + interval '1 month - 1 day')::date,
  'this_month ends on the calendar month''s last day'
);

select is(
  (select previous_start from period_bounds('this_month', 'Europe/Amsterdam')),
  (select period_start from period_bounds('last_month', 'Europe/Amsterdam')),
  'this_month''s previous period is exactly last_month''s own bounds'
);

select is(
  (select period_end from period_bounds('last_month', 'Europe/Amsterdam')),
  (select period_start from period_bounds('this_month', 'Europe/Amsterdam')) - 1,
  'last_month ends the day before this_month starts -- no gap, no overlap'
);

select is(
  (select period_end - period_start + 1 from period_bounds('last_7_days', 'Europe/Amsterdam')),
  7,
  'last_7_days spans exactly seven days, inclusive'
);

select is(
  (select period_end - period_start + 1 from period_bounds('last_30_days', 'Europe/Amsterdam')),
  30,
  'last_30_days spans exactly thirty days, inclusive'
);

select is(
  (select period_start from period_bounds('month_of:2026-03', 'Europe/Amsterdam')),
  '2026-03-01'::date,
  'month_of:YYYY-MM resolves to that exact calendar month, any distance from today'
);

select is(
  (select previous_end from period_bounds('this_year', 'Europe/Amsterdam')),
  (select period_start from period_bounds('this_year', 'Europe/Amsterdam')) - 1,
  'this_year''s previous period ends the day before this year starts'
);

select throws_ok(
  $$ select * from period_bounds('the last fortnight', 'Europe/Amsterdam') $$,
  null, null, 'an unrecognised period is refused, never guessed at (R6)'
);

select * from finish();
rollback;
