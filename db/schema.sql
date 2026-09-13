\restrict dbmate

-- Dumped from database version 16.15 (Debian 16.15-1.pgdg13+2)
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: account_agent_insert_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.account_agent_insert_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if pg_has_role(current_user, 'hh_agent', 'member') and not pg_has_role(current_user, 'hh_admin', 'member') then
    if new.type <> 'expense' or new.reviewed then
      raise exception 'account_agent_insert_guard: the agent may only create an unreviewed expense category unprompted (ADR 0031)';
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: audit_log_deny_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_deny_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  raise exception 'audit_log is append-only and may not be updated or deleted';
end;
$$;


--
-- Name: audit_log_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_actor text;
  v_row_id text;
begin
  begin
    v_actor := current_setting('meowhub.actor');
  exception when others then
    v_actor := null;
  end;

  if v_actor is null or v_actor = '' then
    raise exception 'audit_log_trigger: meowhub.actor must be set for writes to %', TG_TABLE_NAME;
  end if;

  if TG_OP = 'DELETE' then
    v_row_id := (row_to_json(old)->>'id');
  else
    v_row_id := (row_to_json(new)->>'id');
  end if;

  insert into audit_log (table_name, row_id, operation, before_state, after_state, actor)
  values (
    TG_TABLE_NAME,
    v_row_id,
    lower(TG_OP),
    case when TG_OP in ('UPDATE', 'DELETE') then row_to_json(old)::jsonb else null end,
    case when TG_OP in ('UPDATE', 'INSERT') then row_to_json(new)::jsonb else null end,
    v_actor
  );

  if TG_OP = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;


--
-- Name: correct_posting_amounts(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.correct_posting_amounts(p_transaction_id bigint, p_new_amount_minor bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  r record;
begin
  for r in select id, amount from posting where transaction_id = p_transaction_id loop
    if r.amount < 0 then
      update posting set amount = -p_new_amount_minor where id = r.id;
    else
      update posting set amount = p_new_amount_minor where id = r.id;
    end if;
  end loop;
end;
$$;


--
-- Name: FUNCTION correct_posting_amounts(p_transaction_id bigint, p_new_amount_minor bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.correct_posting_amounts(p_transaction_id bigint, p_new_amount_minor bigint) IS 'Corrects both legs of a transaction to a new magnitude in one commit (R15). Not SECURITY DEFINER -- RLS and posting_member_update_guard still apply per row, as the calling role.';


--
-- Name: deny_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deny_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  raise exception '% is append-only and may not be updated or deleted', TG_TABLE_NAME;
end;
$$;


--
-- Name: ledger_probe_member_update_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_probe_member_update_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if pg_has_role(current_user, 'hh_admin', 'member') then
    return new;
  end if;

  if new.confirmed is distinct from old.confirmed
     or new.captured_by is distinct from old.captured_by then
    if old.confirmed or old.captured_by <> current_setting('meowhub.actor')::bigint then
      raise exception 'ledger_probe_member_update_guard: only the capturing member may confirm or correct their own unconfirmed record';
    end if;
  end if;

  return new;
end;
$$;


--
-- Name: pgrst_pre_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pgrst_pre_request() RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  v_member_id text;
begin
  v_member_id := current_setting('request.jwt.claims', true)::json ->> 'member_id';
  if v_member_id is not null then
    perform set_config('meowhub.actor', v_member_id, true);
  end if;
end;
$$;


--
-- Name: FUNCTION pgrst_pre_request(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.pgrst_pre_request() IS 'Wired via PGRST_DB_PRE_REQUEST (spec 0002 T12): sets meowhub.actor from the JWT''s own member_id claim, the same actor audit_log_trigger already requires for a direct psql session.';


--
-- Name: posting_balance_check(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.posting_balance_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_transaction_id bigint;
  v_sum bigint;
begin
  v_transaction_id := coalesce(new.transaction_id, old.transaction_id);
  select sum(amount) into v_sum from posting where transaction_id = v_transaction_id;
  if v_sum is not null and v_sum <> 0 then
    raise exception 'posting_balance_check: transaction % has postings summing to % instead of 0', v_transaction_id, v_sum;
  end if;
  return null;
end;
$$;


--
-- Name: posting_member_update_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.posting_member_update_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_actor bigint;
  v_txn record;
  v_reclassify_only boolean;
begin
  if pg_has_role(current_user, 'hh_admin', 'member') then
    return new;
  end if;

  v_reclassify_only := (new.amount, new.currency) is not distinct from (old.amount, old.currency);

  if v_reclassify_only then
    -- Reclassification only makes sense onto another expense-type account.
    if not exists (select 1 from account where id = new.account_id and type = 'expense') then
      raise exception 'posting_member_update_guard: a member may only reclassify a posting onto an expense-type account';
    end if;
    return new;
  end if;

  v_actor := nullif(current_setting('meowhub.actor', true), '')::bigint;
  select submitter, confirmation_state into v_txn from transaction where id = old.transaction_id;

  if v_txn.submitter is distinct from v_actor then
    raise exception 'posting_member_update_guard: only the capturing member may correct their own posting';
  end if;
  if v_txn.confirmation_state = 'confirmed' then
    raise exception 'posting_member_update_guard: a posting on a confirmed transaction may only be changed by an admin';
  end if;

  return new;
end;
$$;


--
-- Name: transaction_agent_confirm_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transaction_agent_confirm_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_threshold bigint;
  v_quiet_hours bigint;
  v_expense_amount bigint;
begin
  if pg_has_role(current_user, 'hh_agent', 'member') and not pg_has_role(current_user, 'hh_admin', 'member') then
    if old.confirmation_state <> 'unconfirmed'
      or new.confirmation_state <> 'confirmed'
      or new.confirmation_route <> 'quiet'
      or old.category_source is distinct from 'merchant_default'
    then
      raise exception 'transaction_agent_confirm_guard: the agent may only auto-confirm a known merchant''s own category, from unconfirmed to confirmed via the quiet route (R7c)';
    end if;

    select (value #>> '{}')::bigint into v_threshold
      from household_setting where key = 'auto_confirm_threshold_minor';
    select (value #>> '{}')::bigint into v_quiet_hours
      from household_setting where key = 'auto_confirm_quiet_period_hours';

    -- An unset threshold is the same as zero (spec 0003's own edge
    -- case: "An auto-confirm threshold set to zero: nothing
    -- auto-confirms") — never a default that quietly confirms
    -- everything just because the household never configured it.
    if v_threshold is null or v_threshold <= 0 or v_quiet_hours is null then
      raise exception 'transaction_agent_confirm_guard: auto-confirmation is not configured (R7c)';
    end if;

    select abs(amount) into v_expense_amount
      from posting where transaction_id = old.id and amount > 0
      order by amount desc limit 1;

    if v_expense_amount is null or v_expense_amount >= v_threshold then
      raise exception 'transaction_agent_confirm_guard: amount is not below the configured threshold (R7c)';
    end if;

    if old.created_at > now() - (v_quiet_hours || ' hours')::interval then
      raise exception 'transaction_agent_confirm_guard: the quiet period has not elapsed (R7c)';
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: FUNCTION transaction_agent_confirm_guard(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.transaction_agent_confirm_guard() IS 'The database, not the calling workflow, is what actually enforces R7c''s conditions on an hh_agent-driven auto-confirmation.';


--
-- Name: transaction_member_update_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transaction_member_update_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_reclassify_only boolean;
  v_actor bigint;
begin
  if pg_has_role(current_user, 'hh_admin', 'member') or pg_has_role(current_user, 'hh_agent', 'member') then
    return new;
  end if;

  v_actor := nullif(current_setting('meowhub.actor', true), '')::bigint;

  -- project_id and note are never financial facts (R15a, R25): always
  -- allowed regardless of ownership or confirmation state.
  v_reclassify_only :=
    (new.date, new.merchant_id, new.model, new.prompt_version, new.original_amount,
     new.original_currency, new.source, new.confirmation_state, new.confirmation_route)
    is not distinct from
    (old.date, old.merchant_id, old.model, old.prompt_version, old.original_amount,
     old.original_currency, old.source, old.confirmation_state, old.confirmation_route);

  if v_reclassify_only then
    return new;
  end if;

  -- Anything else touches a financial fact or the confirmation state:
  -- only the capturing member, only while it is still unconfirmed
  -- (R7b/R7c/R12), and never to un-confirm what is already confirmed.
  if old.submitter is distinct from v_actor then
    raise exception 'transaction_member_update_guard: only the capturing member may correct or confirm their own transaction';
  end if;
  if old.confirmation_state = 'confirmed' then
    raise exception 'transaction_member_update_guard: a confirmed transaction may only be changed by an admin';
  end if;

  return new;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account (
    id bigint NOT NULL,
    type text NOT NULL,
    name text NOT NULL,
    currency text DEFAULT 'EUR'::text NOT NULL,
    parent_id bigint,
    active boolean DEFAULT true NOT NULL,
    reviewed boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT account_type_check CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'income'::text, 'expense'::text, 'equity'::text])))
);

ALTER TABLE ONLY public.account FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE account; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.account IS 'The chart of accounts (ADR 0011). type is fixed in migrations; the rows are data (ADR 0031). reviewed is false only for a category the agent created unprompted (R13).';


--
-- Name: COLUMN account.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account.name IS 'For type = expense, this is a language-neutral slug (v_category resolves its display name via translation); for every other type, the literal name an admin gave the account.';


--
-- Name: account_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.account ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.account_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: account_term; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_term (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    overdraft_limit bigint,
    credit_limit bigint,
    interest_rate numeric(7,4),
    payment_amount bigint,
    payment_day smallint,
    effective_from date NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.account_term FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE account_term; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.account_term IS 'Effective-dated terms on an account. Append-only: a change is a new row (data-model.md), never an edit — spec 0008 is the slice that exercises this.';


--
-- Name: account_term_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.account_term ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.account_term_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: agent_memory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_memory (
    id bigint NOT NULL,
    member_id bigint,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.agent_memory FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE agent_memory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.agent_memory IS 'A standing fact the agent keeps across conversations (ADR 0044) — member_id null means household-wide. Never a financial fact: informs a question or a default, never a transaction''s own state.';


--
-- Name: agent_memory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.agent_memory ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.agent_memory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    table_name text NOT NULL,
    row_id text NOT NULL,
    operation text NOT NULL,
    before_state jsonb,
    after_state jsonb,
    actor text NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_log_operation_check CHECK ((operation = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text, 'denied'::text])))
);

ALTER TABLE ONLY public.audit_log FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE audit_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_log IS 'Append-only. No application role may update or delete a row here (ADR 0008).';


--
-- Name: CONSTRAINT audit_log_operation_check ON audit_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT audit_log_operation_check ON public.audit_log IS '''denied'' records an access attempt with no member behind it (spec 0002 T12, A18) — table_name/row_id name what was attempted, not a row that exists.';


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bootstrap_probe; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bootstrap_probe (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE bootstrap_probe; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.bootstrap_probe IS 'Exists only to prove migrations apply and are idempotent. Not used by the product.';


--
-- Name: bootstrap_probe_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.bootstrap_probe ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.bootstrap_probe_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: capture; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capture (
    id bigint NOT NULL,
    member_id bigint NOT NULL,
    conversation_id bigint,
    sequence integer DEFAULT 1 NOT NULL,
    direction text NOT NULL,
    kind text NOT NULL,
    channel_message_id text,
    raw_text text,
    file_id bigint,
    extracted_payload jsonb,
    state text,
    transaction_id bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    chat_id text,
    CONSTRAINT capture_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text]))),
    CONSTRAINT capture_kind_check CHECK ((kind = ANY (ARRAY['text'::text, 'photo'::text, 'voice'::text]))),
    CONSTRAINT capture_state_check CHECK ((state = ANY (ARRAY['unparsed'::text, 'resolved'::text])))
);

ALTER TABLE ONLY public.capture FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE capture; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.capture IS 'One row per message (R6a) — the exchange that produced a record, in order. state is meaningful on inbound rows only: null on an outbound question.';


--
-- Name: COLUMN capture.chat_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.capture.chat_id IS 'The Telegram chat this message arrived in — a member''s own private chat, or the one shared household group (ADR 0043). Distinct from member_id (the sender): a query for shared context filters on this, a query for whose bookkeeping this is filters on member_id.';


--
-- Name: capture_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.capture ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.capture_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: conversation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation (
    id bigint NOT NULL,
    member_id bigint NOT NULL,
    kind text NOT NULL,
    step text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    opened_at timestamp with time zone DEFAULT now() NOT NULL,
    last_touched_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    CONSTRAINT conversation_kind_check CHECK ((kind = ANY (ARRAY['setup'::text, 'clarification'::text, 'structural_change'::text, 'correction'::text])))
);

ALTER TABLE ONLY public.conversation FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE conversation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.conversation IS 'A multi-turn exchange in progress (ADR 0038). Never the ledger: nothing in payload is a financial fact until it becomes a transaction.';


--
-- Name: conversation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.conversation ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.conversation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: correction_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.correction_request (
    id bigint NOT NULL,
    transaction_id bigint NOT NULL,
    requested_by bigint NOT NULL,
    requested_change jsonb NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    CONSTRAINT correction_request_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])))
);

ALTER TABLE ONLY public.correction_request FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE correction_request; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.correction_request IS 'A non-admin''s requested correction to a financial fact (R14) — the admins are notified, the transaction is unchanged until an admin acts.';


--
-- Name: correction_request_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.correction_request ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.correction_request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: file; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.file (
    id bigint NOT NULL,
    sha256 text NOT NULL,
    media_type text NOT NULL,
    size_bytes bigint NOT NULL,
    original_name text,
    uploaded_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT file_sha256_check CHECK ((sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT file_size_bytes_check CHECK ((size_bytes >= 0))
);

ALTER TABLE ONLY public.file FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE file; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.file IS 'Metadata for content-addressed files on the storage volume. The path is derived from sha256 (ab/cd/<sha256>); this row never holds the bytes.';


--
-- Name: file_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.file ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.file_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: household_setting; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.household_setting (
    key text NOT NULL,
    value jsonb NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id bigint NOT NULL
);

ALTER TABLE ONLY public.household_setting FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE household_setting; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.household_setting IS 'Settings the household changes without a deploy (ADR 0034). value is jsonb so one table serves every setting''s type.';


--
-- Name: household_setting_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.household_setting ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.household_setting_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: member; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member (
    id bigint NOT NULL,
    role text NOT NULL,
    language text DEFAULT 'ru'::text NOT NULL,
    theme text DEFAULT 'dark'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    default_payment_account_id bigint,
    CONSTRAINT member_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'member'::text])))
);

ALTER TABLE ONLY public.member FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE member; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.member IS 'The person. Role is a property of the member, not of a person (R7). default_payment_account_id arrives with spec 0003''s accounts.';


--
-- Name: member_channel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_channel (
    member_id bigint NOT NULL,
    kind text NOT NULL,
    external_id text NOT NULL,
    linked_by bigint NOT NULL,
    linked_at timestamp with time zone DEFAULT now() NOT NULL,
    id bigint NOT NULL,
    CONSTRAINT member_channel_kind_check CHECK ((kind = 'telegram'::text))
);

ALTER TABLE ONLY public.member_channel FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE member_channel; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.member_channel IS 'Attribution references the member, never the channel id (R6d): re-linking to a different account leaves past history''s member_id unchanged.';


--
-- Name: member_channel_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.member_channel ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.member_channel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: member_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.member ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.member_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: member_identity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_identity (
    member_id bigint NOT NULL,
    provider_subject text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    id bigint NOT NULL
);

ALTER TABLE ONLY public.member_identity FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE member_identity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.member_identity IS 'One member, several sign-in methods (ADR 0032, R3a): a passkey and an Apple ID both attach here, never a second member.';


--
-- Name: member_identity_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.member_identity ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.member_identity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant (
    id bigint NOT NULL,
    name text NOT NULL,
    default_category_id bigint,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.merchant FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE merchant; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant IS 'The merchant registry. default_category_id must reference an expense-type account.';


--
-- Name: merchant_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_alias (
    id bigint NOT NULL,
    merchant_id bigint NOT NULL,
    alias text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.merchant_alias FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE merchant_alias; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_alias IS 'A raw observed string (typed or from a statement descriptor), normalised to lower case, mapped to one merchant.';


--
-- Name: merchant_alias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_alias ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.merchant_alias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.merchant_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: posting; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posting (
    id bigint NOT NULL,
    transaction_id bigint NOT NULL,
    account_id bigint NOT NULL,
    amount bigint NOT NULL,
    currency text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.posting FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE posting; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.posting IS 'One side of a transaction. Sums to zero per transaction_id, enforced by posting_balance_check (deferred, checked at commit).';


--
-- Name: COLUMN posting.amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.posting.amount IS 'Signed, minor units. Asset and expense postings are positive when the household has or spends more; income, equity and liability postings are the mirror — negative when income arrives, an opening balance is set, or debt increases; positive when income is spent from, an opening entry is offset, or debt is paid down. Sums to zero per transaction (posting_balance_check). v_account_balance presents liability balances with the conventional positive-means-owed sign (ADR 0011) — the raw sign here is not that sign.';


--
-- Name: posting_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.posting ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.posting_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: transaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transaction (
    id bigint NOT NULL,
    date date NOT NULL,
    note text,
    project_id bigint,
    import_id bigint,
    submitter bigint NOT NULL,
    source text NOT NULL,
    confirmation_state text DEFAULT 'unconfirmed'::text NOT NULL,
    confirmation_route text,
    confirmed_by bigint,
    confirmed_at timestamp with time zone,
    model text,
    prompt_version text,
    original_amount bigint,
    original_currency text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    merchant_id bigint,
    category_source text,
    inferred_fields text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT transaction_category_source_check CHECK ((category_source = ANY (ARRAY['merchant_default'::text, 'model'::text, 'manual'::text]))),
    CONSTRAINT transaction_check CHECK (((confirmation_state = 'confirmed'::text) = (confirmation_route IS NOT NULL))),
    CONSTRAINT transaction_confirmation_route_check CHECK ((confirmation_route = ANY (ARRAY['review'::text, 'bank'::text, 'quiet'::text]))),
    CONSTRAINT transaction_confirmation_state_check CHECK ((confirmation_state = ANY (ARRAY['unconfirmed'::text, 'confirmed'::text]))),
    CONSTRAINT transaction_source_check CHECK ((source = ANY (ARRAY['text'::text, 'photo'::text, 'voice'::text, 'manual'::text, 'import'::text])))
);

ALTER TABLE ONLY public.transaction FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE transaction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.transaction IS 'One economic event; its postings sum to zero (enforced below). Provenance (source, model, prompt_version) is not optional (R6).';


--
-- Name: COLUMN transaction.project_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.transaction.project_id IS 'No foreign key yet — spec 0010 creates the project table and adds the constraint in the same migration.';


--
-- Name: COLUMN transaction.import_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.transaction.import_id IS 'No foreign key yet — spec 0007 creates statement_import and adds the constraint in the same migration.';


--
-- Name: COLUMN transaction.category_source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.transaction.category_source IS 'Where the category posting''s account came from: the merchant''s established default (no model call, R13), the model''s own guess, or set by hand.';


--
-- Name: COLUMN transaction.inferred_fields; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.transaction.inferred_fields IS 'Which fields the member did not state and the system filled in — amount, merchant, category, account, date. The screens mark these (data-model.md); an empty array means nothing was inferred.';


--
-- Name: transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.transaction ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.transaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: translation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.translation (
    slug text NOT NULL,
    language text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT translation_language_check CHECK ((language = ANY (ARRAY['en'::text, 'ru'::text])))
);

ALTER TABLE ONLY public.translation FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE translation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.translation IS 'Language-neutral slug to display name. A category''s slug is account.name for an expense-type row (ADR 0031).';


--
-- Name: v_account; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_account WITH (security_invoker='true') AS
 SELECT a.id,
    a.type,
    a.name,
    a.currency,
    a.parent_id,
    a.active,
    a.reviewed,
    t.overdraft_limit,
    t.credit_limit,
    t.interest_rate,
    t.payment_amount,
    t.payment_day,
    t.effective_from AS term_effective_from
   FROM (public.account a
     LEFT JOIN LATERAL ( SELECT term.id,
            term.account_id,
            term.overdraft_limit,
            term.credit_limit,
            term.interest_rate,
            term.payment_amount,
            term.payment_day,
            term.effective_from,
            term.created_at
           FROM public.account_term term
          WHERE ((term.account_id = a.id) AND (term.effective_from <= CURRENT_DATE))
          ORDER BY term.effective_from DESC
         LIMIT 1) t ON (true));


--
-- Name: VIEW v_account; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_account IS 'The chart, each account with its current term (data-model.md).';


--
-- Name: v_account_balance; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_account_balance WITH (security_invoker='true') AS
 SELECT a.id AS account_id,
    a.name,
    a.type,
    a.currency,
        CASE
            WHEN (a.type = 'liability'::text) THEN (- COALESCE(sum(p.amount), (0)::numeric))
            ELSE COALESCE(sum(p.amount), (0)::numeric)
        END AS balance,
    COALESCE(t.overdraft_limit, t.credit_limit) AS limit_amount,
        CASE
            WHEN ((a.type = 'asset'::text) AND (t.overdraft_limit IS NOT NULL)) THEN ((t.overdraft_limit)::numeric + COALESCE(sum(p.amount), (0)::numeric))
            WHEN ((a.type = 'liability'::text) AND (t.credit_limit IS NOT NULL)) THEN ((t.credit_limit)::numeric + COALESCE(sum(p.amount), (0)::numeric))
            ELSE NULL::numeric
        END AS headroom
   FROM ((public.account a
     LEFT JOIN public.posting p ON ((p.account_id = a.id)))
     LEFT JOIN LATERAL ( SELECT term.id,
            term.account_id,
            term.overdraft_limit,
            term.credit_limit,
            term.interest_rate,
            term.payment_amount,
            term.payment_day,
            term.effective_from,
            term.created_at
           FROM public.account_term term
          WHERE ((term.account_id = a.id) AND (term.effective_from <= CURRENT_DATE))
          ORDER BY term.effective_from DESC
         LIMIT 1) t ON (true))
  GROUP BY a.id, a.name, a.type, a.currency, t.overdraft_limit, t.credit_limit;


--
-- Name: VIEW v_account_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_account_balance IS 'Balance, limit and headroom per account (data-model.md). Balance is always derived, never stored (R5). A liability''s raw postings accumulate negatively as debt grows; balance and headroom present the conventional positive-means-owed sign.';


--
-- Name: v_category; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_category WITH (security_invoker='true') AS
 SELECT a.id,
    a.name AS slug,
    a.parent_id,
    a.active,
    a.reviewed,
    tr.language,
    tr.display_name
   FROM (public.account a
     JOIN public.translation tr ON ((tr.slug = a.name)))
  WHERE (a.type = 'expense'::text);


--
-- Name: VIEW v_category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_category IS 'Expense accounts as categories, with display names per language (data-model.md). A category is an expense account (ADR 0031) — filter by language for one member''s reply.';


--
-- Name: v_period_spend; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_period_spend WITH (security_invoker='true') AS
 SELECT (date_trunc('month'::text, (t.date)::timestamp with time zone))::date AS period_start,
    sum(p.amount) FILTER (WHERE (a.type = 'expense'::text)) AS spend,
    sum(p.amount) FILTER (WHERE ((a.type = 'expense'::text) AND (t.confirmation_state = 'unconfirmed'::text))) AS unconfirmed_spend,
    count(*) FILTER (WHERE (a.type = 'expense'::text)) AS transaction_count
   FROM ((public.transaction t
     JOIN public.posting p ON ((p.transaction_id = t.id)))
     JOIN public.account a ON ((a.id = p.account_id)))
  WHERE (a.type = 'expense'::text)
  GROUP BY ((date_trunc('month'::text, (t.date)::timestamp with time zone))::date);


--
-- Name: VIEW v_period_spend; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_period_spend IS 'Spend by month, transfers excluded by construction (a transfer has no expense-type posting), with the unconfirmed share (data-model.md, ADR 0023).';


--
-- Name: v_transaction_detail; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_transaction_detail WITH (security_invoker='true') AS
 SELECT t.id,
    t.date,
    t.note,
    t.project_id,
    t.submitter,
    t.source,
    t.confirmation_state,
    t.confirmation_route,
    t.confirmed_by,
    t.confirmed_at,
    t.model,
    t.prompt_version,
    t.original_amount,
    t.original_currency,
    t.category_source,
    t.inferred_fields,
    m.id AS merchant_id,
    m.name AS merchant_name,
    ( SELECT posting.account_id
           FROM public.posting
          WHERE ((posting.transaction_id = t.id) AND (posting.account_id IN ( SELECT account.id
                   FROM public.account
                  WHERE (account.type = 'expense'::text))))
         LIMIT 1) AS category_account_id
   FROM (public.transaction t
     LEFT JOIN public.merchant m ON ((m.id = t.merchant_id)));


--
-- Name: VIEW v_transaction_detail; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_transaction_detail IS 'One transaction with its provenance and where its category came from (data-model.md, spec 0004''s "why this category").';


--
-- Name: v_unconfirmed; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_unconfirmed WITH (security_invoker='true') AS
 SELECT id,
    date,
    submitter,
    merchant_id,
    category_source,
    inferred_fields,
    created_at,
    (EXTRACT(epoch FROM (now() - created_at)) / (3600)::numeric) AS age_hours
   FROM public.transaction t
  WHERE (confirmation_state = 'unconfirmed'::text);


--
-- Name: VIEW v_unconfirmed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_unconfirmed IS 'The review queue (ADR 0023), with which fields were inferred rather than stated.';


--
-- Name: v_unconfirmed_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_unconfirmed_summary WITH (security_invoker='true') AS
 SELECT count(*) AS unconfirmed_count,
    max((EXTRACT(epoch FROM (now() - created_at)) / (3600)::numeric)) AS oldest_age_hours
   FROM public.transaction
  WHERE (confirmation_state = 'unconfirmed'::text);


--
-- Name: VIEW v_unconfirmed_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_unconfirmed_summary IS 'The queue''s count and oldest age (data-model.md) — the ceiling alert reads this.';


--
-- Name: account account_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT account_pkey PRIMARY KEY (id);


--
-- Name: account_term account_term_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_term
    ADD CONSTRAINT account_term_pkey PRIMARY KEY (id);


--
-- Name: agent_memory agent_memory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_memory
    ADD CONSTRAINT agent_memory_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: bootstrap_probe bootstrap_probe_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bootstrap_probe
    ADD CONSTRAINT bootstrap_probe_pkey PRIMARY KEY (id);


--
-- Name: capture capture_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capture
    ADD CONSTRAINT capture_pkey PRIMARY KEY (id);


--
-- Name: conversation conversation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation
    ADD CONSTRAINT conversation_pkey PRIMARY KEY (id);


--
-- Name: correction_request correction_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_request
    ADD CONSTRAINT correction_request_pkey PRIMARY KEY (id);


--
-- Name: file file_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.file
    ADD CONSTRAINT file_pkey PRIMARY KEY (id);


--
-- Name: file file_sha256_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.file
    ADD CONSTRAINT file_sha256_key UNIQUE (sha256);


--
-- Name: household_setting household_setting_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.household_setting
    ADD CONSTRAINT household_setting_key_key UNIQUE (key);


--
-- Name: household_setting household_setting_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.household_setting
    ADD CONSTRAINT household_setting_pkey PRIMARY KEY (id);


--
-- Name: member_channel member_channel_kind_external_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_channel
    ADD CONSTRAINT member_channel_kind_external_id_key UNIQUE (kind, external_id);


--
-- Name: member_channel member_channel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_channel
    ADD CONSTRAINT member_channel_pkey PRIMARY KEY (id);


--
-- Name: member_identity member_identity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_identity
    ADD CONSTRAINT member_identity_pkey PRIMARY KEY (id);


--
-- Name: member_identity member_identity_provider_subject_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_identity
    ADD CONSTRAINT member_identity_provider_subject_key UNIQUE (provider_subject);


--
-- Name: member member_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_pkey PRIMARY KEY (id);


--
-- Name: merchant_alias merchant_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_alias
    ADD CONSTRAINT merchant_alias_pkey PRIMARY KEY (id);


--
-- Name: merchant merchant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant
    ADD CONSTRAINT merchant_pkey PRIMARY KEY (id);


--
-- Name: posting posting_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting
    ADD CONSTRAINT posting_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: transaction transaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_pkey PRIMARY KEY (id);


--
-- Name: translation translation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translation
    ADD CONSTRAINT translation_pkey PRIMARY KEY (slug, language);


--
-- Name: audit_log_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_occurred_at_idx ON public.audit_log USING btree (occurred_at);


--
-- Name: audit_log_table_row_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_table_row_idx ON public.audit_log USING btree (table_name, row_id);


--
-- Name: capture_chat_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX capture_chat_id ON public.capture USING btree (chat_id, created_at);


--
-- Name: capture_conversation_sequence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX capture_conversation_sequence ON public.capture USING btree (conversation_id, sequence);


--
-- Name: conversation_one_open_per_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX conversation_one_open_per_kind ON public.conversation USING btree (member_id, kind) WHERE (closed_at IS NULL);


--
-- Name: merchant_alias_alias_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX merchant_alias_alias_key ON public.merchant_alias USING btree (lower(alias));


--
-- Name: account account_agent_insert_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER account_agent_insert_guard BEFORE INSERT ON public.account FOR EACH ROW EXECUTE FUNCTION public.account_agent_insert_guard();


--
-- Name: account account_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER account_audit AFTER INSERT OR DELETE OR UPDATE ON public.account FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: account_term account_term_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER account_term_audit AFTER INSERT ON public.account_term FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: account_term account_term_deny_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER account_term_deny_delete BEFORE DELETE ON public.account_term FOR EACH ROW EXECUTE FUNCTION public.deny_mutation();


--
-- Name: account_term account_term_deny_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER account_term_deny_update BEFORE UPDATE ON public.account_term FOR EACH ROW EXECUTE FUNCTION public.deny_mutation();


--
-- Name: agent_memory agent_memory_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER agent_memory_audit AFTER INSERT OR DELETE OR UPDATE ON public.agent_memory FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: audit_log audit_log_immutable_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_log_immutable_delete BEFORE DELETE ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.audit_log_deny_mutation();


--
-- Name: audit_log audit_log_immutable_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_log_immutable_update BEFORE UPDATE ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.audit_log_deny_mutation();


--
-- Name: capture capture_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_audit AFTER INSERT OR DELETE OR UPDATE ON public.capture FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: conversation conversation_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER conversation_audit AFTER INSERT OR DELETE OR UPDATE ON public.conversation FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: correction_request correction_request_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER correction_request_audit AFTER INSERT OR DELETE OR UPDATE ON public.correction_request FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: file file_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER file_audit AFTER INSERT OR DELETE OR UPDATE ON public.file FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: household_setting household_setting_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER household_setting_audit AFTER INSERT OR DELETE OR UPDATE ON public.household_setting FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: member member_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER member_audit AFTER INSERT OR DELETE OR UPDATE ON public.member FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: member_channel member_channel_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER member_channel_audit AFTER INSERT OR DELETE OR UPDATE ON public.member_channel FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: member_identity member_identity_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER member_identity_audit AFTER INSERT OR DELETE OR UPDATE ON public.member_identity FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: merchant_alias merchant_alias_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER merchant_alias_audit AFTER INSERT OR DELETE OR UPDATE ON public.merchant_alias FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: merchant merchant_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER merchant_audit AFTER INSERT OR DELETE OR UPDATE ON public.merchant FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: posting posting_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER posting_audit AFTER INSERT OR DELETE OR UPDATE ON public.posting FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: posting posting_balance_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER posting_balance_check AFTER INSERT OR DELETE OR UPDATE ON public.posting DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.posting_balance_check();


--
-- Name: posting posting_member_update_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER posting_member_update_guard BEFORE UPDATE ON public.posting FOR EACH ROW EXECUTE FUNCTION public.posting_member_update_guard();


--
-- Name: transaction transaction_agent_confirm_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER transaction_agent_confirm_guard BEFORE UPDATE ON public.transaction FOR EACH ROW EXECUTE FUNCTION public.transaction_agent_confirm_guard();


--
-- Name: transaction transaction_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER transaction_audit AFTER INSERT OR DELETE OR UPDATE ON public.transaction FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: transaction transaction_member_update_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER transaction_member_update_guard BEFORE UPDATE ON public.transaction FOR EACH ROW EXECUTE FUNCTION public.transaction_member_update_guard();


--
-- Name: account account_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT account_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.account(id);


--
-- Name: account_term account_term_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_term
    ADD CONSTRAINT account_term_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- Name: agent_memory agent_memory_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_memory
    ADD CONSTRAINT agent_memory_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.member(id);


--
-- Name: capture capture_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capture
    ADD CONSTRAINT capture_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversation(id);


--
-- Name: capture capture_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capture
    ADD CONSTRAINT capture_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.file(id);


--
-- Name: capture capture_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capture
    ADD CONSTRAINT capture_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.member(id);


--
-- Name: capture capture_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capture
    ADD CONSTRAINT capture_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES public.transaction(id);


--
-- Name: conversation conversation_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation
    ADD CONSTRAINT conversation_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.member(id);


--
-- Name: correction_request correction_request_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_request
    ADD CONSTRAINT correction_request_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.member(id);


--
-- Name: correction_request correction_request_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_request
    ADD CONSTRAINT correction_request_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES public.transaction(id);


--
-- Name: household_setting household_setting_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.household_setting
    ADD CONSTRAINT household_setting_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.member(id);


--
-- Name: member_channel member_channel_linked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_channel
    ADD CONSTRAINT member_channel_linked_by_fkey FOREIGN KEY (linked_by) REFERENCES public.member(id);


--
-- Name: member_channel member_channel_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_channel
    ADD CONSTRAINT member_channel_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.member(id);


--
-- Name: member member_default_payment_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_default_payment_account_id_fkey FOREIGN KEY (default_payment_account_id) REFERENCES public.account(id);


--
-- Name: member_identity member_identity_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_identity
    ADD CONSTRAINT member_identity_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.member(id);


--
-- Name: merchant_alias merchant_alias_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_alias
    ADD CONSTRAINT merchant_alias_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchant(id);


--
-- Name: merchant merchant_default_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant
    ADD CONSTRAINT merchant_default_category_id_fkey FOREIGN KEY (default_category_id) REFERENCES public.account(id);


--
-- Name: posting posting_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting
    ADD CONSTRAINT posting_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- Name: posting posting_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting
    ADD CONSTRAINT posting_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES public.transaction(id) ON DELETE CASCADE;


--
-- Name: transaction transaction_confirmed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_confirmed_by_fkey FOREIGN KEY (confirmed_by) REFERENCES public.member(id);


--
-- Name: transaction transaction_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchant(id);


--
-- Name: transaction transaction_submitter_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_submitter_fkey FOREIGN KEY (submitter) REFERENCES public.member(id);


--
-- Name: account; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.account ENABLE ROW LEVEL SECURITY;

--
-- Name: account account_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_admin ON public.account TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: account account_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_insert_agent ON public.account FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: account account_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_select ON public.account FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: account_term; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.account_term ENABLE ROW LEVEL SECURITY;

--
-- Name: account_term account_term_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_term_insert ON public.account_term FOR INSERT TO hh_admin WITH CHECK (true);


--
-- Name: account_term account_term_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_term_select ON public.account_term FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: agent_memory; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agent_memory ENABLE ROW LEVEL SECURITY;

--
-- Name: agent_memory agent_memory_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agent_memory_admin ON public.agent_memory TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: agent_memory agent_memory_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agent_memory_insert_agent ON public.agent_memory FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: agent_memory agent_memory_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agent_memory_select ON public.agent_memory FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_log_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_log_insert ON public.audit_log FOR INSERT TO hh_member, hh_admin, hh_agent WITH CHECK (true);


--
-- Name: audit_log audit_log_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_log_select ON public.audit_log FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: capture; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.capture ENABLE ROW LEVEL SECURITY;

--
-- Name: capture capture_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capture_admin ON public.capture TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: capture capture_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capture_agent ON public.capture TO hh_agent USING (true) WITH CHECK (true);


--
-- Name: capture capture_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capture_select_own ON public.capture FOR SELECT TO hh_member USING ((member_id = (current_setting('meowhub.actor'::text, true))::bigint));


--
-- Name: conversation; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversation ENABLE ROW LEVEL SECURITY;

--
-- Name: conversation conversation_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversation_admin ON public.conversation TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: conversation conversation_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversation_agent ON public.conversation TO hh_agent USING (true) WITH CHECK (true);


--
-- Name: conversation conversation_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversation_select_own ON public.conversation FOR SELECT TO hh_member USING ((member_id = (current_setting('meowhub.actor'::text, true))::bigint));


--
-- Name: correction_request; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.correction_request ENABLE ROW LEVEL SECURITY;

--
-- Name: correction_request correction_request_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY correction_request_admin ON public.correction_request TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: correction_request correction_request_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY correction_request_agent ON public.correction_request TO hh_agent USING (true) WITH CHECK (true);


--
-- Name: correction_request correction_request_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY correction_request_insert_own ON public.correction_request FOR INSERT TO hh_member WITH CHECK ((requested_by = (current_setting('meowhub.actor'::text, true))::bigint));


--
-- Name: correction_request correction_request_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY correction_request_select_own ON public.correction_request FOR SELECT TO hh_member USING ((requested_by = (current_setting('meowhub.actor'::text, true))::bigint));


--
-- Name: file; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.file ENABLE ROW LEVEL SECURITY;

--
-- Name: file file_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY file_admin ON public.file TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: file file_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY file_insert_agent ON public.file FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: file file_select_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY file_select_agent ON public.file FOR SELECT TO hh_agent USING (true);


--
-- Name: file file_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY file_select_member ON public.file FOR SELECT TO hh_member USING (true);


--
-- Name: household_setting; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.household_setting ENABLE ROW LEVEL SECURITY;

--
-- Name: household_setting household_setting_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY household_setting_admin ON public.household_setting TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: household_setting household_setting_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY household_setting_select ON public.household_setting FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: member; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.member ENABLE ROW LEVEL SECURITY;

--
-- Name: member_channel; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.member_channel ENABLE ROW LEVEL SECURITY;

--
-- Name: member_channel member_channel_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY member_channel_admin ON public.member_channel TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: member_channel member_channel_select_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY member_channel_select_agent ON public.member_channel FOR SELECT TO hh_agent USING (true);


--
-- Name: member_identity; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.member_identity ENABLE ROW LEVEL SECURITY;

--
-- Name: member_identity member_identity_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY member_identity_admin ON public.member_identity TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: member member_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY member_select ON public.member FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: member member_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY member_write ON public.member TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: merchant; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merchant ENABLE ROW LEVEL SECURITY;

--
-- Name: merchant merchant_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_admin ON public.merchant TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: merchant_alias; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merchant_alias ENABLE ROW LEVEL SECURITY;

--
-- Name: merchant_alias merchant_alias_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_alias_admin ON public.merchant_alias TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: merchant_alias merchant_alias_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_alias_insert_agent ON public.merchant_alias FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: merchant_alias merchant_alias_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_alias_select ON public.merchant_alias FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: merchant merchant_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_insert_agent ON public.merchant FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: merchant merchant_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_select ON public.merchant FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: merchant merchant_update_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_update_agent ON public.merchant FOR UPDATE TO hh_agent USING (true) WITH CHECK (true);


--
-- Name: posting; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.posting ENABLE ROW LEVEL SECURITY;

--
-- Name: posting posting_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY posting_admin ON public.posting TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: posting posting_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY posting_insert_agent ON public.posting FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: posting posting_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY posting_select ON public.posting FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: posting posting_update_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY posting_update_member ON public.posting FOR UPDATE TO hh_member USING (true) WITH CHECK (true);


--
-- Name: transaction; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.transaction ENABLE ROW LEVEL SECURITY;

--
-- Name: transaction transaction_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY transaction_admin ON public.transaction TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: transaction transaction_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY transaction_insert_agent ON public.transaction FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: transaction transaction_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY transaction_select ON public.transaction FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- Name: transaction transaction_update_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY transaction_update_agent ON public.transaction FOR UPDATE TO hh_agent USING (true) WITH CHECK (true);


--
-- Name: transaction transaction_update_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY transaction_update_member ON public.transaction FOR UPDATE TO hh_member USING (true) WITH CHECK (true);


--
-- Name: translation; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.translation ENABLE ROW LEVEL SECURITY;

--
-- Name: translation translation_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY translation_admin ON public.translation TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: translation translation_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY translation_insert_agent ON public.translation FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: translation translation_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY translation_select ON public.translation FOR SELECT TO hh_member, hh_admin, hh_agent USING (true);


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('20260912000001'),
    ('20260912000002'),
    ('20260912000003'),
    ('20260912000004'),
    ('20260912000005'),
    ('20260912000006'),
    ('20260912000007'),
    ('20260912000008'),
    ('20260912000009'),
    ('20260913100429'),
    ('20260913103000'),
    ('20260913120104'),
    ('20260913121500'),
    ('20260913123000'),
    ('20260913130000'),
    ('20260913140000'),
    ('20260913140500'),
    ('20260913141000'),
    ('20260913141500'),
    ('20260913142000'),
    ('20260913142500'),
    ('20260913143000'),
    ('20260913144000'),
    ('20260913145000'),
    ('20260913150000'),
    ('20260913151000');
