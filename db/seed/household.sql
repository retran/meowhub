-- The synthetic household (ADR 0015): three members, a starter chart in
-- both languages, real opening balances, and several months of
-- transactions including a card settlement, a cash-advance fee and a
-- loan-payment split — every special case ADR 0011 exists for. Fixture,
-- demo and development data at once. Not idempotent: run once, against a
-- freshly migrated database.
begin;
select set_config('meowhub.actor', 'seed', true);

-- Members: two admins, one member (the household's real shape).
insert into member (role, language, theme) values ('admin', 'en', 'dark') returning id \gset admin1_
insert into member (role, language, theme) values ('admin', 'ru', 'dark') returning id \gset admin2_
insert into member (role, language, theme) values ('member', 'ru', 'light') returning id \gset kid_

-- The chart: two bank accounts (one with an overdraft), one credit card,
-- one loan, cash, income, and the opening-balance equity account.
insert into account (type, name) values ('asset', 'ABN AMRO Current') returning id \gset abn_
insert into account (type, name) values ('asset', 'ING Current') returning id \gset ing_
insert into account (type, name) values ('asset', 'Cash') returning id \gset cash_
insert into account (type, name) values ('liability', 'ICS Credit Card') returning id \gset card_
insert into account (type, name) values ('liability', 'Loan:Car') returning id \gset loan_
insert into account (type, name) values ('income', 'Salary') returning id \gset salary_
insert into account (type, name) values ('equity', 'Opening Balances') returning id \gset opening_

insert into account_term (account_id, overdraft_limit, effective_from) values (:abn_id, 100000, '2026-01-01');
insert into account_term (account_id, credit_limit, effective_from) values (:card_id, 300000, '2026-01-01');
insert into account_term (account_id, interest_rate, payment_amount, payment_day, effective_from)
  values (:loan_id, 4.9, 25000, 1, '2026-01-01');

-- Categories, both languages, curated (reviewed = true — the seed is not
-- what ADR 0031's unreviewed path is demonstrating).
insert into account (type, name) values
  ('expense', 'groceries'),
  ('expense', 'transport'),
  ('expense', 'dining'),
  ('expense', 'fees.cash-advance'),
  ('expense', 'interest.overdraft'),
  ('expense', 'interest.loan');

insert into translation (slug, language, display_name) values
  ('groceries', 'en', 'Groceries'), ('groceries', 'ru', 'Продукты'),
  ('transport', 'en', 'Transport'), ('transport', 'ru', 'Транспорт'),
  ('dining', 'en', 'Dining out'), ('dining', 'ru', 'Рестораны'),
  ('fees.cash-advance', 'en', 'Cash advance fees'), ('fees.cash-advance', 'ru', 'Комиссии за снятие наличных'),
  ('interest.overdraft', 'en', 'Overdraft interest'), ('interest.overdraft', 'ru', 'Проценты по овердрафту'),
  ('interest.loan', 'en', 'Loan interest'), ('interest.loan', 'ru', 'Проценты по кредиту');

select id into temporary groceries_acc from account where name = 'groceries';
select id into temporary transport_acc from account where name = 'transport';
select id into temporary dining_acc from account where name = 'dining';
select id into temporary cash_advance_acc from account where name = 'fees.cash-advance';
select id into temporary overdraft_int_acc from account where name = 'interest.overdraft';
select id into temporary loan_int_acc from account where name = 'interest.loan';

-- Merchants, with an alias each (proving the registry from day one).
insert into merchant (name, default_category_id) values ('Albert Heijn', (select id from groceries_acc)) returning id \gset ah_
insert into merchant_alias (merchant_id, alias) values (:ah_id, 'albert heijn'), (:ah_id, 'ah');
insert into merchant (name, default_category_id) values ('NS', (select id from transport_acc)) returning id \gset ns_
insert into merchant_alias (merchant_id, alias) values (:ns_id, 'ns'), (:ns_id, 'ns groep');

-- Household settings: the direction this project already committed to.
insert into household_setting (key, value, updated_by) values
  ('timezone', '"Europe/Amsterdam"', :admin1_id),
  ('default_currency', '"EUR"', :admin1_id),
  ('auto_confirm_threshold_minor', '2000', :admin1_id),
  ('auto_confirm_quiet_period_hours', '24', :admin1_id);

update member set default_payment_account_id = :abn_id where id in (:admin1_id, :admin2_id);
update member set default_payment_account_id = :cash_id where id = :kid_id;

-- Opening balances, each its own transaction against the equity account
-- (R3), confirmed on creation (ADR 0023 — nothing for a human to
-- second-guess in a number the household stated).
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-01-01', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset ob1_
insert into posting (transaction_id, account_id, amount, currency) values (:ob1_id, :abn_id, 350000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:ob1_id, :opening_id, -350000, 'EUR');

insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-01-01', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset ob2_
insert into posting (transaction_id, account_id, amount, currency) values (:ob2_id, :ing_id, 120000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:ob2_id, :opening_id, -120000, 'EUR');

insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-01-01', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset ob3_
insert into posting (transaction_id, account_id, amount, currency) values (:ob3_id, :cash_id, 5000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:ob3_id, :opening_id, -5000, 'EUR');

insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-01-01', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset ob4_
insert into posting (transaction_id, account_id, amount, currency) values (:ob4_id, :opening_id, 800000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:ob4_id, :loan_id, -800000, 'EUR');

-- Ordinary captures across three months, confirmed (this is settled
-- history, not today's review queue).
insert into transaction (date, submitter, source, merchant_id, category_source, model, prompt_version, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-01-05', :kid_id, 'text', :ah_id, 'merchant_default', 'stub/echo', 'capture-text@1', 'confirmed', 'quiet', null, now()) returning id \gset t1_
insert into posting (transaction_id, account_id, amount, currency) values (:t1_id, :cash_id, -1850, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:t1_id, (select id from groceries_acc), 1850, 'EUR');

insert into transaction (date, submitter, source, merchant_id, category_source, model, prompt_version, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-01-12', :admin2_id, 'text', :ns_id, 'merchant_default', 'stub/echo', 'capture-text@1', 'confirmed', 'quiet', null, now()) returning id \gset t2_
insert into posting (transaction_id, account_id, amount, currency) values (:t2_id, :abn_id, -1240, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:t2_id, (select id from transport_acc), 1240, 'EUR');

insert into transaction (date, submitter, source, category_source, model, prompt_version, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-01-20', :admin1_id, 'text', 'model', 'stub/echo', 'capture-text@1', 'confirmed', 'review', :admin1_id, now()) returning id \gset t3_
insert into posting (transaction_id, account_id, amount, currency) values (:t3_id, :card_id, -4500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:t3_id, (select id from dining_acc), 4500, 'EUR');

-- Card settlement: the liability goes down, the bank account goes down —
-- a transfer, never spending (ADR 0011's whole point).
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-02-01', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset settle_
insert into posting (transaction_id, account_id, amount, currency) values (:settle_id, :abn_id, -4500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:settle_id, :card_id, 4500, 'EUR');

-- A cash advance: cash up, card liability up by principal plus fee, the
-- fee visible as its own expense (ADR 0011).
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-02-10', :admin2_id, 'manual', 'confirmed', 'review', :admin2_id, now()) returning id \gset advance_
insert into posting (transaction_id, account_id, amount, currency) values (:advance_id, :cash_id, 10000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:advance_id, :card_id, -10300, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:advance_id, (select id from cash_advance_acc), 300, 'EUR');

-- Overdraft interest, charged when the bank charges it (cash-basis
-- recognition, ADR 0011) — not accrued daily.
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-02-28', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset odint_
insert into posting (transaction_id, account_id, amount, currency) values (:odint_id, :abn_id, -1500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:odint_id, (select id from overdraft_int_acc), 1500, 'EUR');

-- A loan payment split into principal (reduces the liability, never
-- spending) and interest (an expense) — the single most common
-- household bookkeeping error, and the reason ADR 0011 exists.
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-03-01', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset loanpay_
insert into posting (transaction_id, account_id, amount, currency) values (:loanpay_id, :abn_id, -25000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:loanpay_id, :loan_id, 21700, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:loanpay_id, (select id from loan_int_acc), 3300, 'EUR');

-- Salary, income posting the other way (a negative on an income account).
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, confirmed_by, confirmed_at)
  values ('2026-03-01', :admin1_id, 'manual', 'confirmed', 'review', :admin1_id, now()) returning id \gset salary_txn_
insert into posting (transaction_id, account_id, amount, currency) values (:salary_txn_id, :abn_id, 320000, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:salary_txn_id, :salary_id, -320000, 'EUR');

-- A few unconfirmed captures — the current, live review queue.
insert into transaction (date, submitter, source, merchant_id, category_source, model, prompt_version, inferred_fields)
  values (current_date, :kid_id, 'text', :ah_id, 'merchant_default', 'stub/echo', 'capture-text@1', array['account', 'date']) returning id \gset u1_
insert into posting (transaction_id, account_id, amount, currency) values (:u1_id, :cash_id, -2200, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:u1_id, (select id from groceries_acc), 2200, 'EUR');

insert into transaction (date, submitter, source, category_source, model, prompt_version, inferred_fields)
  values (current_date - 1, :admin2_id, 'text', 'model', 'stub/echo', 'capture-text@1', array['merchant', 'category']) returning id \gset u2_
insert into posting (transaction_id, account_id, amount, currency) values (:u2_id, :abn_id, -6700, 'EUR');
insert into posting (transaction_id, account_id, amount, currency) values (:u2_id, (select id from dining_acc), 6700, 'EUR');

commit;
