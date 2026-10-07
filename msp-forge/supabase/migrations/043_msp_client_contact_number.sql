-- CNC MSP FORGE | FRM-GATE-01 v1.3.0 | Client contact number 16/09/2026
-- Cassandra's back-end ask 3 (16/09/2026): the landing page now collects a contact
-- number with the company name and contact person, but the client record had no
-- column for it, so the front end has been carrying it inside notes as
-- "Contact number: +27 ...". That is readable by a consultant but cannot be
-- searched, sorted or dialled from.
--
-- This migration:
--   1. adds msp_client_account.contact_number (free text, trimmed; the front end
--      already validates the shape, and numbers arrive in several formats);
--   2. teaches msp_client_signon to read p->>'contact_number', store it on a new
--      account, fill it in on a repeat sign-on when the account has none, and
--      return it;
--   3. backfills the column from any note that still carries the interim wording.
-- notes stays as it is for anything else a consultant wants to record.

alter table msp_client_account add column if not exists contact_number text;
comment on column msp_client_account.contact_number is 'Client contact telephone number as given on the landing page (free text, trimmed). Added 16/09/2026.';

-- Backfill from the interim "Contact number: ..." note written by the landing page
-- between 16/09/2026 and this migration. The note is left in place.
update msp_client_account
   set contact_number = btrim(substring(notes from 'Contact number:\s*([^;\n]+)'))
 where contact_number is null
   and notes ~ 'Contact number:\s*\S';

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
  v_number  text := nullif(btrim(coalesce(p->>'contact_number','')), '');
  v_id uuid;
  v_existing boolean := false;
  v_start jsonb;
begin
  if v_company = '' or v_contact = '' or v_email = '' then
    raise exception 'company name, contact name, and email are required';
  end if;
  if v_number is not null and length(v_number) > 40 then
    raise exception 'contact number is too long';
  end if;

  select id into v_id
    from msp_client_account
   where lower(contact_email) = v_email
   order by created_at desc
   limit 1;

  if v_id is not null then
    v_existing := true;
    -- A repeat sign-on may bring a number the account never had.
    if v_number is not null then
      update msp_client_account
         set contact_number = v_number
       where id = v_id and contact_number is null;
    end if;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon_repeat',
            jsonb_build_object('client_account_id', v_id, 'email', v_email));
  else
    insert into msp_client_account (company_name, contact_name, contact_email, contact_number, notes)
    values (v_company, v_contact, v_email, v_number, v_notes)
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
    'contact_number', (select contact_number from msp_client_account where id = v_id),
    'account_kind', v_start->>'account_kind',
    'declined', coalesce((v_start->>'declined')::boolean, false),
    'token', v_start->>'token');
end;
$$;
revoke execute on function msp_client_signon(jsonb) from public, anon, authenticated;
comment on function msp_client_signon is 'Server side only: records a landing-page company sign-on (company, contact, email, optional contact_number, notes), approves it immediately (self-service, MD ruling 31/08/2026) and returns the assessment token. Idempotent on contact_email.';

notify pgrst, 'reload schema';
