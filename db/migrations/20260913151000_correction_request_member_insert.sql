-- migrate:up

-- A real gap found by spec 0003 T14's declared-tool audit (A42):
-- request_correction (tools/request_correction.json) is declared
-- "shape": "acts_as", "permission": "hh_member" -- a non-admin's own
-- explicit request for a change they may not make themselves (R16a),
-- exactly the "explicitly asked for" case ADR 0042 puts on the
-- asking member's own role, not the agent's. T4 never granted
-- hh_member INSERT on correction_request at all (only hh_agent got
-- full CRUD there); T11's workflow worked around that by minting
-- hh_agent instead, which functioned but contradicted the tool's own
-- declared permission. This grants what was actually declared, with a
-- check tying the row to the requesting member's own actor identity.
grant insert on correction_request to hh_member;

create policy correction_request_insert_own on correction_request
  for insert to hh_member
  with check (requested_by = (current_setting('meowhub.actor', true))::bigint);

-- migrate:down
drop policy correction_request_insert_own on correction_request;
revoke insert on correction_request from hh_member;
