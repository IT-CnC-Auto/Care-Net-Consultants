-- CNC MSP FORGE | FRM-INT-01 v1.1.0 | Transactional intake ingest
-- Phase 2 migration 006. One controlled write path for a validated intake:
-- the Vercel webhook handler calls this RPC after JSON schema validation, and
-- the synthetic end to end test calls the same function, so test and
-- production exercise identical persistence code. Executable by the service
-- role only; revoked from every client facing role.

create sequence if not exists msp_engagement_ref_seq;

create or replace function msp_next_reference()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  -- Serialise reference numbering per day so CNC-MSP-YYYY-MMDD-NNN stays gapless
  -- enough for filing while remaining collision free under concurrency.
  perform pg_advisory_xact_lock(hashtext('msp_engagement_reference'));
  select count(*) + 1 into v_n
    from msp_engagement
   where created_at::date = current_date;
  return 'CNC-MSP-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(v_n::text, 3, '0');
end;
$$;

create or replace function msp_ingest_intake(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client_id uuid;
  v_engagement_id uuid;
  v_intake_id uuid;
  v_reference text;
  v_status text;
  v_triage_reason text;
  v_job jsonb;
  v_site jsonb;
  v_exp jsonb;
  v_chem jsonb;
  v_row int := 0;
begin
  -- Defence in depth: the webhook validator runs first, but core invariants
  -- are re-asserted here so no caller can bypass them.
  if coalesce(p->>'company_registered_name', '') = '' then
    raise exception 'company_registered_name is required';
  end if;
  if coalesce(p->>'docuseal_submission_id', '') = '' then
    raise exception 'docuseal_submission_id is required';
  end if;
  if jsonb_array_length(coalesce(p->'jobs', '[]'::jsonb)) = 0 then
    raise exception 'at least one job category is required';
  end if;
  if (p::text) ~ '\d{13}' then
    raise exception 'payload rejected: contains a thirteen digit sequence resembling a South African identity number';
  end if;
  if coalesce((p->>'consent_processing')::boolean, false) is distinct from true then
    raise exception 'processing consent is required before intake persistence';
  end if;

  v_status := coalesce(p->>'validation_status', 'valid');
  v_triage_reason := p->>'triage_reason';

  insert into msp_client (registered_name, trading_name, registration_number, vat_number, head_office_address)
  values (p->>'company_registered_name',
          nullif(p->>'company_trading_name',''),
          nullif(p->>'company_registration_number',''),
          nullif(p->>'company_vat_number',''),
          nullif(p->>'company_head_office_address',''))
  returning id into v_client_id;

  v_reference := msp_next_reference();

  insert into msp_engagement (client_id, reference, status)
  values (v_client_id, v_reference, case when v_status = 'triage' then 'triage' else 'intake' end)
  returning id into v_engagement_id;

  insert into msp_intake (engagement_id, docuseal_submission_id, raw_payload, schema_version, validation_status, triage_reason)
  values (v_engagement_id, p->>'docuseal_submission_id', p, coalesce(p->>'schema_version','intake.v1'), v_status, v_triage_reason)
  returning id into v_intake_id;

  for v_site in select * from jsonb_array_elements(coalesce(p->'sites','[]'::jsonb)) loop
    insert into msp_intake_site (intake_id, site_name, site_address, activity, headcount)
    values (v_intake_id,
            coalesce(v_site->>'name','Unnamed site'),
            v_site->>'address', v_site->>'activity',
            nullif(v_site->>'headcount','')::int);
  end loop;

  for v_job in select * from jsonb_array_elements(p->'jobs') loop
    v_row := v_row + 1;
    insert into msp_intake_job_category
      (intake_id, row_no, title, headcount, duties, hazard_codes, existing_controls,
       physical_demands, sensory_cognitive_demands, statutory_requirement,
       chronic_flag, rpe_issued, rpe_fit_tested, rpe_fit_test_interval, other_ppe)
    values
      (v_intake_id, v_row,
       v_job->>'title',
       nullif(v_job->>'headcount','')::int,
       v_job->>'duties',
       case when v_job ? 'hazard_codes'
            then array(select jsonb_array_elements_text(v_job->'hazard_codes'))
            else null end,
       v_job->>'existing_controls',
       v_job->>'physical_demands',
       v_job->>'sensory_cognitive_demands',
       v_job->>'statutory_requirement',
       coalesce((v_job->>'chronic_flag')::boolean, false),
       v_job->>'rpe_issued', v_job->>'rpe_fit_tested',
       v_job->>'rpe_fit_test_interval', v_job->>'other_ppe');
  end loop;

  for v_exp in select * from jsonb_array_elements(coalesce(p->'exposures','[]'::jsonb)) loop
    insert into msp_intake_exposure (intake_id, hazard_location, measured_level, unit, stated_oel, date_measured)
    values (v_intake_id,
            coalesce(v_exp->>'hazard_location','Unspecified'),
            coalesce(v_exp->>'measured_level',''),
            v_exp->>'unit', v_exp->>'stated_oel',
            nullif(v_exp->>'date_measured','')::date);
  end loop;

  for v_chem in select * from jsonb_array_elements(coalesce(p->'chemicals','[]'::jsonb)) loop
    insert into msp_intake_chemical (intake_id, substance_name, sds_reference, task_process, frequency, quantity_per_use, controls)
    values (v_intake_id,
            coalesce(v_chem->>'substance_name','Unspecified'),
            v_chem->>'sds_reference', v_chem->>'task_process',
            v_chem->>'frequency', v_chem->>'quantity_per_use', v_chem->>'controls');
  end loop;

  -- Unbundled POPIA consent records. Processing consent is asserted above;
  -- marketing consent defaults to false and is stored either way as a record
  -- of what was and was not granted.
  insert into msp_consent (engagement_id, consent_kind, granted, wording_version, granted_at, withdrawal_contact)
  values
    (v_engagement_id, 'processing', true,
     coalesce(p->>'consent_wording_version','popia.v1'), now(),
     coalesce(p->>'information_officer_contact','Care Net Consultants Information Officer')),
    (v_engagement_id, 'marketing', coalesce((p->>'consent_marketing')::boolean, false),
     coalesce(p->>'consent_wording_version','popia.v1'), now(),
     coalesce(p->>'information_officer_contact','Care Net Consultants Information Officer')),
    (v_engagement_id, 'popia_forms_election', coalesce((p->>'popia_use_cnc_forms')::boolean, true),
     coalesce(p->>'consent_wording_version','popia.v1'), now(),
     coalesce(p->>'information_officer_contact','Care Net Consultants Information Officer'));

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_engagement_id, 'webhook', 'intake_received',
          jsonb_build_object(
            'docuseal_submission_id', p->>'docuseal_submission_id',
            'schema_version', coalesce(p->>'schema_version','intake.v1'),
            'validation_status', v_status,
            'triage_reason', v_triage_reason,
            'job_count', jsonb_array_length(p->'jobs'),
            'reference', v_reference));

  return jsonb_build_object(
    'engagement_id', v_engagement_id,
    'intake_id', v_intake_id,
    'reference', v_reference,
    'status', case when v_status = 'triage' then 'triage' else 'intake' end);
end;
$$;

-- The controlled write path is server side only.
revoke execute on function msp_ingest_intake(jsonb) from public, anon, authenticated;
revoke execute on function msp_next_reference() from public, anon, authenticated;
