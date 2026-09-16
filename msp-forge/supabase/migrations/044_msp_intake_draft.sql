-- CNC MSP FORGE | FRM-DRAFT-01 v1.0.0 | Server-side assessment drafts 16/09/2026
-- Cassandra's back-end ask 4 (16/09/2026): the assessment page saves a draft in the
-- visitor's browser (cnc-journey.js), which holds up on one machine but cannot
-- follow the same emailed link to a second one. This migration gives a draft a
-- home on the server, one row per access token, so the link opens the
-- part-finished assessment anywhere and the browser copy becomes the fallback.
--
-- Rules
--   * The access token is the only key. A draft can be saved or read only while
--     msp_check_access says the token is live (unknown, used or expired tokens are
--     refused with the same reasons the assessment page already shows).
--   * One row per token; saving again replaces the payload.
--   * The payload is the form's own field map plus the repeat-block counts, the
--     section the client was on and the running answer count. The server does not
--     interpret it. Size is capped at 256 KB (a full assessment is well under 50 KB).
--   * When the token is consumed by a submission the draft is deleted by trigger,
--     so nothing lingers once the intake exists. msp_draft_purge() removes drafts
--     whose token has expired; run it from the agent schedule or by hand.
--   * POPIA: a draft holds company details, named contacts and workplace hazards,
--     never clinical results (the form forbids them). RLS is on with no policies,
--     so only the service role (the Vercel endpoints) can touch the table.

create table if not exists msp_intake_draft (
  id uuid primary key default gen_random_uuid(),
  access_id uuid not null unique references msp_form_access(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  step int not null default 1,
  filled int not null default 0,
  company text,
  saved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint msp_intake_draft_payload_size check (pg_column_size(payload) <= 262144)
);
comment on table msp_intake_draft is 'Part-finished assessment answers, one row per live access token, saved from assess.html so the same emailed link resumes on any machine. Deleted when the token is consumed. Service role only.';
alter table msp_intake_draft enable row level security;
revoke all on msp_intake_draft from public, anon, authenticated;

-- Save (upsert) a draft against a live token.
create or replace function msp_draft_save(p_token text, p_payload jsonb, p_step int default 1, p_filled int default 0, p_company text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_check jsonb;
  v_access uuid;
  v_saved timestamptz;
begin
  v_check := msp_check_access(p_token);
  if not coalesce((v_check->>'valid')::boolean, false) then
    return jsonb_build_object('saved', false, 'reason', v_check->>'reason');
  end if;
  v_access := (v_check->>'access_id')::uuid;

  insert into msp_intake_draft (access_id, payload, step, filled, company, saved_at)
  values (v_access, coalesce(p_payload, '{}'::jsonb), greatest(coalesce(p_step, 1), 1),
          greatest(coalesce(p_filled, 0), 0), nullif(btrim(coalesce(p_company, '')), ''), now())
  on conflict (access_id) do update
     set payload  = excluded.payload,
         step     = excluded.step,
         filled   = excluded.filled,
         company  = coalesce(excluded.company, msp_intake_draft.company),
         saved_at = now()
  returning saved_at into v_saved;

  return jsonb_build_object('saved', true, 'saved_at', v_saved);
end;
$$;
revoke execute on function msp_draft_save(text, jsonb, int, int, text) from public, anon, authenticated;
comment on function msp_draft_save is 'Server side only: upserts the part-finished assessment for a live access token. Refuses unknown, used or expired tokens with the msp_check_access reason.';

-- Read a draft back for a live token.
create or replace function msp_draft_get(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_check jsonb;
  d msp_intake_draft%rowtype;
begin
  v_check := msp_check_access(p_token);
  if not coalesce((v_check->>'valid')::boolean, false) then
    return jsonb_build_object('found', false, 'valid', false, 'reason', v_check->>'reason');
  end if;

  select * into d from msp_intake_draft where access_id = (v_check->>'access_id')::uuid;
  if d.id is null then
    return jsonb_build_object('found', false, 'valid', true, 'company_name', v_check->>'company_name');
  end if;

  return jsonb_build_object(
    'found', true, 'valid', true,
    'company_name', v_check->>'company_name',
    'payload', d.payload, 'step', d.step, 'filled', d.filled,
    'company', d.company, 'saved_at', d.saved_at);
end;
$$;
revoke execute on function msp_draft_get(text) from public, anon, authenticated;
comment on function msp_draft_get is 'Server side only: returns the saved draft for a live access token, or found=false.';

-- Discard a draft (the Discard button).
create or replace function msp_draft_clear(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  delete from msp_intake_draft d
   using msp_form_access f
   where f.id = d.access_id and f.token = p_token;
  get diagnostics v_n = row_count;
  return jsonb_build_object('cleared', v_n > 0);
end;
$$;
revoke execute on function msp_draft_clear(text) from public, anon, authenticated;

-- A consumed token has no draft to keep.
create or replace function msp_intake_draft_on_consume()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.used_by_intake is not null and old.used_by_intake is null then
    delete from msp_intake_draft where access_id = new.id;
  end if;
  return new;
end;
$$;
drop trigger if exists msp_form_access_consume_draft on msp_form_access;
create trigger msp_form_access_consume_draft
  after update of used_by_intake on msp_form_access
  for each row execute function msp_intake_draft_on_consume();

-- Housekeeping: drafts whose token has expired.
create or replace function msp_draft_purge()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  delete from msp_intake_draft d
   using msp_form_access f
   where f.id = d.access_id and f.expires_at < now();
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function msp_draft_purge() from public, anon, authenticated;

notify pgrst, 'reload schema';
