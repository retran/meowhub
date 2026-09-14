-- pgTAP: the tools the agent chooses with (spec 0004 T6, ADR 0046).
-- v_merchant_lookup is what replaces the substring match spec 0003's
-- capture-text did in JavaScript, so what it finds and does not find
-- is the contract. The create boundaries are asserted here as the
-- tools' own edges; the wider role grants they rest on are proven in
-- db/tests/013 and db/tests/019.
begin;
select plan(9);

select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin')  returning id \gset admin_
insert into member (role) values ('member') returning id \gset a_
insert into account (type, name) values ('expense', 'groceries') returning id \gset groceries_
insert into merchant (name, default_category_id) values ('Albert Heijn', :groceries_id) returning id \gset ah_
insert into merchant_alias (merchant_id, alias) values (:ah_id, 'ah'), (:ah_id, 'appie');
insert into merchant (name) values ('Green Leaf Diner') returning id \gset diner_

-- find_merchant: the merchant's own name is matchable.
select is(
  (select merchant_id from v_merchant_lookup where match_text ilike '%albert heijn%' and match_kind = 'name'),
  :ah_id::bigint,
  'find_merchant: a merchant is found by its own name'
);

-- find_merchant: and so is every alias it has collected, which is the
-- whole point -- "ah" is what a member actually types.
select is(
  (select distinct merchant_id from v_merchant_lookup where match_text ilike 'ah'),
  :ah_id::bigint,
  'find_merchant: a merchant is found by a short alias a member would actually type'
);
select is(
  (select distinct merchant_id from v_merchant_lookup where match_text ilike 'appie'),
  :ah_id::bigint,
  'find_merchant: a second alias for the same merchant resolves to it too'
);

-- The default category rides along, so a capture at a known merchant
-- needs no category guess at all (spec 0003 R13, A10).
select is(
  (select distinct default_category_slug from v_merchant_lookup where merchant_id = :'ah_id'),
  'groceries',
  'find_merchant: the merchant''s default category comes back with it, so no category need be guessed'
);

-- A merchant with no aliases is still findable by name, and a string
-- belonging to nothing finds nothing -- "this is new" has to be a real
-- answer, not an empty result the agent cannot distinguish.
select is(
  (select count(*)::int from v_merchant_lookup where match_text ilike '%green leaf%'),
  1,
  'find_merchant: a merchant with no aliases is findable by name alone'
);
select is(
  (select count(*)::int from v_merchant_lookup where match_text ilike '%merchant nobody has ever visited%'),
  0,
  'find_merchant: an unknown name finds nothing, which is what makes "this is new" a decision'
);

-- create_merchant composes as the agent (ADR 0042): a new merchant and
-- the spelling that found it, in one member's name.
set role hh_agent;
select set_config('meowhub.actor', :'a_id', true);
select lives_ok(
  $$ insert into merchant (name) values ('Coffee Corner') $$,
  'create_merchant: the agent composes a merchant it has just met'
);
select lives_ok(
  format($$ insert into merchant_alias (merchant_id, alias) values (%s, 'coffee corner on the square') $$, :'diner_id'),
  'create_merchant: the agent records the spelling the member used as an alias'
);
reset role;

-- ...and a member never writes the registry themselves, whatever they
-- typed. The tool is "composes"/hh_agent for exactly this reason.
set role hh_member;
select set_config('meowhub.actor', :'a_id', true);
select throws_ok(
  $$ insert into merchant (name) values ('Sneaky Shop') $$,
  null, null, 'create_merchant: a member has no grant to write the merchant registry directly'
);
reset role;

select * from finish();
rollback;
