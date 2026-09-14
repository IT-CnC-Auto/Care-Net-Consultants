-- CNC MSP FORGE | FRM-INT-01 v1.1.1 | Gap-safe engagement reference 14/09/2026
-- Defect: msp_next_reference (migration 006) numbered a day's engagements as
-- count(today) + 1. After any deletion the count falls behind the highest number
-- in use, the next intake is assigned a reference that already exists, and
-- msp_ingest_intake fails on the unique reference (seen 14/09/2026 after a
-- test-data clear: CNC-MSP-2026-0914-003 assigned twice).
-- Fix: next number = highest existing number for the day + 1. The advisory lock
-- still serialises concurrent intakes so two submissions never share a number.

create or replace function msp_next_reference()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text := 'CNC-MSP-' || to_char(current_date, 'YYYY-MMDD') || '-';
  v_n int;
begin
  perform pg_advisory_xact_lock(hashtext('msp_engagement_reference'));
  select coalesce(max(substring(reference from '(\d{3})$')::int), 0) + 1 into v_n
    from msp_engagement
   where reference like v_prefix || '%';
  return v_prefix || lpad(v_n::text, 3, '0');
end;
$$;
revoke execute on function msp_next_reference() from public, anon, authenticated;
comment on function msp_next_reference is 'CNC-MSP-YYYY-MMDD-NNN. NNN = highest existing number for the day + 1 (gap-safe; count+1 collided after a test-data deletion on 14/09/2026). Advisory lock serialises concurrent intakes.';
