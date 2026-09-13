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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_account; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_account (
    id bigint NOT NULL,
    email text NOT NULL,
    password_hash text NOT NULL,
    password_is_initial boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE admin_account; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.admin_account IS 'Scaffold only (spec 0001 T17). Superseded by spec 0002''s accounts/members/roles schema.';


--
-- Name: admin_account_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.admin_account ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.admin_account_id_seq
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
    CONSTRAINT audit_log_operation_check CHECK ((operation = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text])))
);


--
-- Name: TABLE audit_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_log IS 'Append-only. No application role may update or delete a row here (ADR 0008).';


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
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: admin_account admin_account_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_account
    ADD CONSTRAINT admin_account_email_key UNIQUE (email);


--
-- Name: admin_account admin_account_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_account
    ADD CONSTRAINT admin_account_pkey PRIMARY KEY (id);


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
    ('20260912000004');
