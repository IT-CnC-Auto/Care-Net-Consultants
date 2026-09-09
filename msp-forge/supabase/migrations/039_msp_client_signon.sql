-- CNC MSP FORGE | FRM-GATE-01 v1.1.0 | Client sign-on write path 09/09/2026
-- Defect: signon.js was the only endpoint writing with a raw PostgREST table
-- insert. msp_client_account (migration 009) has RLS enabled with SELECT and
-- UPDATE policies but NO INSERT policy, so the applicant row could never be
-- written and every company registration failed with the generic
-- "sign on could not be recorded". Every other write path in this build goes
-- through a security definer function; this brings sign-on into line.
--
-- The function also makes re-submission idempotent: a repeat sign-on for an
-- email that already has an account returns that account instead of dead-ending,
-- so a second attempt never errors.

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
  v_kind text;
begin
  if v_company = '' or v_contact = '' or v_email = '' then
    raise exception 'company name, contact name, and email are required';
  end if;

  select id, account_kind into v_id, v_kind
    from msp_client_account
   where lower(contact_email) = v_email
   order by created_at desc
   limit 1;

  if v_id is not null then
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon_repeat',
            jsonb_build_object('client_account_id', v_id, 'email', v_email));
    return jsonb_build_object('status', 'received', 'reference', v_id,
                             'account_kind', v_kind, 'existing', true);
  end if;

  insert into msp_client_account (company_name, contact_name, contact_email, notes)
  values (v_company, v_contact, v_email, v_notes)
  returning id, account_kind into v_id, v_kind;

  insert into msp_audit (actor, event_type, event_detail)
  values ('signon', 'client_signon',
          jsonb_build_object('client_account_id', v_id, 'company', v_company, 'email', v_email));

  return jsonb_build_object('status', 'received', 'reference', v_id,
                           'account_kind', v_kind, 'existing', false);
end;
$$;

-- Mirror the grant pattern of the other server-side RPCs (msp_company_lookup,
-- msp_create_quote): callable only by the service role that the Vercel
-- endpoints authenticate with, never by a browser.
revoke execute on function msp_client_signon(jsonb) from public, anon, authenticated;

comment on function msp_client_signon is 'Server side only: records a landing-page company sign-on as an applicant (account_kind defaults to applicant; a forge_admin approves in the review interface). Idempotent on contact_email. Replaces the raw table insert that RLS refused.';
