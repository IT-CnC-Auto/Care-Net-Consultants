-- CNC HSF FORGE | BI-ENG-01, BI-RPT-01, BI-OPS-01, BI-DEC-01 checks | local test harness only.
-- Proves the Bee-Inspect engine of migrations 060, 061, 063 and 064 (hsf/BUILD-CONTRACT.md
-- 16, P3, and the decisions locked in 16.8) against a replayed database: the Fail
-- rule (recommended and strict), the Issued guard (signature, cleared scope, the
-- dual gate of FICA and KYC and a current qualification, step up MFA with its
-- two windows as parameters: 10 minutes in the app and 24 hours for DocuSeal,
-- device, kernel references, voice notes, PDF), append only tables, sealed
-- evidence and legal hold, template immutability, the free digital Safety File
-- eligibility (rule A: a verified Care Net client with more than 50 verified
-- medicals; rule B: a site with more than 500; a subcontractor registered on an
-- eligible site; not eligible, awaiting and then filed), Section F filing
-- (linked, section only, no File then filed on retry, idempotent, withdrawal),
-- the risk bands with their labels and colours, the MCO package and nodes, and
-- the scheduled runs (reminders and recurrence, NCR escalation, qualification
-- expiry). Loads the fictitious demonstration seed inside the transaction.
-- Never applied to Supabase. Everything runs in one transaction that is rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/bi_engine_checks.sql

\set ON_ERROR_STOP 1
\pset pager off
\pset tuples_only on
begin;

create function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'CHECK FAILED: %', p_name;
  end if;
  raise notice 'ok   %', p_name;
end $$;

create function pg_temp.refuses(p_name text, p_sql text, p_pattern text) returns void language plpgsql as $$
declare
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    if v_msg ~* p_pattern then
      raise notice 'ok   %', p_name;
      return;
    end if;
    raise exception 'CHECK FAILED: % (refused with "%", expected /%/)', p_name, v_msg, p_pattern;
  end;
  raise exception 'CHECK FAILED: % (not refused)', p_name;
end $$;

-- A fresh signoff step up for an auth user, as the Edge Function records it.
create function pg_temp.step_up(p_auth uuid, p_minutes_ago int default 0) returns uuid language sql as $$
  select (bi_step_up_record(p_auth, jsonb_build_object('purpose', 'signoff', 'method', 'totp', 'aal', 'aal2',
            'asserted_epoch', extract(epoch from now() - make_interval(mins => p_minutes_ago)),
            'session_ref', encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'))) ->> 'step_up_id')::uuid $$;

create function pg_temp.content(p_vns int[] default '{}', p_claims jsonb default null) returns jsonb language sql as $$
  select jsonb_build_object('label', 'Assistive draft. Competent person sign off required.',
    'claims', coalesce(p_claims, jsonb_build_array(jsonb_build_object('text', 'Each Fail finding has an owner.', 'kernel_ref', 'CNC-DEMO-GEN-01'))),
    'voice_note_index', coalesce((select jsonb_agg(jsonb_build_object('vn', v)) from unnest(p_vns) v), '[]'::jsonb)) $$;

-- Draft, sign off request, step up, signature and issue, in one go.
create function pg_temp.issue_flow(p_insp uuid, p_auth uuid, p_vns int[] default '{}') returns uuid language plpgsql as $$
declare
  v_r uuid;
begin
  v_r := (bi_report_save_draft(p_auth, p_insp, pg_temp.content(p_vns), 'ai_assistive') ->> 'report_id')::uuid;
  perform bi_report_request_signoff(p_auth, v_r);
  perform bi_report_sign(p_auth, v_r, jsonb_build_object('step_up_id', pg_temp.step_up(p_auth), 'device_integrity', 'ok',
                                                         'confirm_photos', true, 'confirm_voice_notes', true));
  perform bi_report_issue(v_r, 'x/' || v_r || '/r.pdf', encode(extensions.digest(v_r::text, 'sha256'), 'hex'), 'x/' || v_r || '/r.json');
  return v_r;
end $$;

-- A fail finding with the evidence the flags ask for.
create function pg_temp.fail_finding(p_insp uuid, p_area uuid, p_photo boolean, p_ca boolean, p_vn boolean) returns uuid language plpgsql as $$
declare
  v_f uuid;
  v_i bi_inspection;
begin
  select * into v_i from bi_inspection where id = p_insp;
  insert into bi_finding (inspection_id, tenant_id, client_account_id, area_id, result, note)
  values (p_insp, v_i.tenant_id, v_i.client_account_id, p_area, 'fail', 'check') returning id into v_f;
  if p_photo then
    insert into bi_photo (inspection_id, tenant_id, client_account_id, area_id, finding_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id)
    values (p_insp, v_i.tenant_id, v_i.client_account_id, p_area, v_f, 'risk_close_up', v_i.client_account_id || '/' || p_insp || '/' || v_f || '.jpg',
            encode(extensions.digest(v_f::text, 'sha256'), 'hex'), 1000, 'image/jpeg', now(), v_i.inspector_user_id);
  end if;
  if p_ca then
    insert into bi_corrective_action (inspection_id, tenant_id, client_account_id, finding_id, description, owner_name, due_on)
    values (p_insp, v_i.tenant_id, v_i.client_account_id, v_f, 'Fix it properly', 'Owner (fictitious)', current_date + 7);
  end if;
  if p_vn then
    insert into bi_voice_note (inspection_id, tenant_id, client_account_id, area_id, finding_id, audio_path, audio_sha256, size_bytes, mime_type, duration_seconds, captured_at, inspector_user_id)
    values (p_insp, v_i.tenant_id, v_i.client_account_id, p_area, v_f, v_i.client_account_id || '/' || p_insp || '/' || v_f || '.m4a',
            encode(extensions.digest(v_f::text || 'vn', 'sha256'), 'hex'), 1000, 'audio/mp4', 10, now(), v_i.inspector_user_id);
  end if;
  return v_f;
end $$;

\ir ../../supabase/seed/bee_inspect_demo.sql

\set tenant '''b1a00000-0000-4000-8000-000000000001'''
\set company '''b1a00000-0000-4000-8000-000000000002'''
\set inspauth '''b1a00000-0000-4000-8000-000000000011'''

-- 0. The seed -------------------------------------------------------------------------------------------

select pg_temp.ok('seed: one Issued report, signed, filed into Section F on HSF-F-01',
  (select count(*) from bi_report r join bi_report_file_link l on l.report_id = r.id
     where r.status = 'issued' and l.status = 'linked' and l.element_code = 'HSF-F-01') = 1
  and (select count(*) from bi_signature) = 1);
select pg_temp.ok('seed: the File item HSF-F-01 is uploaded and carries engine_generated evidence from Bee-Inspect',
  exists (select 1 from hsf_file_item fi join hsf_element e on e.id = fi.element_id join hsf_evidence ev on ev.file_item_id = fi.id
           where e.code = 'HSF-F-01' and fi.status = 'uploaded' and ev.source = 'engine_generated'
             and ev.supplied_by = 'Bee-Inspect report signed by Thandi Mokoena (fictitious)' and ev.storage_path is null));
select pg_temp.ok('seed: the demonstration company is eligible for the free digital Safety File (rule A: a verified Care Net client with 64 verified medicals), and the link records why',
  (select eligibility_reason from bi_report_file_link) = 'care_net_client_over_50'
  and bi_free_file_eligible(:company, 'b1a00000-0000-4000-8000-000000000041') @> '{"eligible": true, "reason": "care_net_client_over_50", "client_verified": true}'
  and (bi_free_file_eligible(:company) -> 'counts' -> 'company' ->> 'volume_12m')::int = 64
  and (bi_free_file_eligible(:company) -> 'thresholds') @> '{"client_medicals_more_than": 50, "site_medicals_more_than": 500}');
select pg_temp.ok('the thresholds are parameters, not literals: 50 and 500',
  msp_env_get_int('bi.free_file.client_medicals_threshold') = 50 and msp_env_get_int('bi.free_file.site_medicals_threshold') = 500);
select pg_temp.ok('seed: the filing is audited against the File in msp_audit',
  exists (select 1 from msp_audit where event_type = 'bi_report_filed_section_f' and hsf_file_id is not null));
select pg_temp.ok('seed: the MCO package is stored (supabase_stored) and the company nodes registered locally',
  (select count(*) from bi_transfer_package where status = 'supabase_stored') = 1
  and (select count(*) from bi_mco_node where client_account_id = :company and status = 'registered_local') = 4);
select pg_temp.ok('seed: voice notes are numbered VN-1 and VN-2 by the database',
  (select array_agg(vn_number order by vn_number) from bi_voice_note) = array[1,2]);
select pg_temp.ok('seed: transcripts are versioned (2 versions for VN-1)',
  (select max(version) from bi_voice_transcript where voice_note_id = 'b1a00000-0000-4000-8000-0000000000b1') = 2);
select pg_temp.ok('seed: the risk register gives inherent 16 extreme and residual 8 medium for the edge protection risk',
  exists (select 1 from bi_risk_register where id = 'b1a00000-0000-4000-8000-0000000000c1' and inherent_score = 16 and inherent_band = 'extreme'
            and residual_score = 8 and residual_band = 'medium' and top_control = 'engineering'));

-- 1. The Fail rule ----------------------------------------------------------------------------------------

insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status)
values ('b1a00000-0000-4000-8000-0000000000f1', :tenant, :company, 'b1a00000-0000-4000-8000-000000000041',
        'b1a00000-0000-4000-8000-000000000062', 'b1a00000-0000-4000-8000-000000000021', 'Ladder check (strict)', 'in_progress');
insert into bi_inspection_area (id, inspection_id, tenant_id, client_account_id, label)
values ('b1a00000-0000-4000-8000-0000000000f2', 'b1a00000-0000-4000-8000-0000000000f1', :tenant, :company, 'Workshop');
select pg_temp.ok('the strict tenant policy is copied onto the inspection', (select voice_note_policy from bi_inspection where id = 'b1a00000-0000-4000-8000-0000000000f1') = 'strict');

select pg_temp.fail_finding('b1a00000-0000-4000-8000-0000000000f1', 'b1a00000-0000-4000-8000-0000000000f2', false, false, false) as f_bare \gset
select pg_temp.refuses('Fail rule: a Fail with no photo, no corrective action and no voice note stops the submit',
  $q$select bi_inspection_submit('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f1')$q$, 'Fail rule');
select pg_temp.ok('the violations name photo, corrective_action and voice_note',
  bi_fail_rule_violations('b1a00000-0000-4000-8000-0000000000f1') -> 0 -> 'missing' = '["photo","corrective_action","voice_note"]'::jsonb);
insert into bi_photo (inspection_id, tenant_id, client_account_id, finding_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id)
values ('b1a00000-0000-4000-8000-0000000000f1', :tenant, :company, :'f_bare', 'risk_close_up',
        :company || '/b1a00000-0000-4000-8000-0000000000f1/bare.jpg', repeat('c', 64), 100, 'image/jpeg', now(), 'b1a00000-0000-4000-8000-000000000021');
insert into bi_corrective_action (inspection_id, tenant_id, client_account_id, finding_id, description, owner_name, due_on)
values ('b1a00000-0000-4000-8000-0000000000f1', :tenant, :company, :'f_bare', 'Replace the ladder', 'Owner (fictitious)', current_date + 3);
select pg_temp.refuses('strict: a photo and a corrective action are not enough without a voice note',
  $q$update bi_inspection set status = 'submitted' where id = 'b1a00000-0000-4000-8000-0000000000f1'$q$, 'voice note \(strict policy\)');
insert into bi_voice_note (inspection_id, tenant_id, client_account_id, finding_id, audio_path, audio_sha256, size_bytes, mime_type, duration_seconds, captured_at, inspector_user_id)
values ('b1a00000-0000-4000-8000-0000000000f1', :tenant, :company, :'f_bare', :company || '/b1a00000-0000-4000-8000-0000000000f1/bare.m4a',
        repeat('d', 64), 100, 'audio/mp4', 5, now(), 'b1a00000-0000-4000-8000-000000000021');
select pg_temp.ok('with photo, corrective action and voice note the strict inspection submits',
  bi_inspection_submit('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f1') ->> 'status' = 'submitted');

update bi_tenant set voice_note_policy = 'recommended' where id = :tenant;
insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status)
values ('b1a00000-0000-4000-8000-0000000000f3', :tenant, :company, 'b1a00000-0000-4000-8000-000000000041',
        'b1a00000-0000-4000-8000-000000000065', 'b1a00000-0000-4000-8000-000000000021', 'Fire check (recommended)', 'in_progress');
insert into bi_inspection_area (id, inspection_id, tenant_id, client_account_id, label)
values ('b1a00000-0000-4000-8000-0000000000f4', 'b1a00000-0000-4000-8000-0000000000f3', :tenant, :company, 'Store');
select pg_temp.fail_finding('b1a00000-0000-4000-8000-0000000000f3', 'b1a00000-0000-4000-8000-0000000000f4', true, false, false) as f_nocap \gset
select pg_temp.refuses('recommended: a Fail with a photo but no corrective action stops the submit',
  $q$select bi_inspection_submit('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f3')$q$, 'Fail rule');
insert into bi_corrective_action (inspection_id, tenant_id, client_account_id, finding_id, description, owner_name, due_on)
values ('b1a00000-0000-4000-8000-0000000000f3', :tenant, :company, :'f_nocap', 'Service the extinguisher', 'Owner (fictitious)', current_date + 3);
select pg_temp.ok('recommended: photo and corrective action are enough (no voice note needed)',
  bi_inspection_submit('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f3') ->> 'status' = 'submitted');
update bi_tenant set voice_note_policy = 'strict' where id = :tenant;

select pg_temp.refuses('Start Inspection is closed while the company is not Active',
  $q$with b as (update bi_company set onboarding_status = 'blocked', blocked_reason = 'FICA check failed' where client_account_id = 'b1a00000-0000-4000-8000-000000000002' returning 1)
     insert into bi_inspection (tenant_id, client_account_id, site_id, template_id, inspector_user_id, title)
     select 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041',
            'b1a00000-0000-4000-8000-000000000062', 'b1a00000-0000-4000-8000-000000000021', 'x' from b$q$, 'onboarding is Active');

-- 2. The Issued guard ---------------------------------------------------------------------------------------

select pg_temp.refuses('a draft whose legal claim has no kernel reference is refused',
  $q$select bi_report_save_draft('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f1',
       pg_temp.content('{1}', '[{"text":"An uncited claim."}]'), 'ai_assistive')$q$, 'kernel reference');
select pg_temp.refuses('a claim citing a reference no released kernel holds is refused',
  $q$select bi_report_save_draft('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f1',
       pg_temp.content('{1}', '[{"text":"x","kernel_ref":"NOT-IN-KERNEL-01"}]'), 'ai_assistive')$q$, 'kernel reference');
select pg_temp.refuses('an AI draft without the label "Assistive draft. Competent person sign off required." is refused',
  $q$select bi_report_save_draft('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f1',
       pg_temp.content('{1}') - 'label', 'ai_assistive')$q$, 'bi_report_version_label');

select (bi_report_save_draft(:inspauth, 'b1a00000-0000-4000-8000-0000000000f1', pg_temp.content('{}'), 'ai_assistive') ->> 'report_id') as rid \gset
select pg_temp.ok('the draft preview counts the voice notes: 1 total, 0 accounted for',
  (select voice_notes_total = 1 and voice_notes_referenced = 0 from bi_report_version where report_id = :'rid'));
select pg_temp.refuses('strict: sign off cannot be requested while a voice note is missing from the report',
  $q$select bi_report_request_signoff('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$')$q$, '1 missing');
select pg_temp.refuses('a report is never Issued straight from Draft',
  $q$update bi_report set status = 'issued', pdf_path = 'a', pdf_sha256 = repeat('a', 64), json_path = 'b' where id = '$q$ || :'rid' || $q$'$q$, 'only from Awaiting sign off');
select pg_temp.ok('a new version that accounts for VN-1 can go to sign off',
  (bi_report_save_draft(:inspauth, 'b1a00000-0000-4000-8000-0000000000f1', pg_temp.content('{1}'), 'ai_assistive') ->> 'version')::int = 2
  and bi_report_request_signoff(:inspauth, :'rid') ->> 'status' = 'awaiting_signoff');
select pg_temp.refuses('Issued without any signature is refused (unsigned stays Awaiting sign off)',
  $q$select bi_report_issue('$q$ || :'rid' || $q$', 'p.pdf', repeat('a', 64), 'p.json')$q$, 'no competent person has signed');
select pg_temp.refuses('a step up at aal1 is not a step up',
  $q$select bi_step_up_record('b1a00000-0000-4000-8000-000000000011', '{"purpose":"signoff","method":"totp","aal":"aal1","asserted_epoch":0,"session_ref":"x"}')$q$, 'second factor');
select pg_temp.refuses('a step up verified 20 minutes ago is too old',
  $q$select pg_temp.step_up('b1a00000-0000-4000-8000-000000000011', 20)$q$, 'too long ago');
select pg_temp.refuses('signing without a step up is refused',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', '{"device_integrity":"ok","confirm_photos":true,"confirm_voice_notes":true}')$q$, 'second factor');
select pg_temp.refuses('a rooted or jailbroken device cannot sign',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', pg_temp.step_up('b1a00000-0000-4000-8000-000000000011'), 'device_integrity', 'compromised', 'confirm_photos', true, 'confirm_voice_notes', true))$q$, 'rooted or jailbroken');
select pg_temp.refuses('the signer must confirm the photos and the voice notes',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', pg_temp.step_up('b1a00000-0000-4000-8000-000000000011'), 'device_integrity', 'ok', 'confirm_photos', true))$q$, 'Confirm that you reviewed');
update bi_inspector_profile set status = 'restricted', restricted_reason = 'Check restriction' where app_user_id = 'b1a00000-0000-4000-8000-000000000021';
select pg_temp.refuses('a restricted inspector cannot sign',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', pg_temp.step_up('b1a00000-0000-4000-8000-000000000011'), 'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true))$q$, 'not cleared');
update bi_inspector_profile set status = 'cleared', restricted_reason = null, competence_scope = array['scaffolds'] where app_user_id = 'b1a00000-0000-4000-8000-000000000021';
select pg_temp.refuses('a cleared inspector whose scope does not cover ladders cannot sign a ladder report',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', pg_temp.step_up('b1a00000-0000-4000-8000-000000000011'), 'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true))$q$, 'not cleared to sign ladders');
update bi_inspector_profile set competence_scope = array['scaffolds','ladders','fire','ppe','chemicals'] where app_user_id = 'b1a00000-0000-4000-8000-000000000021';
-- The dual gate (decision section 2): FICA and KYC cleared and a qualification cleared.
select pg_temp.ok('dual gate: the seed inspector has FICA and KYC and a current qualification cleared',
  bi_signer_gate('b1a00000-0000-4000-8000-000000000021', :company, 'ladders') @> '{"ok": true, "fica_kyc_cleared": true, "qualification_cleared": true, "missing": []}');
update bi_fica_record set status = 'rejected', review_note = 'Check: document unreadable' where id = 'b1a00000-0000-4000-8000-000000000029';
select pg_temp.refuses('dual gate: an inspector whose own FICA record is not accepted cannot sign',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', pg_temp.step_up('b1a00000-0000-4000-8000-000000000011'), 'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true))$q$, 'FICA and KYC.*fica_record');
update bi_fica_record set status = 'accepted' where id = 'b1a00000-0000-4000-8000-000000000029';
update bi_inspector_qualification set status = 'pending', verified_by = null, verified_at = null where id = 'b1a00000-0000-4000-8000-000000000027';
select pg_temp.ok('dual gate: without a verified qualification in date, FICA and KYC stay cleared but the qualification does not',
  bi_signer_gate('b1a00000-0000-4000-8000-000000000021', :company, 'ladders') @> '{"ok": false, "fica_kyc_cleared": true, "qualification_cleared": false, "missing": ["current_qualification"]}');
select pg_temp.refuses('dual gate: and the inspector cannot sign',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', pg_temp.step_up('b1a00000-0000-4000-8000-000000000011'), 'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true))$q$, 'current_qualification');
update bi_inspector_qualification set status = 'verified', verified_by = 'check', verified_at = now() where id = 'b1a00000-0000-4000-8000-000000000027';
select pg_temp.ok('step up windows are parameters: 10 minutes in the app, 1 440 minutes (24 hours) for DocuSeal',
  msp_env_get_int('bi.step_up_window_minutes') = 10 and msp_env_get_int('bi.step_up_docuseal_window_minutes') = 1440
  and bi_step_up_window_minutes('in_app') = 10 and bi_step_up_window_minutes('docuseal') = 1440);
select pg_temp.step_up(:inspauth) as sid \gset
select pg_temp.ok('a cleared inspector with the scope, a fresh step up, a sound device and both confirmations signs',
  bi_report_sign(:inspauth, :'rid', jsonb_build_object('step_up_id', :'sid', 'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true)) ? 'signature_id');
select pg_temp.ok('the step up is consumed by the signature', (select consumed_at is not null from bi_step_up where id = :'sid'));
select pg_temp.refuses('a consumed step up cannot sign again',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', '$q$ || :'sid' || $q$', 'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true))$q$, 'second factor');
select pg_temp.ok('signing does not issue: the report stays Awaiting sign off until the PDF exists',
  (select status from bi_report where id = :'rid') = 'awaiting_signoff');
select pg_temp.refuses('Issued needs the PDF and JSON stored',
  $q$select bi_report_issue('$q$ || :'rid' || $q$', null, null, null)$q$, 'PDF and JSON');
update bi_inspector_profile set status = 'restricted', restricted_reason = 'Lapsed between signing and issue' where app_user_id = 'b1a00000-0000-4000-8000-000000000021';
select pg_temp.refuses('the guard checks the signer again at issue: restricted since signing means no Issued',
  $q$select bi_report_issue('$q$ || :'rid' || $q$', 'p.pdf', repeat('a', 64), 'p.json')$q$, 'not a cleared competent person');
update bi_inspector_profile set status = 'cleared', restricted_reason = null where app_user_id = 'b1a00000-0000-4000-8000-000000000021';
update bi_fica_record set status = 'rejected', review_note = 'Check: lapsed between signing and issue' where id = 'b1a00000-0000-4000-8000-000000000029';
select pg_temp.refuses('the Issued guard checks the dual gate again at issue (FICA rejected since signing means no Issued)',
  $q$select bi_report_issue('$q$ || :'rid' || $q$', 'p.pdf', repeat('a', 64), 'p.json')$q$, 'FICA and KYC and a current qualification must both be cleared');
update bi_fica_record set status = 'accepted' where id = 'b1a00000-0000-4000-8000-000000000029';
select pg_temp.ok('with a valid signature and the PDF the report is Issued and filed into Section F (HSF-F-02, linked)',
  bi_report_issue(:'rid', 'x/ladder.pdf', repeat('e', 64), 'x/ladder.json') -> 'section_f' ->> 'status' = 'linked');
select pg_temp.ok('the link names HSF-F-02', (select element_code from bi_report_file_link where report_id = :'rid') = 'HSF-F-02');
select pg_temp.refuses('an Issued report is never edited',
  $q$update bi_report set title = 'Changed' where id = '$q$ || :'rid' || $q$'$q$, 'never edited');
select pg_temp.refuses('an Issued report takes no new version',
  $q$select bi_report_save_draft('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-0000000000f1', pg_temp.content('{1}'), 'ai_assistive')$q$, 'never edited');
select pg_temp.refuses('an Issued report is never deleted',
  $q$delete from bi_report where id = '$q$ || :'rid' || $q$'$q$, 'never deleted');
select pg_temp.refuses('a new signature on an Issued report is refused',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', jsonb_build_object('step_up_id', pg_temp.step_up('b1a00000-0000-4000-8000-000000000011'), 'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true))$q$, 'Awaiting sign off');

-- 3. Section F filing -------------------------------------------------------------------------------------------

select pg_temp.ok('Section F: the ladder item is uploaded and the File compliance went up',
  (select fi.status from hsf_file_item fi join hsf_element e on e.id = fi.element_id join hsf_file f on f.id = fi.file_id
    where f.client_account_id = :company and e.code = 'HSF-F-02') = 'uploaded'
  and (select compliance_pct from hsf_file where client_account_id = :company) > 1.1);
select pg_temp.ok('Section F sync is idempotent: a second call adds no evidence',
  (bi_hsf_section_f_sync(:'rid') ->> 'already')::boolean
  and (select count(*) from hsf_evidence ev join hsf_file_item fi on fi.id = ev.file_item_id join hsf_element e on e.id = fi.element_id where e.code = 'HSF-F-02') = 1);
select pg_temp.ok('the File owner sees both reports in the Section F list',
  jsonb_array_length(bi_section_f_reports('b1a00000-0000-4000-8000-000000000013', (select id from hsf_file where client_account_id = :company))) = 2);
select pg_temp.ok('someone else gets an empty Section F list',
  jsonb_array_length(bi_section_f_reports('b1a00000-0000-4000-8000-000000000012', (select id from hsf_file where client_account_id = :company))) = 0);

-- section_only: a template mapped to a Section F element that is not on this File (asbestos, not raised).
insert into bi_template (id, code, name, category, section_f_element_code, status) values
  ('b1a00000-0000-4000-8000-0000000000f5', 'ASBESTOS-CHECK', 'Asbestos inventory walk', 'chemicals', 'HSF-F-13', 'draft');
update bi_template set status = 'published' where id = 'b1a00000-0000-4000-8000-0000000000f5';
insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status)
values ('b1a00000-0000-4000-8000-0000000000f6', :tenant, :company, 'b1a00000-0000-4000-8000-000000000041',
        'b1a00000-0000-4000-8000-0000000000f5', 'b1a00000-0000-4000-8000-000000000021', 'Asbestos walk', 'in_progress');
update bi_inspection set status = 'submitted' where id = 'b1a00000-0000-4000-8000-0000000000f6';
select (bi_report_save_draft(:inspauth, 'b1a00000-0000-4000-8000-0000000000f6', pg_temp.content('{}'), 'ai_assistive') ->> 'report_id') as rid2 \gset
select bi_report_request_signoff(:inspauth, :'rid2') ->> 'status' as rq2 \gset
-- Decision 1.5: DocuSeal signing allows a step up recorded up to 24 hours before (the signer verified in the app first).
insert into bi_step_up (id, auth_user_id, purpose, method, aal, asserted_at, session_ref, created_at) values
  ('b1a00000-0000-4000-8000-0000000000f7', :inspauth, 'signoff', 'totp', 'aal2', now() - interval '20 hours', repeat('7', 64), now() - interval '20 hours'),
  ('b1a00000-0000-4000-8000-0000000000f8', :inspauth, 'signoff', 'totp', 'aal2', now() - interval '25 hours', repeat('8', 64), now() - interval '25 hours');
select pg_temp.refuses('a step up verified 20 hours ago is too old for an in app signature (10 minutes)',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid2' || $q$', '{"step_up_id":"b1a00000-0000-4000-8000-0000000000f7","channel":"in_app","device_integrity":"ok","confirm_photos":true,"confirm_voice_notes":true}')$q$, 'second factor');
select pg_temp.refuses('a step up verified 25 hours ago is too old for DocuSeal (24 hours)',
  $q$select bi_report_sign('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid2' || $q$', '{"step_up_id":"b1a00000-0000-4000-8000-0000000000f8","channel":"docuseal","docuseal_submission_ref":"DS-CHECK-0001","device_integrity":"unknown","confirm_photos":true,"confirm_voice_notes":true}')$q$, 'second factor');
select pg_temp.ok('a step up verified 20 hours ago signs through DocuSeal (within 24 hours)',
  bi_report_sign(:inspauth, :'rid2', '{"step_up_id":"b1a00000-0000-4000-8000-0000000000f7","channel":"docuseal","docuseal_submission_ref":"DS-CHECK-0002","device_integrity":"unknown","confirm_photos":true,"confirm_voice_notes":true}') ? 'signature_id');
select pg_temp.ok('and the Issued guard accepts the DocuSeal window at issue',
  bi_report_issue(:'rid2', 'x/asbestos.pdf', repeat('f', 64), 'x/asbestos.json') ->> 'status' = 'issued');
update msp_env_parameter set value = '60' where key = 'bi.step_up_docuseal_window_minutes';
select pg_temp.ok('the DocuSeal window follows its parameter (60 minutes while set so)', bi_step_up_window_minutes('docuseal') = 60);
update msp_env_parameter set value = '1440' where key = 'bi.step_up_docuseal_window_minutes';
select pg_temp.ok('an element not on the File: the report is listed in Section F without an element (section_only)',
  (select status from bi_report_file_link where report_id = :'rid2') = 'section_only');

-- Contract 16.8: a company not eligible for the free digital Safety File. Its
-- Issued report waits as awaiting_eligibility (no evidence, no compliance
-- change) and is filed once a verified count makes it eligible (rule A).
insert into auth.users (id, email, email_confirmed_at) values ('b4a00000-0000-4000-8000-000000000013', 'nofile.contact.check@example.invalid', now());
insert into msp_client_account (id, company_name, contact_name, contact_email, auth_user_id)
values ('b4a00000-0000-4000-8000-000000000002', 'No File Yet Works (fictitious)', 'Contact', 'nofile.contact.check@example.invalid', 'b4a00000-0000-4000-8000-000000000013');
insert into bi_company (client_account_id, legal_name, onboarding_status, activated_at, activated_by)
values ('b4a00000-0000-4000-8000-000000000002', 'No File Yet Works (fictitious)', 'active', now(), 'check');
insert into bi_company_subscription (tenant_id, client_account_id, plan_code, price_cents, wallet_monthly_cents, storage_bytes)
values (:tenant, 'b4a00000-0000-4000-8000-000000000002', 'extra_company', 19900, 10000, 10737418240);
insert into bi_site (id, client_account_id, name) values ('b4a00000-0000-4000-8000-000000000041', 'b4a00000-0000-4000-8000-000000000002', 'No File Site');
insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status)
values ('b4a00000-0000-4000-8000-000000000081', :tenant, 'b4a00000-0000-4000-8000-000000000002', 'b4a00000-0000-4000-8000-000000000041',
        'b1a00000-0000-4000-8000-000000000062', 'b1a00000-0000-4000-8000-000000000021', 'Ladders at a company not yet eligible', 'in_progress');
update bi_inspection set status = 'submitted' where id = 'b4a00000-0000-4000-8000-000000000081';
select pg_temp.ok('not a verified client and no verified count: not eligible',
  bi_free_file_eligible('b4a00000-0000-4000-8000-000000000002', 'b4a00000-0000-4000-8000-000000000041') @> '{"eligible": false, "reason": "not_eligible", "client_verified": false}');
select pg_temp.issue_flow('b4a00000-0000-4000-8000-000000000081', :inspauth) as rid3 \gset
select pg_temp.ok('not eligible: the report is Issued and its link waits as awaiting_eligibility, with no evidence',
  (select status from bi_report where id = :'rid3') = 'issued'
  and (select status = 'awaiting_eligibility' and evidence_id is null and eligibility_reason = 'not_eligible' from bi_report_file_link where report_id = :'rid3'));
select pg_temp.ok('the company builds its free File',
  hsf_generate_file('b4a00000-0000-4000-8000-000000000013', '{"industry_code":"CONSTR","triggers":["T-LADDERS"],"scope":{"sites":[{"name":"No File Site"}]}}') ? 'file_id');
select id as nf_file, coalesce(compliance_pct, -1) as nf_pct_before from hsf_file where client_account_id = 'b4a00000-0000-4000-8000-000000000002' \gset
select pg_temp.ok('while it is not eligible the retry run files nothing and counts the report as still waiting',
  bi_hsf_section_f_sync_pending(10) @> '{"processed": 0}' and (bi_hsf_section_f_sync_pending(10) ->> 'awaiting_eligibility')::int >= 1);
select pg_temp.ok('a direct sync of the waiting report answers awaiting_eligibility again',
  bi_hsf_section_f_sync(:'rid3') @> '{"status": "awaiting_eligibility"}');
select pg_temp.ok('and links it to the new File''s Section F item without evidence',
  (select file_id = :'nf_file' and file_item_id is not null and evidence_id is null from bi_report_file_link where report_id = :'rid3'));
select pg_temp.ok('awaiting eligibility changes nothing in the File: no evidence, the ladder item outstanding, the compliance figure unchanged',
  not exists (select 1 from hsf_evidence ev join hsf_file_item fi on fi.id = ev.file_item_id where fi.file_id = :'nf_file')
  and (select fi.status from hsf_file_item fi join hsf_element e on e.id = fi.element_id where fi.file_id = :'nf_file' and e.code = 'HSF-F-02') = 'outstanding'
  and (select coalesce(compliance_pct, -1) from hsf_file where id = :'nf_file') = :nf_pct_before);
select pg_temp.ok('the File lists the report in Section F as awaiting eligibility',
  (select x ->> 'filing' from jsonb_array_elements(bi_section_f_reports('b4a00000-0000-4000-8000-000000000013', :'nf_file')) x) = 'awaiting_eligibility');
select pg_temp.ok('the File audit notes the waiting report once', (select count(*) from msp_audit where event_type = 'bi_report_awaiting_eligibility' and hsf_file_id = :'nf_file') = 1);

-- Rule A: the File's own Care Net client flag (052) and MORE THAN 50 verified medicals.
insert into hsf_client_verification (client_account_id, status, method, evidence_ref, requested_at, verified_by, verified_at)
values ('b4a00000-0000-4000-8000-000000000002', 'verified', 'sales_executive', 'CHECK-REGISTER-0002', now(), 'check', now());
select pg_temp.ok('verified as a Care Net client but with no verified count: still not eligible',
  bi_free_file_eligible('b4a00000-0000-4000-8000-000000000002', 'b4a00000-0000-4000-8000-000000000041') @> '{"eligible": false, "client_verified": true}');
select pg_temp.refuses('only Care Net records a verified count: the company contact''s own declaration is refused',
  $q$select bi_medicals_volume_record('b4a00000-0000-4000-8000-000000000013', '{"client_account_id":"b4a00000-0000-4000-8000-000000000002","volume_12m":400,"source":"sales_executive_verified","evidence_ref":"self declared"}')$q$, 'Only Care Net');
select pg_temp.refuses('a count needs its evidence reference',
  $q$select bi_medicals_volume_record(null, '{"client_account_id":"b4a00000-0000-4000-8000-000000000002","volume_12m":51,"source":"mco","evidence_ref":"","verified_by":"MCO feed"}')$q$, 'Record what the count rests on');
select pg_temp.refuses('a count comes from a known source only',
  $q$select bi_medicals_volume_record(null, '{"client_account_id":"b4a00000-0000-4000-8000-000000000002","volume_12m":51,"source":"self_declared","evidence_ref":"form","verified_by":"x"}')$q$, 'source must be');
select pg_temp.ok('exactly 50 verified medicals is not eligible (more than 50 is needed)',
  bi_medicals_volume_record(null, jsonb_build_object('client_account_id', 'b4a00000-0000-4000-8000-000000000002', 'volume_12m', 50, 'source', 'mco',
    'evidence_ref', 'MCO-CHECK-0050', 'verified_by', 'MCO feed (check)', 'counted_to', current_date - 1)) -> 'eligibility' @> '{"eligible": false, "reason": "not_eligible"}');
select pg_temp.ok('and the retry run still files nothing', bi_hsf_section_f_sync_pending(10) @> '{"processed": 0}');
select pg_temp.ok('51 verified medicals make the verified client eligible (rule A: care_net_client_over_50)',
  bi_medicals_volume_record(null, jsonb_build_object('client_account_id', 'b4a00000-0000-4000-8000-000000000002', 'volume_12m', 51,
    'source', 'occupational_health', 'evidence_ref', 'OH-CHECK-0051', 'verified_by', 'Occupational health register (check)'))
    -> 'eligibility' @> '{"eligible": true, "reason": "care_net_client_over_50"}');
select pg_temp.ok('every verified count is audited in bi_audit_log and points at its audit row',
  (select count(*) from bi_medicals_volume m join bi_audit_log a on a.id = m.audit_log_id and a.event = 'medicals_volume_verified' and a.object_id = m.id
    where m.client_account_id = 'b4a00000-0000-4000-8000-000000000002') = 2);
select pg_temp.refuses('verified counts are append only', $q$update bi_medicals_volume set volume_12m = 999$q$, 'append only');
select pg_temp.ok('the retry run files the waiting report once eligibility is confirmed', (bi_hsf_section_f_sync_pending(10) ->> 'processed')::int = 1);
select pg_temp.ok('filed: linked with evidence, the ladder item uploaded, the compliance figure raised, the eligibility kept (attempt 3)',
  (select status = 'linked' and evidence_id is not null and eligibility_reason = 'care_net_client_over_50' and attempts = 3 from bi_report_file_link where report_id = :'rid3')
  and (select fi.status from hsf_file_item fi join hsf_element e on e.id = fi.element_id where fi.file_id = :'nf_file' and e.code = 'HSF-F-02') = 'uploaded'
  and (select coalesce(compliance_pct, -1) from hsf_file where id = :'nf_file') > :nf_pct_before);
select pg_temp.ok('a count counted to more than 92 days before (bi.free_file.count_max_age_days) is no longer current',
  bi_free_file_eligible('b4a00000-0000-4000-8000-000000000002', null, current_date + 100) @> '{"eligible": false}'
  and msp_env_get_int('bi.free_file.count_max_age_days') = 92);

-- Rule B and the subcontractor route: a big site and a subcontractor registered on it.
insert into auth.users (id, email, email_confirmed_at) values
  ('b7a00000-0000-4000-8000-000000000013', 'principal.contact.check@example.invalid', now()),
  ('b8a00000-0000-4000-8000-000000000013', 'subcontractor.contact.check@example.invalid', now());
insert into msp_client_account (id, company_name, contact_name, contact_email, auth_user_id) values
  ('b7a00000-0000-4000-8000-000000000002', 'Big Site Principal (fictitious)', 'Contact', 'principal.contact.check@example.invalid', 'b7a00000-0000-4000-8000-000000000013'),
  ('b8a00000-0000-4000-8000-000000000002', 'Scaffold Subcontractor (fictitious)', 'Contact', 'subcontractor.contact.check@example.invalid', 'b8a00000-0000-4000-8000-000000000013');
insert into bi_site (id, client_account_id, name) values
  ('b7a00000-0000-4000-8000-000000000041', 'b7a00000-0000-4000-8000-000000000002', 'Big Site (fictitious)'),
  ('b7a00000-0000-4000-8000-000000000042', 'b7a00000-0000-4000-8000-000000000002', 'Small Depot (fictitious)'),
  ('b8a00000-0000-4000-8000-000000000041', 'b8a00000-0000-4000-8000-000000000002', 'Scaffold crew at the Big Site (fictitious)'),
  ('b8a00000-0000-4000-8000-000000000042', 'b8a00000-0000-4000-8000-000000000002', 'Scaffold yard (fictitious)');
select pg_temp.refuses('a site count must be for a site of that company',
  $q$select bi_medicals_volume_record(null, '{"client_account_id":"b7a00000-0000-4000-8000-000000000002","site_id":"b8a00000-0000-4000-8000-000000000041","volume_12m":900,"source":"mco","evidence_ref":"MCO-X","verified_by":"MCO feed"}')$q$, 'not a site of this company');
select pg_temp.ok('a site with exactly 500 verified medicals is not a big site',
  bi_medicals_volume_record(null, jsonb_build_object('client_account_id', 'b7a00000-0000-4000-8000-000000000002', 'site_id', 'b7a00000-0000-4000-8000-000000000041',
    'volume_12m', 500, 'source', 'mco', 'evidence_ref', 'MCO-SITE-0500', 'verified_by', 'MCO feed (check)', 'counted_to', current_date - 1))
    -> 'eligibility' @> '{"eligible": false}');
select pg_temp.ok('612 verified medicals at the site: eligible for that site (rule B: big_site_over_500), though the principal is not a verified client',
  bi_medicals_volume_record(null, jsonb_build_object('client_account_id', 'b7a00000-0000-4000-8000-000000000002', 'site_id', 'b7a00000-0000-4000-8000-000000000041',
    'volume_12m', 612, 'source', 'mco', 'evidence_ref', 'MCO-SITE-0612', 'verified_by', 'MCO feed (check)'))
    -> 'eligibility' @> '{"eligible": true, "reason": "big_site_over_500", "client_verified": false}');
select pg_temp.ok('rule B is for that site only: the principal''s other site and the company as a whole are not eligible',
  bi_free_file_eligible('b7a00000-0000-4000-8000-000000000002', 'b7a00000-0000-4000-8000-000000000042') @> '{"eligible": false}'
  and bi_free_file_eligible('b7a00000-0000-4000-8000-000000000002') @> '{"eligible": false}');
select pg_temp.refuses('only Care Net registers a subcontractor on a site (an inspector is refused)',
  $q$select bi_site_subcontractor_register('b1a00000-0000-4000-8000-000000000011', '{"site_id":"b7a00000-0000-4000-8000-000000000041","subcontractor_account_id":"b8a00000-0000-4000-8000-000000000002","evidence_ref":"x register"}')$q$, 'Only Care Net');
select pg_temp.ok('before registration the subcontractor is not eligible',
  bi_free_file_eligible('b8a00000-0000-4000-8000-000000000002', 'b8a00000-0000-4000-8000-000000000041') @> '{"eligible": false}');
select pg_temp.ok('Care Net registers the subcontractor on the big site, and it is eligible there (subcontractor_of_eligible_site)',
  bi_site_subcontractor_register(null, '{"site_id":"b7a00000-0000-4000-8000-000000000041","subcontractor_account_id":"b8a00000-0000-4000-8000-000000000002","subcontractor_site_id":"b8a00000-0000-4000-8000-000000000041","evidence_ref":"PRINCIPAL-CONTRACTOR-REGISTER-07"}')
    -> 'eligibility' @> '{"eligible": true, "reason": "subcontractor_of_eligible_site"}');
select pg_temp.ok('for that site only: its other site and the company as a whole are not eligible',
  bi_free_file_eligible('b8a00000-0000-4000-8000-000000000002', 'b8a00000-0000-4000-8000-000000000042') @> '{"eligible": false}'
  and bi_free_file_eligible('b8a00000-0000-4000-8000-000000000002') @> '{"eligible": false}');
select pg_temp.ok('the answer names the principal''s site, its rule and its count',
  (bi_free_file_eligible('b8a00000-0000-4000-8000-000000000002', 'b8a00000-0000-4000-8000-000000000041') -> 'counts' -> 'subcontractor') @>
    '{"principal_site_id": "b7a00000-0000-4000-8000-000000000041", "principal_reason": "big_site_over_500", "principal_site": {"volume_12m": 612}}');
select pg_temp.refuses('a subcontractor is registered once per site', $q$select bi_site_subcontractor_register(null, '{"site_id":"b7a00000-0000-4000-8000-000000000041","subcontractor_account_id":"b8a00000-0000-4000-8000-000000000002","evidence_ref":"again register"}')$q$, 'duplicate|unique');
insert into bi_company (client_account_id, legal_name, onboarding_status, activated_at, activated_by)
values ('b8a00000-0000-4000-8000-000000000002', 'Scaffold Subcontractor (fictitious)', 'active', now(), 'check');
insert into bi_company_subscription (tenant_id, client_account_id, plan_code, price_cents, wallet_monthly_cents, storage_bytes)
values (:tenant, 'b8a00000-0000-4000-8000-000000000002', 'extra_company', 19900, 10000, 10737418240);
insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status)
values ('b8a00000-0000-4000-8000-000000000081', :tenant, 'b8a00000-0000-4000-8000-000000000002', 'b8a00000-0000-4000-8000-000000000041',
        'b1a00000-0000-4000-8000-000000000061', 'b1a00000-0000-4000-8000-000000000021', 'Scaffold check at the big site', 'in_progress');
update bi_inspection set status = 'submitted' where id = 'b8a00000-0000-4000-8000-000000000081';
select pg_temp.issue_flow('b8a00000-0000-4000-8000-000000000081', :inspauth) as rid4 \gset
select pg_temp.ok('the subcontractor''s Issued report: eligible, but no File yet (no_file)',
  (select status = 'no_file' and eligibility_reason = 'subcontractor_of_eligible_site' from bi_report_file_link where report_id = :'rid4'));
select pg_temp.ok('the subcontractor builds its free File',
  hsf_generate_file('b8a00000-0000-4000-8000-000000000013', '{"industry_code":"CONSTR","triggers":["T-SCAFFOLD"],"scope":{"sites":[{"name":"Scaffold crew at the Big Site"}]}}') ? 'file_id');
select pg_temp.ok('the retry run processes it', (bi_hsf_section_f_sync_pending(10) ->> 'processed')::int = 1);
select pg_temp.ok('and files it into the subcontractor''s scaffold register HSF-F-01 (linked, with evidence)',
  (select status = 'linked' and element_code = 'HSF-F-01' and evidence_id is not null from bi_report_file_link where report_id = :'rid4'));
select pg_temp.ok('Care Net ends the registration',
  bi_site_subcontractor_end(null, (select id from bi_site_subcontractor where subcontractor_account_id = 'b8a00000-0000-4000-8000-000000000002'), 'Contract ended (check)') ->> 'ended' = 'true');
select pg_temp.ok('which ends the eligibility for later reports, while the filed report stays filed',
  bi_free_file_eligible('b8a00000-0000-4000-8000-000000000002', 'b8a00000-0000-4000-8000-000000000041') @> '{"eligible": false}'
  and (select status from bi_report_file_link where report_id = :'rid4') = 'linked');
select pg_temp.refuses('a registration is ended, never deleted', $q$delete from bi_site_subcontractor$q$, 'never deleted');

-- Withdrawal revokes the Section F evidence.
select pg_temp.refuses('only Care Net withdraws an Issued report',
  $q$select bi_report_withdraw('b1a00000-0000-4000-8000-000000000011', '$q$ || :'rid' || $q$', 'Wrong site recorded on the report')$q$, 'Only Care Net');
update auth.users set raw_app_meta_data = '{"msp_roles":["forge_admin"]}' where id = 'b1a00000-0000-4000-8000-000000000013';
select pg_temp.ok('ops (forge_admin) withdraws with a reason',
  bi_report_withdraw('b1a00000-0000-4000-8000-000000000013', :'rid', 'Wrong site recorded on the report') ->> 'status' = 'withdrawn');
update auth.users set raw_app_meta_data = null where id = 'b1a00000-0000-4000-8000-000000000013';
select pg_temp.ok('the withdrawn report''s evidence is revoked, its item is outstanding again and its link reads revoked',
  (select revoked_at is not null from hsf_evidence where id = (select evidence_id from bi_report_file_link where report_id = :'rid'))
  and (select fi.status from hsf_file_item fi join hsf_element e on e.id = fi.element_id join hsf_file f on f.id = fi.file_id
        where f.client_account_id = :company and e.code = 'HSF-F-02') = 'outstanding'
  and (select status from bi_report_file_link where report_id = :'rid') = 'revoked');

-- 4. Append only, seals, legal hold, templates, packages ----------------------------------------------------------

select pg_temp.refuses('bi_wallet_ledger is append only (update)', $q$update bi_wallet_ledger set amount_cents = 1$q$, 'append only');
select pg_temp.refuses('bi_wallet_ledger is append only (delete)', $q$delete from bi_wallet_ledger$q$, 'append only');
select pg_temp.refuses('bi_audit_log is append only', $q$delete from bi_audit_log$q$, 'append only');
select pg_temp.refuses('bi_signature is append only', $q$update bi_signature set signer_role = 'reviewer'$q$, 'append only');
select pg_temp.refuses('bi_report_version is append only', $q$update bi_report_version set content = '{}'$q$, 'append only');
select pg_temp.refuses('bi_voice_transcript is append only (a correction is a new version)', $q$update bi_voice_transcript set body = 'x'$q$, 'append only');
select pg_temp.ok('an install is recorded as attribution', bi_attribution_record('b1a00000-0000-4000-8000-000000000011', '{"event":"install","utm_source":"hsf_builder"}') ? 'id');
select pg_temp.refuses('bi_attribution is append only', $q$delete from bi_attribution$q$, 'append only');
select pg_temp.refuses('a consent decision never changes; only its withdrawal is added',
  $q$update bi_consent_record set granted = false where consent_kind = 'terms'$q$, 'only confirmed_at and withdrawn_at');
update bi_consent_record set withdrawn_at = now() where consent_kind = 'location';
select pg_temp.ok('a consent withdrawal is recorded', (select count(*) = 1 from bi_consent_record where consent_kind = 'location' and withdrawn_at is not null));
select pg_temp.refuses('and only once', $q$update bi_consent_record set withdrawn_at = now() + interval '1 day' where consent_kind = 'location'$q$, 'once each');
select pg_temp.refuses('marketing consent needs a double opt in',
  $q$insert into bi_consent_record (auth_user_id, consent_kind, granted, wording_version) values ('b1a00000-0000-4000-8000-000000000011', 'marketing', true, 'BI-MARKETING-0.1')$q$, 'double_opt_in');
select pg_temp.refuses('sealed evidence: a photo''s GPS never changes, even on a trusted path',
  $q$update bi_photo set gps_lat = 0 where id = 'b1a00000-0000-4000-8000-0000000000a2'$q$, 'sealed evidence');
select pg_temp.refuses('sealed evidence: a voice note''s audio path never changes',
  $q$update bi_voice_note set audio_path = 'b1a00000-0000-4000-8000-000000000002/b1a00000-0000-4000-8000-000000000081/other.m4a' where id = 'b1a00000-0000-4000-8000-0000000000b1'$q$, 'sealed evidence');
select pg_temp.ok('the photo seal is the SHA 256 of its evidence fields',
  (select seal_sha256 = bi_evidence_seal(storage_path, sha256, captured_at, gps_lat, gps_lng, inspector_user_id) from bi_photo where id = 'b1a00000-0000-4000-8000-0000000000a2'));
select pg_temp.refuses('a photo showing identifiable people needs a consent reference',
  $q$update bi_photo set identifiable_people = true where id = 'b1a00000-0000-4000-8000-0000000000a1'$q$, 'bi_photo_people_consent');
update bi_inspection set legal_hold = true where id = 'b1a00000-0000-4000-8000-000000000081';
select pg_temp.refuses('legal hold: evidence of the inspection cannot be deleted', $q$delete from bi_photo where id = 'b1a00000-0000-4000-8000-0000000000a1'$q$, 'Legal hold');
select pg_temp.refuses('a published template is never changed', $q$update bi_template set name = 'Changed' where code = 'LADDERS'$q$, 'never changed');
select pg_temp.refuses('a published template takes no new item',
  $q$insert into bi_template_item (template_id, ordinal, prompt) values ('b1a00000-0000-4000-8000-000000000062', 99, 'New line here')$q$, 'never changed');
update bi_template set status = 'retired' where code = 'PPE';
select pg_temp.ok('a published template can be retired', (select status from bi_template where code = 'PPE') = 'retired');
select pg_temp.refuses('mco_ingested is reserved until the MyClinicOnline endpoint exists',
  $q$update bi_transfer_package set status = 'mco_ingested'$q$, 'reserved');
select pg_temp.refuses('an MCO node cannot be linked yet', $q$update bi_mco_node set status = 'linked'$q$, 'reserved');
select pg_temp.refuses('a risk''s residual score never exceeds its inherent score',
  $q$update bi_risk set residual_likelihood = 5, residual_severity = 5 where id = 'b1a00000-0000-4000-8000-0000000000c1'$q$, 'bi_risk_residual_not_above');
select pg_temp.refuses('controls are named on the hierarchy of controls only',
  $q$update bi_risk set controls = '[{"level":"luck","description":"hope"}]' where id = 'b1a00000-0000-4000-8000-0000000000c3'$q$, 'bi_risk_controls_shape');
select pg_temp.ok('5 x 5 bands: 4 low, 5 medium, 9 medium, 10 high, 15 high, 16 extreme, 25 extreme',
  bi_risk_band(4) = 'low' and bi_risk_band(5) = 'medium' and bi_risk_band(9) = 'medium' and bi_risk_band(10) = 'high'
  and bi_risk_band(15) = 'high' and bi_risk_band(16) = 'extreme' and bi_risk_band(25) = 'extreme' and bi_risk_band(26) is null);
select pg_temp.ok('decision 1.2: the label and colour always beside the score: 4 Low green, 5 Medium amber, 9 Medium amber, 10 High orange, 15 High orange, 16 Extreme red',
  (select array_agg(n || ' ' || bi_risk_band_label(n) || ' ' || bi_risk_band_colour(bi_risk_band(n)) order by n) from unnest(array[4,5,9,10,15,16]) n)
    = array['4 Low green','5 Medium amber','9 Medium amber','10 High orange','15 High orange','16 Extreme red']);
select pg_temp.ok('bi_risk_assess returns the number and the label together (3 x 5 = 15 High orange, 4 x 4 = 16 Extreme red)',
  bi_risk_assess(3, 5) @> '{"score": 15, "band": "high", "label": "High", "colour": "orange"}'
  and bi_risk_assess(4, 4) @> '{"score": 16, "band": "extreme", "label": "Extreme", "colour": "red"}' and bi_risk_assess(0, 3) is null);
select pg_temp.ok('every cell of the 5 x 5 matrix has exactly one of the four labels, and there are no other cut points',
  (select count(*) from generate_series(1, 5) l, generate_series(1, 5) sv where bi_risk_band_label(l * sv) is null) = 0
  and (select array_agg(distinct bi_risk_band_label(n) order by bi_risk_band_label(n)) from generate_series(1, 25) n) = array['Extreme','High','Low','Medium']);
select pg_temp.ok('the risk register carries the labels and colours: inherent 16 Extreme red, residual 8 Medium amber',
  exists (select 1 from bi_risk_register where id = 'b1a00000-0000-4000-8000-0000000000c1' and inherent_band_label = 'Extreme' and inherent_band_colour = 'red'
            and residual_band_label = 'Medium' and residual_band_colour = 'amber'));

-- 5. Scheduled runs ---------------------------------------------------------------------------------------------------

select pg_temp.ok('recurrence: the monthly series of the demonstration inspection plans its next inspection',
  (bi_schedule_reminders_run(current_date) ->> 'recurring_created')::int = 1);
select pg_temp.ok('the next inspection is planned one month on',
  exists (select 1 from bi_inspection where series_id = 'b1a00000-0000-4000-8000-000000000081' and status = 'planned'
                and scheduled_for = (current_date - 1 + interval '1 month')::date));
select pg_temp.ok('a second run plans nothing more', (bi_schedule_reminders_run(current_date) ->> 'recurring_created')::int = 0);
select pg_temp.ok('the planned inspection is reminded three days ahead',
  jsonb_array_length(bi_schedule_reminders_run((current_date - 1 + interval '1 month')::date - 2) -> 'reminders') = 1);
select pg_temp.ok('and only once',
  jsonb_array_length(bi_schedule_reminders_run((current_date - 1 + interval '1 month')::date - 1) -> 'reminders') = 0);
select pg_temp.ok('and listed overdue once its day has passed',
  jsonb_array_length(bi_schedule_reminders_run((current_date - 1 + interval '1 month')::date + 1) -> 'overdue') >= 1);

select pg_temp.ok('NCR: three days after its due date the first demonstration action is overdue (level 1)',
  (select jsonb_agg(x ->> 'escalation_level') from jsonb_array_elements(bi_ncr_escalation_run(current_date + 3) -> 'escalated') x
     where x ->> 'id' = 'b1a00000-0000-4000-8000-0000000000d1') = '["1"]'::jsonb);
select pg_temp.ok('NCR: the first action now reads overdue',
  (select status from bi_corrective_action where id = 'b1a00000-0000-4000-8000-0000000000d1') = 'overdue');
select pg_temp.ok('NCR: at ten days both demonstration actions move',
  (select count(*) from jsonb_array_elements(bi_ncr_escalation_run(current_date + 10) -> 'escalated') x
    where x ->> 'id' in ('b1a00000-0000-4000-8000-0000000000d1','b1a00000-0000-4000-8000-0000000000d2')) = 2);
select pg_temp.ok('NCR: the first is escalated to the company admin (level 2), the second overdue (level 1)',
  (select escalation_level from bi_corrective_action where id = 'b1a00000-0000-4000-8000-0000000000d1') = 2
  and (select escalation_level from bi_corrective_action where id = 'b1a00000-0000-4000-8000-0000000000d2') = 1);
select pg_temp.ok('NCR: a repeat run at the same day raises nothing again', jsonb_array_length(bi_ncr_escalation_run(current_date + 10) -> 'escalated') = 0);
select pg_temp.ok('NCR: well past due both move again',
  (select count(*) from jsonb_array_elements(bi_ncr_escalation_run(current_date + 30) -> 'escalated') x
    where x ->> 'id' in ('b1a00000-0000-4000-8000-0000000000d1','b1a00000-0000-4000-8000-0000000000d2')) = 2);
select pg_temp.ok('NCR: both reach Care Net ops (level 3, escalated)',
  (select bool_and(escalation_level = 3 and status = 'escalated') from bi_corrective_action where id in ('b1a00000-0000-4000-8000-0000000000d1','b1a00000-0000-4000-8000-0000000000d2')));

update bi_inspector_qualification set expires_on = current_date + 25 where id = 'b1a00000-0000-4000-8000-000000000027';
select pg_temp.ok('qualification expiry: 25 days out sends the 30 day alert',
  (bi_qualification_expiry_run(current_date) -> 'alerts' -> 0 ->> 'threshold') = '30');
select pg_temp.ok('only once',
  jsonb_array_length(bi_qualification_expiry_run(current_date) -> 'alerts') = 0);
select pg_temp.ok('qualification expiry: 5 days out sends the 7 day alert',
  (bi_qualification_expiry_run(current_date + 20) -> 'alerts' -> 0 ->> 'threshold') = '7');
select pg_temp.ok('qualification expiry: once lapsed the qualification is expired and the cleared inspector restricted',
  (bi_qualification_expiry_run(current_date + 26) -> 'restricted') = '["b1a00000-0000-4000-8000-000000000021"]'::jsonb);
select pg_temp.ok('the inspector now reads restricted, with the reason',
  (select status from bi_inspector_profile where app_user_id = 'b1a00000-0000-4000-8000-000000000021') = 'restricted'
  and (select restricted_reason from bi_inspector_profile where app_user_id = 'b1a00000-0000-4000-8000-000000000021') like 'A qualification expired:%');
select pg_temp.refuses('clearance is refused while a qualification is expired',
  $q$select bi_inspector_set_status('b2a00000-0000-4000-8000-000000000013', 'b1a00000-0000-4000-8000-000000000021', 'cleared')$q$, 'Only Care Net|expired qualification');

do $$ begin raise notice 'bi_engine_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
