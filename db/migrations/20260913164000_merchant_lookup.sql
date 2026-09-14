-- migrate:up

-- spec 0004 T6 / ADR 0046: the agent chooses a merchant by asking the
-- registry, so the question "do we already know this shop?" is one
-- filtered read rather than a substring match performed in a
-- workflow's own JavaScript (which is how spec 0003's capture-text
-- did it, and why the agent could not actually choose).
--
-- One row per way a merchant can be recognised: its own name, and each
-- alias it has collected. match_kind says which, so the agent can tell
-- "this is what the shop is called" from "this is something someone
-- once typed".
create view v_merchant_lookup with (security_invoker = true) as
select
  m.id as merchant_id, m.name as merchant_name, m.active,
  m.default_category_id, cat.name as default_category_slug,
  m.name as match_text, 'name' as match_kind
from merchant m
left join account cat on cat.id = m.default_category_id
union all
select
  m.id, m.name, m.active,
  m.default_category_id, cat.name,
  a.alias, 'alias'
from merchant m
join merchant_alias a on a.merchant_id = m.id
left join account cat on cat.id = m.default_category_id;

comment on view v_merchant_lookup is
  'Every string a merchant can be recognised by -- its own name and each alias -- with the category it defaults to. The agent''s find_merchant tool filters this; nothing matches merchants in application code (ADR 0046).';

grant select on v_merchant_lookup to hh_member, hh_agent, hh_admin;

-- migrate:down
revoke select on v_merchant_lookup from hh_member, hh_agent, hh_admin;
drop view v_merchant_lookup;
