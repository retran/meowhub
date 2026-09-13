-- migrate:up

-- audit_log_trigger (spec 0001 T5) requires meowhub.actor to be set in the
-- same transaction as a write to any audited table, so PostgREST needs a
-- way to set it from the verified JWT's own member_id claim on every
-- request — otherwise every write PostgREST makes on a member's behalf
-- fails outright. PostgREST calls whatever function PGRST_DB_PRE_REQUEST
-- names before running the request itself (spec 0002 T12).
create or replace function pgrst_pre_request()
returns void
language plpgsql
as $$
declare
  v_member_id text;
begin
  v_member_id := current_setting('request.jwt.claims', true)::json ->> 'member_id';
  if v_member_id is not null then
    perform set_config('meowhub.actor', v_member_id, true);
  end if;
end;
$$;

comment on function pgrst_pre_request() is
  'Wired via PGRST_DB_PRE_REQUEST (spec 0002 T12): sets meowhub.actor from the JWT''s own member_id claim, the same actor audit_log_trigger already requires for a direct psql session.';

-- PostgREST calls this already impersonating the request's own role
-- (SET ROLE happens first), so every role that can write to an audited
-- table must be able to call it.
grant execute on function pgrst_pre_request() to hh_member, hh_admin, hh_agent;

-- migrate:down
drop function if exists pgrst_pre_request();
