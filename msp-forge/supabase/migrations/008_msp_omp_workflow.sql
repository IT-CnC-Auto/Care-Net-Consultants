-- CNC MSP FORGE | POP-OMP-01 v1.0.0, POP-DSR-01 v1.0.0 | OMP workflow and data subject rights
-- Phase 5 migration 008. The OMP decision path, the release path behind the
-- database gate, the engagement export for data subject access, and the
-- erasure workflow that respects occupational health record retention.
-- Every function asserts the caller's role itself: the UI is never trusted.

create or replace function msp_caller_is(p_role text)
returns boolean
language sql
stable
set search_path = public
as $$
  select auth.role() = 'service_role' or msp_has_role(p_role);
$$;
comment on function msp_caller_is is 'Role gate for workflow functions: the named forge role, or the server side service context.';

-- OMP decision: approve, amend, or reject. Recorded with name, HPCSA practice
-- number, and timestamp. Release remains impossible without an approved row.
create or replace function msp_omp_decide(
  p_review_id uuid,
  p_decision text,
  p_omp_name text,
  p_omp_hpcsa_number text,
  p_amendment_notes jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng uuid;
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'only the Designated OMP may record a decision';
  end if;
  if p_decision not in ('approved','amended','rejected') then
    raise exception 'decision must be approved, amended, or rejected';
  end if;
  if coalesce(btrim(p_omp_name),'') = '' or coalesce(btrim(p_omp_hpcsa_number),'') = '' then
    raise exception 'a decision must carry the OMP name and HPCSA practice number';
  end if;

  update msp_omp_review
     set decision = p_decision,
         omp_name = p_omp_name,
         omp_hpcsa_number = p_omp_hpcsa_number,
         decided_at = now(),
         amendment_notes = p_amendment_notes
   where id = p_review_id and decision is null
   returning engagement_id into v_eng;

  if v_eng is null then
    raise exception 'review % not found or already decided', p_review_id;
  end if;

  update msp_engagement
     set status = case p_decision when 'approved' then 'approved'
                                  when 'rejected' then 'rejected'
                                  else 'omp_queue' end
   where id = v_eng;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'omp:' || p_omp_name, 'omp_decision',
          jsonb_build_object('review_id', p_review_id, 'decision', p_decision,
                             'hpcsa_number', p_omp_hpcsa_number,
                             'amendment_notes', p_amendment_notes));

  return jsonb_build_object('review_id', p_review_id, 'decision', p_decision, 'engagement_id', v_eng);
end;
$$;

-- Release: only possible against an approved review; the msp_release gate
-- trigger enforces this even if this function is bypassed.
create or replace function msp_release_pack(
  p_review_id uuid,
  p_docx_path text,
  p_pdf_path text,
  p_envelope_id text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng uuid;
  v_release uuid;
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'only forge_admin may release';
  end if;
  select engagement_id into v_eng from msp_omp_review where id = p_review_id;
  insert into msp_release (engagement_id, omp_review_id, docx_path, pdf_path, docuseal_envelope_id)
  values (v_eng, p_review_id, p_docx_path, p_pdf_path, p_envelope_id)
  returning id into v_release;
  update msp_engagement set status = 'released' where id = v_eng;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'admin', 'release',
          jsonb_build_object('release_id', v_release, 'review_id', p_review_id,
                             'docx', p_docx_path, 'pdf', p_pdf_path));
  return v_release;
end;
$$;

-- Data subject access: everything held for an engagement, one JSON document.
create or replace function msp_engagement_export(p_engagement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'only forge_admin may export';
  end if;
  select jsonb_build_object(
    'engagement', (select to_jsonb(e) from msp_engagement e where e.id = p_engagement_id),
    'client', (select to_jsonb(c) from msp_client c join msp_engagement e on e.client_id = c.id where e.id = p_engagement_id),
    'intake', (select jsonb_agg(to_jsonb(i)) from msp_intake i where i.engagement_id = p_engagement_id),
    'sites', (select jsonb_agg(to_jsonb(s)) from msp_intake_site s join msp_intake i on i.id = s.intake_id where i.engagement_id = p_engagement_id),
    'job_categories', (select jsonb_agg(to_jsonb(j)) from msp_intake_job_category j join msp_intake i on i.id = j.intake_id where i.engagement_id = p_engagement_id),
    'exposures', (select jsonb_agg(to_jsonb(x)) from msp_intake_exposure x join msp_intake i on i.id = x.intake_id where i.engagement_id = p_engagement_id),
    'chemicals', (select jsonb_agg(to_jsonb(c)) from msp_intake_chemical c join msp_intake i on i.id = c.intake_id where i.engagement_id = p_engagement_id),
    'consents', (select jsonb_agg(to_jsonb(c)) from msp_consent c where c.engagement_id = p_engagement_id),
    'drafts', (select jsonb_agg(jsonb_build_object('stage', d.stage, 'schema_version', d.schema_version, 'created_at', d.created_at, 'stage_output', d.stage_output)) from msp_draft d where d.engagement_id = p_engagement_id),
    'reviews', (select jsonb_agg(to_jsonb(r)) from msp_omp_review r where r.engagement_id = p_engagement_id),
    'documents', (select jsonb_agg(to_jsonb(d)) from msp_document d where d.engagement_id = p_engagement_id),
    'audit', (select jsonb_agg(to_jsonb(a) order by a.id) from msp_audit a where a.engagement_id = p_engagement_id),
    'exported_at', now()
  ) into v;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (p_engagement_id, 'admin', 'export', jsonb_build_object('kind', 'data_subject_access_export'));
  return v;
end;
$$;

-- Erasure workflow. Occupational health records carry long statutory
-- retention (CR-12.4, open in the confirmation register), so erasure of an
-- engagement that has a released pack is refused unless the retention
-- override is explicitly asserted with a reason. Erasure removes intake
-- content and pseudonymises the client while keeping the audit skeleton and
-- consent records as proof of processing history.
create or replace function msp_engagement_erase(
  p_engagement_id uuid,
  p_reason text,
  p_retention_override boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_released int;
  v_client uuid;
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'only forge_admin may erase';
  end if;
  if coalesce(btrim(p_reason),'') = '' then
    raise exception 'an erasure requires a stated reason';
  end if;

  select count(*) into v_released from msp_release where engagement_id = p_engagement_id;
  if v_released > 0 and not p_retention_override then
    raise exception 'erasure refused: engagement has a released pack and occupational health records carry statutory retention (CR-12.4); assert the retention override only on documented legal advice';
  end if;

  select client_id into v_client from msp_engagement where id = p_engagement_id;
  if v_client is null then
    raise exception 'engagement % not found', p_engagement_id;
  end if;

  delete from msp_intake_site      where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_job_category where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_exposure  where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_chemical  where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_file      where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  update msp_intake
     set raw_payload = jsonb_build_object('erased', true, 'erased_at', now(), 'reason', p_reason)
   where engagement_id = p_engagement_id;
  update msp_client
     set registered_name = 'ERASED ' || left(v_client::text, 8),
         trading_name = null, registration_number = null,
         vat_number = null, head_office_address = null
   where id = v_client;
  update msp_engagement set status = 'archived' where id = p_engagement_id;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (p_engagement_id, 'admin', 'erasure',
          jsonb_build_object('reason', p_reason, 'retention_override', p_retention_override));

  return jsonb_build_object('engagement_id', p_engagement_id, 'erased', true);
end;
$$;

-- The review queue view for the interface: one row per undecided draft with
-- its OMP notes surfaced.
create or replace view msp_review_queue
with (security_invoker = on) as
select r.id as review_id, e.reference, c.registered_name as client,
       e.status, r.draft_id, d.stage_output -> 'omp_notes' as omp_notes,
       d.stage_output -> 'placeholders' as placeholders,
       e.created_at
  from msp_omp_review r
  join msp_engagement e on e.id = r.engagement_id
  join msp_client c on c.id = e.client_id
  join msp_draft d on d.id = r.draft_id
 where r.decision is null;

grant execute on function msp_omp_decide(uuid, text, text, text, jsonb) to authenticated;
grant execute on function msp_release_pack(uuid, text, text, text) to authenticated;
grant execute on function msp_engagement_export(uuid) to authenticated;
grant execute on function msp_engagement_erase(uuid, text, boolean) to authenticated;
revoke execute on function msp_omp_decide(uuid, text, text, text, jsonb) from anon, public;
revoke execute on function msp_release_pack(uuid, text, text, text) from anon, public;
revoke execute on function msp_engagement_export(uuid) from anon, public;
revoke execute on function msp_engagement_erase(uuid, text, boolean) from anon, public;
