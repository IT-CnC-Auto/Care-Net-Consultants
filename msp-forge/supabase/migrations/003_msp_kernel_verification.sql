-- CNC MSP FORGE | KRN-VER-01 v1.0.1 | Triple verification workflow
-- v1.0.1: msp_verification_due view runs as security invoker so kernel RLS applies.
-- Phase 1 migration 003. The workflow is enforced in the database:
-- an instrument becomes verified only through msp_verify_instrument, which
-- asserts all three gates; a failed candidate is excluded through
-- msp_exclude_instrument, which records the register entry and the reason.

-- Gate discipline:
--   gate a: primary instrument located (the Act, Regulation, Gazette notice,
--           HPCSA booklet, SANS standard, or peer reviewed guideline itself)
--   gate b: second authoritative corroboration
--   gate c: currency check confirming not amended, repealed, or superseded,
--           with the amendment history recorded

create or replace function msp_ingest_instrument(
  p_short_name text,
  p_full_citation text,
  p_instrument_type text,
  p_gazette_reference text default null,
  p_effective_date date default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into msp_legal_instrument
    (short_name, full_citation, instrument_type, gazette_reference, effective_date,
     source_one, source_two, source_three, status)
  values
    (p_short_name, p_full_citation, p_instrument_type, p_gazette_reference, p_effective_date,
     '[CONFIRM] pending gate a', '[CONFIRM] pending gate b', '[CONFIRM] pending gate c', 'pending')
  returning id into v_id;
  return v_id;
end;
$$;
comment on function msp_ingest_instrument is 'Stage an instrument as pending. It carries CONFIRM markers until verification and can never be cited by the agent while pending.';

create or replace function msp_verify_instrument(
  p_id uuid,
  p_source_one text,
  p_source_two text,
  p_source_three text,
  p_amendment_history text,
  p_verified_by text,
  p_review_due date
) returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if coalesce(btrim(p_source_one), '') = '' or p_source_one like '[CONFIRM]%' then
    raise exception 'Gate a not satisfied: primary instrument source is required';
  end if;
  if coalesce(btrim(p_source_two), '') = '' or p_source_two like '[CONFIRM]%' then
    raise exception 'Gate b not satisfied: authoritative corroboration is required';
  end if;
  if coalesce(btrim(p_source_three), '') = '' or p_source_three like '[CONFIRM]%' then
    raise exception 'Gate c not satisfied: currency check record is required';
  end if;
  if p_review_due is null or p_review_due <= current_date then
    raise exception 'A verified instrument requires a future review due date';
  end if;

  update msp_legal_instrument
     set source_one = p_source_one,
         source_two = p_source_two,
         source_three = p_source_three,
         amendment_history = p_amendment_history,
         verified_on = current_date,
         verified_by = p_verified_by,
         review_due = p_review_due,
         status = 'verified'
   where id = p_id
     and status in ('pending','verified');

  if not found then
    raise exception 'Instrument % is not in a verifiable state', p_id;
  end if;
end;
$$;

create or replace function msp_exclude_instrument(
  p_id uuid,
  p_failed_gate text,
  p_reason text,
  p_excluded_by text
) returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_citation text;
begin
  select full_citation into v_citation from msp_legal_instrument where id = p_id;
  if v_citation is null then
    raise exception 'Instrument % not found', p_id;
  end if;

  update msp_legal_instrument set status = 'excluded' where id = p_id;

  insert into msp_kernel_exclusion (candidate_citation, failed_gate, reason, excluded_by)
  values (v_citation, p_failed_gate, p_reason, p_excluded_by);
end;
$$;
comment on function msp_exclude_instrument is 'A source that cannot pass all three gates is excluded, not padded, and logged in the exclusion register with the reason.';

-- Currency watchdog view: instruments whose review date has arrived, or which
-- carry a recorded supersession horizon, surface here for the verifier queue.
create or replace view msp_verification_due
with (security_invoker = on) as
select id, short_name, full_citation, status, verified_on, review_due,
       amendment_history
  from msp_legal_instrument
 where status = 'verified'
   and review_due <= current_date + interval '60 days';
comment on view msp_verification_due is 'Verified instruments within sixty days of their review due date. The noise regulation transition of 06/09/2026 is the founding example.';
