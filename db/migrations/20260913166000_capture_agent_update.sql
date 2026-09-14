-- migrate:up

-- A real gap found migrating capture onto the agent loop (spec 0004
-- T9a): hh_agent could insert a capture row but never update one.
--
-- Spec 0003's capture-text never needed to. It decided the whole
-- outcome first and wrote the row once, already final. The loop cannot
-- work that way: R6a requires the inbound message to be stored
-- *before* anything is attempted, so nothing is lost when the gateway
-- is unreachable — which means the row is written before the exchange
-- has an outcome, and the outcome is an update.
--
-- Column-level on purpose. The agent may attach a row to the exchange
-- it belongs to and record what became of it; it may never touch
-- raw_text, so "the exact text of the message, retrievable later
-- exactly as sent" (R6a) is a guarantee of the grant rather than of
-- the agent's good behaviour.
grant update (conversation_id, state, transaction_id) on capture to hh_agent;

-- migrate:down
revoke update (conversation_id, state, transaction_id) on capture from hh_agent;
