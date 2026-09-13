-- migrate:up

-- A real gap found by spec 0003 T10: T4's grants assumed every
-- conversation is created by hh_agent, composing on someone's behalf.
-- Starting a *setup* conversation is the asking admin's own structural
-- request (ADR 0042's "acts_as" — the same reasoning that already put
-- open_account and amend_account on the admin's own role), so hh_admin
-- needs INSERT here too, not just SELECT/UPDATE.
-- The existing conversation_admin policy already says "for all" — it was
-- always permissive enough. What was missing is the base GRANT: a
-- policy only ever narrows what a role's own privileges already allow,
-- so an admin with no INSERT grant at all was refused before the
-- policy was even consulted.
grant insert on conversation to hh_admin;

-- migrate:down
revoke insert on conversation from hh_admin;
