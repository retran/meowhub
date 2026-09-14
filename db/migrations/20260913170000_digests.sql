-- migrate:up

-- R9/R10/R15: a digest arrives on a schedule, in the member's own
-- language, and any member can turn their own off. The preference is a
-- column on the member because it is a fact about that person, not a
-- household setting -- and it defaults to on, because a digest nobody
-- opted into is what makes the books noticed (spec 0004's "Why").
alter table member add column digest_weekly boolean not null default true;
alter table member add column digest_monthly boolean not null default true;

-- R15 means the member, not only an admin. Column-level, so "I'd
-- rather not get these" can never become "I changed my own role".
grant update (digest_weekly, digest_monthly) on member to hh_member, hh_agent;
create policy member_update_own on member for update to hh_member, hh_agent
  using (id = current_setting('meowhub.actor', true)::bigint)
  with check (id = current_setting('meowhub.actor', true)::bigint);

-- Scheduling bookkeeping, deliberately not a view and not in the
-- catalogue: it is not a figure about money (plan.md).
--
-- The unique key is the whole idempotency mechanism. The tick runs
-- hourly and asks SQL who is due *and unsent*; the insert is the
-- send's own gate, so a container that was down at 09:00 sends at
-- 10:00 and a container restarted twice in an hour sends once.
create table digest_run (
  id bigint generated always as identity primary key,
  member_id bigint not null references member (id),
  kind text not null check (kind in ('weekly', 'monthly')),
  period_start date not null,
  sent_at timestamptz not null default now(),
  unique (member_id, kind, period_start)
);

comment on table digest_run is
  'One row per digest actually sent (R9, R10). Unique on (member_id, kind, period_start): the insert is the send''s gate, which is what makes the hourly tick idempotent and self-healing.';

alter table digest_run enable row level security;
alter table digest_run force row level security;
grant select, insert on digest_run to hh_agent;
grant select on digest_run to hh_admin, hh_member;
create policy digest_run_agent on digest_run for all to hh_agent using (true) with check (true);
create policy digest_run_admin on digest_run for select to hh_admin using (true);
create policy digest_run_select_own on digest_run for select to hh_member
  using (member_id = current_setting('meowhub.actor', true)::bigint);

-- Who is due, and unsent, at a given moment -- the whole scheduling
-- decision, in SQL (plan.md's chosen option). `at` is a parameter and
-- not `now()` so the clock can be moved in a test instead of waited
-- for, and so the household's timezone decides what "Monday 09:00"
-- means rather than whatever zone a container happens to run in.
--
-- Weekly covers last_7_days and monthly last_month: both are names in
-- the fixed vocabulary (ADR 0045), so a digest's figure and an answer's
-- figure come out of the same view for the same bounds (R13).
create function digest_due(at timestamptz default now())
returns table (member_id bigint, kind text, period_start date, period text, language text)
language sql
stable
as $$
  with tz as (
    select coalesce((select value #>> '{}' from household_setting where key = 'timezone'), 'UTC') as zone
  ),
  local as (select (at at time zone (select zone from tz)) as ts),
  due as (
    select 'weekly'::text as kind,
           date_trunc('week', (select ts from local))::date as period_start,
           'last_7_days'::text as period,
           (select ts from local) >= date_trunc('week', (select ts from local)) + interval '9 hours' as reached
    union all
    select 'monthly'::text,
           date_trunc('month', (select ts from local))::date,
           'last_month'::text,
           (select ts from local) >= date_trunc('month', (select ts from local)) + interval '9 hours'
  )
  select m.id, d.kind, d.period_start, d.period, m.language
  from member m
  cross join due d
  where m.active
    and d.reached
    and case d.kind when 'weekly' then m.digest_weekly else m.digest_monthly end
    and not exists (
      select 1 from digest_run r
      where r.member_id = m.id and r.kind = d.kind and r.period_start = d.period_start
    );
$$;

comment on function digest_due(timestamptz) is
  'Who is due a digest at a given moment and has not had it (R9, R10, R15, R17). Monday 09:00 and the 1st at 09:00, in the household''s timezone; a missed hour self-heals because the answer stays true until the row exists.';

grant execute on function digest_due(timestamptz) to hh_agent, hh_admin;

-- migrate:down
drop function digest_due(timestamptz);
drop policy if exists digest_run_select_own on digest_run;
drop policy if exists digest_run_admin on digest_run;
drop policy if exists digest_run_agent on digest_run;
drop table digest_run;
drop policy if exists member_update_own on member;
revoke update (digest_weekly, digest_monthly) on member from hh_member, hh_agent;
alter table member drop column digest_monthly;
alter table member drop column digest_weekly;
