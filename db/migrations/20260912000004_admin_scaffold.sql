-- migrate:up

-- A minimal scaffold for the first admin (spec 0001 T17, R14e) — just
-- enough to prove "create one, refuse a second, mark the password
-- initial" before any identity design exists. Spec 0002 replaces this
-- table with the full accounts/members/roles schema; this one is not
-- meant to survive that migration unchanged.
create extension if not exists pgcrypto;

create table if not exists admin_account (
  id                    bigint generated always as identity primary key,
  email                 text not null unique,
  password_hash         text not null,
  password_is_initial   boolean not null default true,
  created_at            timestamptz not null default now()
);

comment on table admin_account is
  'Scaffold only (spec 0001 T17). Superseded by spec 0002''s accounts/members/roles schema.';

-- migrate:down
drop table if exists admin_account;
drop extension if exists pgcrypto;
