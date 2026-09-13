-- pgTAP: the real ledger tables exist with the shape the catalogue
-- promises, and ledger_probe (spec 0002 T4's scaffold) is gone
-- (spec 0003 T1).
begin;
select plan(14);

select hasnt_table('public', 'ledger_probe', 'ledger_probe is dropped, superseded by transaction/posting');

select has_table('public', 'account', 'account exists');
select col_has_check('public', 'account', 'type', 'account.type is constrained to the five ADR 0011 types');

select has_table('public', 'account_term', 'account_term exists');
select has_table('public', 'transaction', 'transaction exists');
select has_table('public', 'posting', 'posting exists');
select has_table('public', 'merchant', 'merchant exists');
select has_table('public', 'merchant_alias', 'merchant_alias exists');
select has_table('public', 'translation', 'translation exists');
select col_is_pk('public', 'translation', array['slug', 'language'], 'translation is keyed on (slug, language)');
select has_table('public', 'household_setting', 'household_setting exists');
select has_column('public', 'member', 'default_payment_account_id', 'member.default_payment_account_id exists');

-- account_term is append-only (data-model.md: a rate change is a new row)
select set_config('meowhub.actor', 'test-suite', true);
insert into account (type, name) values ('asset', 'Assets:Test') returning id \gset acc_
insert into account_term (account_id, effective_from) values (:acc_id, current_date) returning id \gset term_

select throws_ok(
  $$ update account_term set effective_from = current_date + 1 $$,
  'P0001',
  null,
  'account_term rejects an update — a rate change is a new row'
);
select throws_ok(
  $$ delete from account_term $$,
  'P0001',
  null,
  'account_term rejects a delete'
);

select * from finish();
rollback;
