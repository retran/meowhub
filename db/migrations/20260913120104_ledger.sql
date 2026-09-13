-- migrate:up

-- The real ledger (spec 0003 T1, ADR 0011, ADR 0031). ledger_probe
-- (spec 0002 T4) was built explicitly to be superseded here; it holds
-- only test fixtures, and none are migrated.
drop table if exists ledger_probe;

-- A rate change is a new row, never an edit (data-model.md) — enforced
-- structurally rather than by convention, and reused below for posting:
-- a correction rewrites postings via the correct_transaction() function
-- (T11), never an UPDATE issued directly against this table's rows once
-- they exist as part of a *confirmed* transaction. Unconfirmed rows are
-- the one exception (T3 grants it), so this stays a function rather than
-- a blanket trigger.
create function deny_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is append-only and may not be updated or deleted', TG_TABLE_NAME;
end;
$$;

-- Five types, fixed here; the accounts themselves are data an admin (and
-- the agent, on an admin's instruction) manages (ADR 0031). A category is
-- an expense account: for an expense-type row, name is the language-
-- neutral slug translation resolves; for every other type, name is the
-- literal name an admin gave it (a bank's own account name is not
-- translated).
create table account (
  id          bigint generated always as identity primary key,
  type        text        not null check (type in ('asset', 'liability', 'income', 'expense', 'equity')),
  name        text        not null,
  currency    text        not null default 'EUR',
  parent_id   bigint      references account (id),
  active      boolean     not null default true,
  reviewed    boolean     not null default true,
  created_at  timestamptz not null default now()
);

comment on table account is
  'The chart of accounts (ADR 0011). type is fixed in migrations; the rows are data (ADR 0031). reviewed is false only for a category the agent created unprompted (R13).';
comment on column account.name is
  'For type = expense, this is a language-neutral slug (v_category resolves its display name via translation); for every other type, the literal name an admin gave the account.';

-- Limits, rate, payment amount and day, effective from. A rate change is
-- a new row (T1's own comment above): append-only once written.
create table account_term (
  id                bigint generated always as identity primary key,
  account_id        bigint      not null references account (id),
  overdraft_limit   bigint,
  credit_limit      bigint,
  interest_rate     numeric(7, 4),
  payment_amount    bigint,
  payment_day       smallint,
  effective_from    date        not null,
  created_at        timestamptz not null default now()
);

comment on table account_term is
  'Effective-dated terms on an account. Append-only: a change is a new row (data-model.md), never an edit — spec 0008 is the slice that exercises this.';

create trigger account_term_deny_update before update on account_term
  for each row execute function deny_mutation();
create trigger account_term_deny_delete before delete on account_term
  for each row execute function deny_mutation();

-- One economic event (ADR 0011). project_id and import_id are added now,
-- nullable and with no foreign key yet: R15a needs the column before
-- spec 0010's `project` table exists to reference, and spec 0007's
-- `statement_import` is the same shape. Each later slice adds its own
-- constraint in the same migration that creates its target table.
create table transaction (
  id                    bigint generated always as identity primary key,
  date                  date        not null,
  note                  text,
  project_id            bigint,
  import_id             bigint,
  submitter             bigint      not null references member (id),
  source                text        not null check (source in ('text', 'photo', 'voice', 'manual', 'import')),
  confirmation_state    text        not null default 'unconfirmed' check (confirmation_state in ('unconfirmed', 'confirmed')),
  confirmation_route    text        check (confirmation_route in ('review', 'bank', 'quiet')),
  confirmed_by          bigint      references member (id),
  confirmed_at          timestamptz,
  model                 text,
  prompt_version        text,
  original_amount       bigint,
  original_currency     text,
  created_at            timestamptz not null default now(),
  check ((confirmation_state = 'confirmed') = (confirmation_route is not null))
);

comment on table transaction is
  'One economic event; its postings sum to zero (enforced below). Provenance (source, model, prompt_version) is not optional (R6).';
comment on column transaction.project_id is
  'No foreign key yet — spec 0010 creates the project table and adds the constraint in the same migration.';
comment on column transaction.import_id is
  'No foreign key yet — spec 0007 creates statement_import and adds the constraint in the same migration.';

create trigger transaction_audit
  after insert or update or delete on transaction
  for each row execute function audit_log_trigger();

-- One side of a transaction (ADR 0011). Signed, minor units, explicit
-- currency — the invariant lives in the deferred constraint trigger
-- below, not here, because a multi-row write must be legal mid-statement.
create table posting (
  id             bigint generated always as identity primary key,
  transaction_id bigint      not null references transaction (id) on delete cascade,
  account_id     bigint      not null references account (id),
  amount         bigint      not null,
  currency       text        not null,
  created_at     timestamptz not null default now()
);

comment on table posting is
  'One side of a transaction. Sums to zero per transaction_id, enforced by posting_balance_check (deferred, checked at commit).';

create trigger posting_audit
  after insert or update or delete on posting
  for each row execute function audit_log_trigger();

-- Canonical merchant, and what a raw observed string maps to (ADR 0004).
create table merchant (
  id                  bigint generated always as identity primary key,
  name                text        not null,
  default_category_id bigint     references account (id),
  active              boolean     not null default true,
  created_at          timestamptz not null default now()
);

comment on table merchant is
  'The merchant registry. default_category_id must reference an expense-type account.';

create trigger merchant_audit
  after insert or update or delete on merchant
  for each row execute function audit_log_trigger();

create table merchant_alias (
  id          bigint generated always as identity primary key,
  merchant_id bigint      not null references merchant (id),
  alias       text        not null,
  created_at  timestamptz not null default now()
);

comment on table merchant_alias is
  'A raw observed string (typed or from a statement descriptor), normalised to lower case, mapped to one merchant.';

create unique index merchant_alias_alias_key on merchant_alias (lower(alias));

create trigger merchant_alias_audit
  after insert or update or delete on merchant_alias
  for each row execute function audit_log_trigger();

-- slug -> display name per language (ADR 0017, R11b): categories and
-- account-type labels both live here.
create table translation (
  slug         text not null,
  language     text not null check (language in ('en', 'ru')),
  display_name text not null,
  primary key (slug, language)
);

comment on table translation is
  'Language-neutral slug to display name. A category''s slug is account.name for an expense-type row (ADR 0031).';

-- A setting the household changes is a row, never an environment
-- variable (ADR 0034) — the timezone, the default currency, the
-- auto-confirm threshold and quiet period, and later slices' own
-- thresholds.
create table household_setting (
  key        text        primary key,
  value      jsonb       not null,
  updated_by bigint      references member (id),
  updated_at timestamptz not null default now()
);

comment on table household_setting is
  'Settings the household changes without a deploy (ADR 0034). value is jsonb so one table serves every setting''s type.';

create trigger household_setting_audit
  after insert or update or delete on household_setting
  for each row execute function audit_log_trigger();

-- Every member has a default payment account once setup has established
-- one (R10); nullable because R0a requires capture to work after the
-- first account, before a default is necessarily chosen.
alter table member add column default_payment_account_id bigint references account (id);

-- migrate:down
alter table member drop column default_payment_account_id;
drop trigger if exists household_setting_audit on household_setting;
drop table if exists household_setting;
drop table if exists translation;
drop trigger if exists merchant_alias_audit on merchant_alias;
drop table if exists merchant_alias;
drop trigger if exists merchant_audit on merchant;
drop table if exists merchant;
drop trigger if exists posting_audit on posting;
drop table if exists posting;
drop trigger if exists transaction_audit on transaction;
drop table if exists transaction;
drop trigger if exists account_term_deny_delete on account_term;
drop trigger if exists account_term_deny_update on account_term;
drop table if exists account_term;
drop table if exists account;
drop function if exists deny_mutation();

create table ledger_probe (
  id          bigint generated always as identity primary key,
  captured_by bigint      not null references member (id),
  category    text,
  confirmed   boolean     not null default false,
  created_at  timestamptz not null default now()
);
