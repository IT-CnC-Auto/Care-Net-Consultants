-- CNC MSP FORGE | FRM-GATE-01 v1.2.0 | Self-service assessment access 11/09/2026
-- MD ruling (31/08/2026, restated 11/09/2026): the Medical Surveillance Plan is free
-- for every client who books medicals, and the OMP sign-off is the paid tier. The
-- consultant approval gate on client accounts therefore no longer serves a purpose,
-- and in practice it had no user interface at all: msp_grant_access is server-side
-- only and settings.html has no client-accounts tab, so every registration stalled
-- at "your registration is with a consultant for approval".
--
-- This migration removes the wait:
--   1. msp_client_start_assessment(p_email) approves the account on demand and
--      returns a live single-use assessment token, reusing an unused, unexpired
--      token when one already exists so a page refresh never mints a second one.
--   2. msp_client_signon now returns that token in the same call, so a client who
--      has just registered is handed their assessment link immediately.
--
-- Nothing in the schema changes. account_kind keeps its enum (applicant,
-- approved_client, declined); declined accounts are still refused; the token,
-- expiry and one-token-one-assessment rule from migration 009 are unchanged.

create or replace function msp_client_start_assessment(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account%rowtype;
  v_token text;
  v_grant jsonb;
begin
  select * into v_acc
    from msp_client_account
   where lower(contact_email) = lower(btrim(coalesce(p_email, '')))
   order by created_at desc
   limit 1;

  if v_acc.id is null then
    return jsonb_build_object('found', false);
  end if;

  if v_acc.account_kind = 'declined' then
    return jsonb_build_object('found', true, 'declined', true,
                              'company_name', v_acc.company_name);
  end if;

  -- Self-service approval: the account is approved the moment it asks to start.
  if v_acc.account_kind <> 'approved_client' then
    update msp_client_account
       set account_kind = 'approved_client',
           approved_by  = 'self-service',
           approved_at  = now()
     where id = v_acc.id;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_self_approved',
            jsonb_build_object('client_account_id', v_acc.id, 'company', v_acc.company_name));
  end if;

  -- Reuse a live token if one exists; otherwise mint one through the existing grant path.
  select token into v_token
    from msp_form_access
   where client_account_id = v_acc.id
     and used_by_intake is null
     and expires_at > now()
   order by created_at desc
   limit 1;

  if v_token is null then
    v_grant := msp_grant_access('approved_client', v_acc.company_name, null, v_acc.id);
    v_token := v_grant->>'token';
  end if;

  return jsonb_build_object(
    'found', true,
    'declined', false,
    'company_name', v_acc.company_name,
    'account_kind', 'approved_client',
    'sla_status', v_acc.sla_status,
    'tool_free', true,
    'token', v_token);
end;
$$;
revoke execute on function msp_client_start_assessment(text) from public, anon, authenticated;
comment on function msp_client_start_assessment is 'Server side only: approves the signed-in contact''s account on demand and returns a live single-use assessment token (reusing an unused, unexpired one). Replaces the manual consultant approval step per the MD ruling of 31/08/2026.';

create or replace function msp_client_signon(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company text := btrim(coalesce(p->>'company_name',''));
  v_contact text := btrim(coalesce(p->>'contact_name',''));
  v_email   text := lower(btrim(coalesce(p->>'contact_email','')));
  v_notes   text := nullif(btrim(coalesce(p->>'notes','')), '');
  v_id uuid;
  v_existing boolean := false;
  v_start jsonb;
begin
  if v_company = '' or v_contact = '' or v_email = '' then
    raise exception 'company name, contact name, and email are required';
  end if;

  select id into v_id
    from msp_client_account
   where lower(contact_email) = v_email
   order by created_at desc
   limit 1;

  if v_id is not null then
    v_existing := true;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon_repeat',
            jsonb_build_object('client_account_id', v_id, 'email', v_email));
  else
    insert into msp_client_account (company_name, contact_name, contact_email, notes)
    values (v_company, v_contact, v_email, v_notes)
    returning id into v_id;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon',
            jsonb_build_object('client_account_id', v_id, 'company', v_company, 'email', v_email));
  end if;

  v_start := msp_client_start_assessment(v_email);

  return jsonb_build_object(
    'status', 'received',
    'reference', v_id,
    'existing', v_existing,
    'company_name', v_start->>'company_name',
    'account_kind', v_start->>'account_kind',
    'declined', coalesce((v_start->>'declined')::boolean, false),
    'token', v_start->>'token');
end;
$$;
revoke execute on function msp_client_signon(jsonb) from public, anon, authenticated;
comment on function msp_client_signon is 'Server side only: records a landing-page company sign-on, approves it immediately (self-service, MD ruling 31/08/2026) and returns the assessment token. Idempotent on contact_email.';

notify pgrst, 'reload schema';
