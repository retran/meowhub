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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
-- Name: ledger_probe; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_probe (
    id bigint NOT NULL,
    captured_by bigint NOT NULL,
    category text,
    confirmed boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.ledger_probe FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE ledger_probe; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ledger_probe IS 'Scaffold only (spec 0002 T4). Superseded by spec 0003''s real transaction/posting tables and policies.';


--
-- Name: ledger_probe_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ledger_probe ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ledger_probe_id_seq
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
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


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
-- Name: ledger_probe ledger_probe_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_probe
    ADD CONSTRAINT ledger_probe_pkey PRIMARY KEY (id);


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
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: audit_log_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_occurred_at_idx ON public.audit_log USING btree (occurred_at);


--
-- Name: audit_log_table_row_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_table_row_idx ON public.audit_log USING btree (table_name, row_id);


--
-- Name: audit_log audit_log_immutable_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_log_immutable_delete BEFORE DELETE ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.audit_log_deny_mutation();


--
-- Name: audit_log audit_log_immutable_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_log_immutable_update BEFORE UPDATE ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.audit_log_deny_mutation();


--
-- Name: file file_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER file_audit AFTER INSERT OR DELETE OR UPDATE ON public.file FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: ledger_probe ledger_probe_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_probe_audit AFTER INSERT OR DELETE OR UPDATE ON public.ledger_probe FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: ledger_probe ledger_probe_member_update_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_probe_member_update_guard BEFORE UPDATE ON public.ledger_probe FOR EACH ROW EXECUTE FUNCTION public.ledger_probe_member_update_guard();


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
-- Name: ledger_probe ledger_probe_captured_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_probe
    ADD CONSTRAINT ledger_probe_captured_by_fkey FOREIGN KEY (captured_by) REFERENCES public.member(id);


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
-- Name: member_identity member_identity_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_identity
    ADD CONSTRAINT member_identity_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.member(id);


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
-- Name: ledger_probe; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ledger_probe ENABLE ROW LEVEL SECURITY;

--
-- Name: ledger_probe ledger_probe_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ledger_probe_admin ON public.ledger_probe TO hh_admin USING (true) WITH CHECK (true);


--
-- Name: ledger_probe ledger_probe_insert_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ledger_probe_insert_agent ON public.ledger_probe FOR INSERT TO hh_agent WITH CHECK (true);


--
-- Name: ledger_probe ledger_probe_select_agent; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ledger_probe_select_agent ON public.ledger_probe FOR SELECT TO hh_agent USING (true);


--
-- Name: ledger_probe ledger_probe_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ledger_probe_select_member ON public.ledger_probe FOR SELECT TO hh_member USING (true);


--
-- Name: ledger_probe ledger_probe_update_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ledger_probe_update_member ON public.ledger_probe FOR UPDATE TO hh_member USING (true) WITH CHECK (true);


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
    ('20260913103000');
