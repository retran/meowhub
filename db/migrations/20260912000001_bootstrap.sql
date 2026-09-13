-- migrate:up

-- Proves the migration mechanism itself before anything valuable depends on
-- it (spec 0001, T2). A trivial table, deliberately.
create table if not exists bootstrap_probe (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now()
);

comment on table bootstrap_probe is
  'Exists only to prove migrations apply and are idempotent. Not used by the product.';

-- migrate:down
drop table if exists bootstrap_probe;
