-- CNC HSF FORGE | BI-SEED-01 v1.0.0 | Bee-Inspect demonstration tenant (FICTITIOUS) 26/09/2026
--
-- NOT A MIGRATION. NEVER APPLIED TO THE LIVE PROJECT. For the local replay and,
-- on the Director's word only, a staging project (prompt section 9: "Seed
-- staging demo tenant: Rietvlei Civils and Building (fictitious)").
--
-- Everything here is fictitious: the company, its people, sites, equipment,
-- registration and qualification numbers, email addresses (example.invalid,
-- which can never deliver), photos and voice notes (paths only, no files), and
-- the demonstration kernel chunks (which are NOT legal text). Every name carries
-- "(fictitious)" or DEMO so it can never be mistaken for a real record.
--
-- Needs migrations 001 to 063. Run it in one transaction:
--   psql --single-transaction -v ON_ERROR_STOP=1 -f supabase/seed/bee_inspect_demo.sql
-- It is idempotent: fixed ids with "on conflict do nothing", and the flow in
-- step 9 runs only while the demonstration report does not exist yet.
--
-- On a real Supabase project the three auth.users rows are better created by
-- the Auth admin API (the ids below must then be used); the direct insert here
-- serves the local stub.
--
-- What it builds (hsf/BEE-INSPECT-BUILD-PROMPT.md section 9 and the P3 brief):
--   tenant Rietvlei Civils and Building (strict voice note policy), its File
--   company, a base line, a cleared inspector, an assistant and a company
--   admin (the File contact), a site with departments, buildings and rooms,
--   equipment, seven Care Net library templates mapped to Section F registers
--   (scaffolds, ladders, lifting, electrical, fire, PPE, chemicals), a
--   demonstration kernel, the company's free File, one inspection with
--   findings, photos, voice notes, risks and corrective actions, a signed and
--   Issued report filed into Section F, and a wallet with ledger entries.

-- 1. People (fictitious) ----------------------------------------------------------------------

insert into auth.users (id, email, email_confirmed_at) values
  ('b1a00000-0000-4000-8000-000000000011', 'thandi.inspector.demo@example.invalid', now()),
  ('b1a00000-0000-4000-8000-000000000012', 'pieter.assistant.demo@example.invalid', now()),
  ('b1a00000-0000-4000-8000-000000000013', 'naledi.admin.demo@example.invalid', now())
on conflict (id) do nothing;

-- 2. The File company and the tenant ------------------------------------------------------------

insert into msp_client_account (id, company_name, contact_name, contact_email, account_kind, notes, auth_user_id)
values ('b1a00000-0000-4000-8000-000000000002', 'Rietvlei Civils and Building (Pty) Ltd (fictitious)', 'Naledi Dlamini (fictitious)',
        'naledi.admin.demo@example.invalid', 'applicant', 'FICTITIOUS Bee-Inspect demonstration company (supabase/seed/bee_inspect_demo.sql).',
        'b1a00000-0000-4000-8000-000000000013')
on conflict (id) do nothing;

insert into bi_tenant (id, name, voice_note_policy)
values ('b1a00000-0000-4000-8000-000000000001', 'Rietvlei Civils and Building (fictitious demonstration tenant)', 'strict')
on conflict (id) do nothing;

insert into bi_company (client_account_id, legal_name, trading_name, registration_number, cipc_status, s16_1_contact, s16_2_contact,
                        popia_contact, prefilled_from_file, onboarding_status, activated_at, activated_by)
values ('b1a00000-0000-4000-8000-000000000002', 'Rietvlei Civils and Building (Pty) Ltd (fictitious)', 'Rietvlei Civils',
        'DEMO/0000/000000/07', 'in_business', 'Sipho Nkosi, Managing Director (fictitious)', 'Naledi Dlamini, SHE Manager (fictitious)',
        'Naledi Dlamini (fictitious)', true, 'active', now(), 'seed')
on conflict (client_account_id) do nothing;

insert into bi_company_subscription (id, tenant_id, client_account_id, plan_code, status, price_cents, wallet_monthly_cents, storage_bytes,
                                     source, external_ref, current_period_start, current_period_end)
values ('b1a00000-0000-4000-8000-000000000031', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002',
        'base', 'active', 29900, 15000, 10737418240, 'manual', 'DEMO-SUB-001',
        date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month')::date)
on conflict (id) do nothing;

insert into bi_app_user (id, auth_user_id, tenant_id, display_name, email, mobile_e164, mobile_verified_at, mfa_enrolled_at) values
  ('b1a00000-0000-4000-8000-000000000021', 'b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000001',
   'Thandi Mokoena (fictitious)', 'thandi.inspector.demo@example.invalid', '+27000000011', now(), now()),
  ('b1a00000-0000-4000-8000-000000000022', 'b1a00000-0000-4000-8000-000000000012', 'b1a00000-0000-4000-8000-000000000001',
   'Pieter van Wyk (fictitious)', 'pieter.assistant.demo@example.invalid', null, null, null),
  ('b1a00000-0000-4000-8000-000000000023', 'b1a00000-0000-4000-8000-000000000013', 'b1a00000-0000-4000-8000-000000000001',
   'Naledi Dlamini (fictitious)', 'naledi.admin.demo@example.invalid', null, null, now())
on conflict (id) do nothing;

insert into bi_role_assignment (id, app_user_id, tenant_id, client_account_id, role, granted_by) values
  ('b1a00000-0000-4000-8000-000000000024', 'b1a00000-0000-4000-8000-000000000021', 'b1a00000-0000-4000-8000-000000000001', null, 'inspector', 'seed'),
  ('b1a00000-0000-4000-8000-000000000025', 'b1a00000-0000-4000-8000-000000000022', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'assistant', 'seed'),
  ('b1a00000-0000-4000-8000-000000000026', 'b1a00000-0000-4000-8000-000000000023', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'company_admin', 'seed')
on conflict (id) do nothing;

insert into bi_inspector_profile (app_user_id, status, id_document_kind, id_last4, kyc_vendor_ref, liveness_passed_at, competence_scope,
                                  declarations_accepted_at, cleared_by, cleared_at)
values ('b1a00000-0000-4000-8000-000000000021', 'cleared', 'sa_id', '0000', 'DEMO-KYC-0001', now(),
        array['scaffolds','ladders','lifting','electrical','fire','ppe','chemicals','construction','general'], now(), 'seed', now())
on conflict (app_user_id) do nothing;
insert into bi_inspector_profile (app_user_id, status) values ('b1a00000-0000-4000-8000-000000000022', 'assistant_only')
on conflict (app_user_id) do nothing;

insert into bi_inspector_qualification (id, app_user_id, qual_type, issuer, number, issued_on, expires_on, document_path, status, verified_by, verified_at)
values ('b1a00000-0000-4000-8000-000000000027', 'b1a00000-0000-4000-8000-000000000021', 'Construction Health and Safety Manager (fictitious)',
        'SACPCMP (demonstration record)', 'DEMO-CHSM-0001', current_date - 400, current_date + 330,
        'b1a00000-0000-4000-8000-000000000002/qualifications/demo-chsm.pdf', 'verified', 'seed', now())
on conflict (id) do nothing;

insert into bi_fica_record (id, subject_kind, client_account_id, document_kind, document_path, status, reviewed_by, reviewed_at) values
  ('b1a00000-0000-4000-8000-000000000028', 'company', 'b1a00000-0000-4000-8000-000000000002', 'cipc_registration',
   'b1a00000-0000-4000-8000-000000000002/fica/demo-cipc.pdf', 'accepted', 'seed', now())
on conflict (id) do nothing;
insert into bi_fica_record (id, subject_kind, app_user_id, document_kind, document_path, status, reviewed_by, reviewed_at) values
  ('b1a00000-0000-4000-8000-000000000029', 'inspector', 'b1a00000-0000-4000-8000-000000000021', 'id_document',
   'inspectors/b1a00000-0000-4000-8000-000000000021/demo-id.pdf', 'accepted', 'seed', now())
on conflict (id) do nothing;

insert into bi_consent_record (id, auth_user_id, client_account_id, consent_kind, granted, wording_version) values
  ('b1a00000-0000-4000-8000-00000000002a', 'b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000002', 'terms', true, 'BI-TERMS-0.1'),
  ('b1a00000-0000-4000-8000-00000000002b', 'b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000002', 'location', true, 'BI-LOCATION-0.1'),
  ('b1a00000-0000-4000-8000-00000000002c', 'b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000002', 'voice_recording', true, 'BI-VOICE-0.1')
on conflict (id) do nothing;

-- 3. Sites tree (fictitious) --------------------------------------------------------------------

insert into bi_site (id, client_account_id, name, address) values
  ('b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000002', 'Rietvlei Yard (fictitious)', '1 Demonstration Road, Pretoria East (fictitious)')
on conflict (id) do nothing;
insert into bi_department (id, client_account_id, site_id, department_code, name) values
  ('b1a00000-0000-4000-8000-000000000042', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'OPS', 'Site operations'),
  ('b1a00000-0000-4000-8000-000000000043', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'FAC', 'Stores and yard')
on conflict (id) do nothing;
insert into bi_building (id, client_account_id, site_id, department_id, name, kind) values
  ('b1a00000-0000-4000-8000-000000000044', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000042', 'Workshop block', 'building'),
  ('b1a00000-0000-4000-8000-000000000045', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000043', 'Yard zone B', 'zone')
on conflict (id) do nothing;
insert into bi_room (id, client_account_id, site_id, building_id, name, kind) values
  ('b1a00000-0000-4000-8000-000000000046', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000044', 'Workshop floor', 'room'),
  ('b1a00000-0000-4000-8000-000000000047', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000044', 'Chemical store', 'room'),
  ('b1a00000-0000-4000-8000-000000000048', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000045', 'Scaffold laydown area', 'area')
on conflict (id) do nothing;

insert into bi_equipment (id, client_account_id, site_id, tag_code, kind, description, serial_number) values
  ('b1a00000-0000-4000-8000-000000000051', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'DEMO-SCAF-014', 'Tube and clamp scaffold', 'Scaffold bay 14, yard zone B (fictitious)', null),
  ('b1a00000-0000-4000-8000-000000000052', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'DEMO-LAD-003', 'Aluminium extension ladder', 'Workshop ladder 3 (fictitious)', 'DEMO-SN-LAD-3'),
  ('b1a00000-0000-4000-8000-000000000053', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'DEMO-FE-021', 'Dry chemical powder fire extinguisher', 'Chemical store door (fictitious)', 'DEMO-SN-FE-21'),
  ('b1a00000-0000-4000-8000-000000000054', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'DEMO-CB-002', 'Chain block', 'Workshop gantry (fictitious)', 'DEMO-SN-CB-2')
on conflict (id) do nothing;

-- 4. Templates mapped to Section F registers --------------------------------------------------------

insert into bi_template (id, tenant_id, code, version, name, category, section_f_element_code, description, status) values
  ('b1a00000-0000-4000-8000-000000000061', null, 'SCAFFOLDS', 1, 'Scaffold inspection', 'scaffolds', 'HSF-F-01', 'Demonstration template. Files into the scaffold register.', 'draft'),
  ('b1a00000-0000-4000-8000-000000000062', null, 'LADDERS', 1, 'Ladder inspection', 'ladders', 'HSF-F-02', 'Demonstration template. Files into the ladder register.', 'draft'),
  ('b1a00000-0000-4000-8000-000000000063', null, 'LIFTING', 1, 'Lifting machines and tackle inspection', 'lifting', 'HSF-F-03', 'Demonstration template. Files into the lifting register.', 'draft'),
  ('b1a00000-0000-4000-8000-000000000064', null, 'ELECTRICAL', 1, 'Portable electrical equipment inspection', 'electrical', 'HSF-F-04', 'Demonstration template. Files into the portable electrical register.', 'draft'),
  ('b1a00000-0000-4000-8000-000000000065', null, 'FIRE', 1, 'Fire equipment inspection', 'fire', 'HSF-F-06', 'Demonstration template. Files into the fire equipment register.', 'draft'),
  ('b1a00000-0000-4000-8000-000000000066', null, 'PPE', 1, 'Personal protective equipment inspection', 'ppe', 'HSF-F-11', 'Demonstration template. Files into the PPE register.', 'draft'),
  ('b1a00000-0000-4000-8000-000000000067', null, 'CHEMICALS', 1, 'Hazardous chemical store inspection', 'chemicals', 'HSF-F-12', 'Demonstration template. Files into the hazardous chemical agent register.', 'draft')
on conflict (id) do nothing;

insert into bi_template_item (template_id, ordinal, section_label, prompt, kernel_ref)
select t.id, i.ordinal, i.section_label, i.prompt, i.kernel_ref
  from bi_template t
  join (values
    ('SCAFFOLDS', 1, 'Foundation', 'Scaffold stands on sound base plates and sole boards', 'CNC-DEMO-SCAFF-01'),
    ('SCAFFOLDS', 2, 'Platforms', 'Guard rails, mid rails and toe boards are in place on every working platform', 'CNC-DEMO-SCAFF-01'),
    ('SCAFFOLDS', 3, 'Tagging', 'The scaffold tag shows a current inspection', 'CNC-DEMO-SCAFF-02'),
    ('SCAFFOLDS', 4, 'Records', 'The scaffold inspection register is signed by the competent person', 'CNC-DEMO-SCAFF-02'),
    ('SCAFFOLDS', 5, 'Access', 'The access ladder is secured and extends past the platform', null),
    ('SCAFFOLDS', 6, 'Surroundings', 'The scaffold is clear of overhead power lines', null),
    ('LADDERS', 1, 'Condition', 'Stiles and rungs are free of damage', null),
    ('LADDERS', 2, 'Feet', 'Non slip feet are present and sound', null),
    ('LADDERS', 3, 'Records', 'The ladder is on the ladder register with a current inspection', null),
    ('LIFTING', 1, 'Marking', 'The safe working load is marked on the machine and the tackle', null),
    ('LIFTING', 2, 'Records', 'A current load test and inspection are on record', null),
    ('LIFTING', 3, 'Condition', 'Hooks carry a working safety catch', null),
    ('ELECTRICAL', 1, 'Leads', 'Leads and plugs are undamaged', null),
    ('ELECTRICAL', 2, 'Protection', 'Equipment is used through an earth leakage device', null),
    ('ELECTRICAL', 3, 'Records', 'The item is on the portable electrical register with a current inspection', null),
    ('FIRE', 1, 'Access', 'Fire equipment is visible, signed and unobstructed', null),
    ('FIRE', 2, 'Service', 'The service tag is current', null),
    ('FIRE', 3, 'Condition', 'The pressure gauge reads in the green and the seal is intact', null),
    ('PPE', 1, 'Issue', 'PPE issued matches the risk assessment for the task', null),
    ('PPE', 2, 'Condition', 'PPE in use is in good condition', null),
    ('PPE', 3, 'Records', 'The PPE issue register is signed by each worker', null),
    ('CHEMICALS', 1, 'Register', 'Every chemical in the store is on the hazardous chemical agent register', null),
    ('CHEMICALS', 2, 'Information', 'A current safety data sheet is available for every chemical', null),
    ('CHEMICALS', 3, 'Storage', 'Incompatible chemicals are stored apart with spill containment', null)
  ) as i(code, ordinal, section_label, prompt, kernel_ref) on i.code = t.code
 where t.tenant_id is null and t.version = 1 and t.id::text like 'b1a00000-%' and t.status = 'draft'
on conflict (template_id, ordinal) do nothing;

update bi_template set status = 'published' where id::text like 'b1a00000-0000-4000-8000-00000000006%' and status = 'draft';

-- 5. Demonstration kernel (NOT legal text) -------------------------------------------------------------

insert into bi_kernel_version (id, semver, source, status, released_at, notes)
values ('b1a00000-0000-4000-8000-000000000071', 'DEMO-0.1', 'DEMONSTRATION ONLY: {{kernel_source}} not supplied', 'released', now(),
        'Fictitious chunks so the demonstration report can show kernel references. Never cite in a real report.')
on conflict (id) do nothing;
insert into bi_kernel_doc (id, kernel_version_id, code, title, source_kind)
values ('b1a00000-0000-4000-8000-000000000072', 'b1a00000-0000-4000-8000-000000000071', 'CNC-METHOD-DEMO',
        'Care Net inspection method (demonstration, not legal text)', 'cnc_methodology')
on conflict (id) do nothing;
insert into bi_kernel_chunk (id, doc_id, ordinal, ref, content, token_count) values
  ('b1a00000-0000-4000-8000-000000000073', 'b1a00000-0000-4000-8000-000000000072', 1, 'CNC-DEMO-SCAFF-01',
   'DEMONSTRATION CHUNK (fictitious, not legal text): a working platform is protected on every open side before it is used.', 24),
  ('b1a00000-0000-4000-8000-000000000074', 'b1a00000-0000-4000-8000-000000000072', 2, 'CNC-DEMO-SCAFF-02',
   'DEMONSTRATION CHUNK (fictitious, not legal text): a scaffold is inspected and the inspection recorded before use and at the interval the competent person sets.', 28),
  ('b1a00000-0000-4000-8000-000000000075', 'b1a00000-0000-4000-8000-000000000072', 3, 'CNC-DEMO-GEN-01',
   'DEMONSTRATION CHUNK (fictitious, not legal text): every Fail finding has an owner, a due date and closure evidence.', 22)
on conflict (id) do nothing;

-- 6 to 10. The company's File, the inspection, the report, the wallet ---------------------------------------

do $seed$
declare
  k_tenant constant uuid := 'b1a00000-0000-4000-8000-000000000001';
  k_company constant uuid := 'b1a00000-0000-4000-8000-000000000002';
  k_insp_auth constant uuid := 'b1a00000-0000-4000-8000-000000000011';
  k_admin_auth constant uuid := 'b1a00000-0000-4000-8000-000000000013';
  k_inspector constant uuid := 'b1a00000-0000-4000-8000-000000000021';
  k_assistant constant uuid := 'b1a00000-0000-4000-8000-000000000022';
  k_insp constant uuid := 'b1a00000-0000-4000-8000-000000000081';
  v_report jsonb;
  v_step jsonb;
  v_rid uuid;
  v_wallet uuid;
  v_lot bigint;
  v_ue uuid;
  t_item record;
  v_captured timestamptz := date_trunc('day', now()) - interval '1 day' + interval '9 hours';
begin
  if exists (select 1 from bi_report where inspection_id = k_insp) then
    raise notice 'bee_inspect_demo: the demonstration report exists; nothing more to do';
    return;
  end if;

  -- 6. The company's free File (Construction), if it has none yet.
  if not exists (select 1 from hsf_file where client_account_id = k_company) then
    perform hsf_generate_file(k_admin_auth, jsonb_build_object(
      'industry_code', 'CONSTR',
      'triggers', jsonb_build_array('T-SCAFFOLD','T-LADDERS','T-LIFTING','T-HCA'),
      'scope', jsonb_build_object('sites', jsonb_build_array(jsonb_build_object('name', 'Rietvlei Yard (fictitious)')), 'headcount', '48')));
  end if;

  -- 7. The inspection (scaffolds), walked yesterday.
  insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status, scheduled_for, recurrence, device_id)
  values (k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000061', k_inspector,
          'Scaffold inspection, Rietvlei Yard (fictitious)', 'in_progress', current_date - 1, 'monthly', 'DEMO-DEVICE-01');

  insert into bi_inspection_area (id, inspection_id, tenant_id, client_account_id, room_id, label, ordinal) values
    ('b1a00000-0000-4000-8000-000000000082', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000048', 'Scaffold laydown area', 1),
    ('b1a00000-0000-4000-8000-000000000083', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000046', 'Workshop floor', 2),
    ('b1a00000-0000-4000-8000-000000000084', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000047', 'Chemical store', 3);

  insert into bi_finding (id, inspection_id, tenant_id, client_account_id, area_id, template_item_id, equipment_id, result, note, severity, captured_by, captured_at, gps_lat, gps_lng)
  select x.id::uuid, k_insp, k_tenant, k_company, x.area::uuid,
         (select ti.id from bi_template_item ti where ti.template_id = 'b1a00000-0000-4000-8000-000000000061' and ti.ordinal = x.ord),
         x.equip::uuid, x.result, x.note, x.sev, case when x.by_assistant then k_assistant else k_inspector end,
         v_captured + (x.ord || ' minutes')::interval, -25.790000, 28.300000
    from (values
      ('b1a00000-0000-4000-8000-000000000091', 'b1a00000-0000-4000-8000-000000000082', 1, 'b1a00000-0000-4000-8000-000000000051', 'pass', 'Base plates and sole boards sound on bay 14.', null, false),
      ('b1a00000-0000-4000-8000-000000000092', 'b1a00000-0000-4000-8000-000000000082', 2, 'b1a00000-0000-4000-8000-000000000051', 'fail', 'Toe boards missing on the second lift of bay 14.', 'high', false),
      ('b1a00000-0000-4000-8000-000000000093', 'b1a00000-0000-4000-8000-000000000082', 3, 'b1a00000-0000-4000-8000-000000000051', 'observe', 'Tag inspection falls due in three days.', 'low', true),
      ('b1a00000-0000-4000-8000-000000000094', 'b1a00000-0000-4000-8000-000000000083', 5, null, 'pass', 'Access ladder tied in and extends past the platform.', null, false),
      ('b1a00000-0000-4000-8000-000000000095', 'b1a00000-0000-4000-8000-000000000083', 4, null, 'fail', 'Last two weekly entries in the scaffold register are unsigned.', 'medium', false),
      ('b1a00000-0000-4000-8000-000000000096', 'b1a00000-0000-4000-8000-000000000084', 6, null, 'na', 'No scaffold near the chemical store.', null, true)
    ) as x(id, area, ord, equip, result, note, sev, by_assistant);

  insert into bi_photo (id, inspection_id, tenant_id, client_account_id, area_id, finding_id, equipment_id, kind, storage_path, sha256, size_bytes, mime_type,
                        captured_at, gps_lat, gps_lng, gps_accuracy_m, inspector_user_id, caption)
  values
    ('b1a00000-0000-4000-8000-0000000000a1', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000082', null, null, 'area',
     k_company || '/' || k_insp || '/demo-area-laydown.jpg', encode(extensions.digest('demo photo a1', 'sha256'), 'hex'), 812345, 'image/jpeg',
     v_captured, -25.790000, 28.300000, 4.5, k_inspector, 'Scaffold laydown area, general view (fictitious)'),
    ('b1a00000-0000-4000-8000-0000000000a2', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000082', 'b1a00000-0000-4000-8000-000000000092',
     'b1a00000-0000-4000-8000-000000000051', 'risk_close_up',
     k_company || '/' || k_insp || '/demo-missing-toe-boards.jpg', encode(extensions.digest('demo photo a2', 'sha256'), 'hex'), 1034567, 'image/jpeg',
     v_captured + interval '3 minutes', -25.790010, 28.300020, 3.0, k_inspector, 'Missing toe boards, second lift, bay 14 (fictitious)'),
    ('b1a00000-0000-4000-8000-0000000000a3', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000083', 'b1a00000-0000-4000-8000-000000000095', null, 'other',
     k_company || '/' || k_insp || '/demo-register-unsigned.jpg', encode(extensions.digest('demo photo a3', 'sha256'), 'hex'), 654321, 'image/jpeg',
     v_captured + interval '6 minutes', -25.790100, 28.300100, 6.0, k_inspector, 'Scaffold register with two unsigned entries (fictitious)');

  insert into bi_voice_note (id, inspection_id, tenant_id, client_account_id, area_id, finding_id, audio_path, audio_sha256, size_bytes, mime_type,
                             duration_seconds, captured_at, gps_lat, gps_lng, inspector_user_id, transcript_status)
  values
    ('b1a00000-0000-4000-8000-0000000000b1', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000082', 'b1a00000-0000-4000-8000-000000000092',
     k_company || '/' || k_insp || '/demo-vn-1.m4a', encode(extensions.digest('demo voice b1', 'sha256'), 'hex'), 245760, 'audio/mp4', 42,
     v_captured + interval '4 minutes', -25.790010, 28.300020, k_inspector, 'transcribed'),
    ('b1a00000-0000-4000-8000-0000000000b2', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000083', 'b1a00000-0000-4000-8000-000000000095',
     k_company || '/' || k_insp || '/demo-vn-2.m4a', encode(extensions.digest('demo voice b2', 'sha256'), 'hex'), 163840, 'audio/mp4', 28,
     v_captured + interval '7 minutes', -25.790100, 28.300100, k_inspector, 'transcribed');

  insert into bi_voice_transcript (voice_note_id, tenant_id, client_account_id, version, source, body, created_by) values
    ('b1a00000-0000-4000-8000-0000000000b1', k_tenant, k_company, 1, 'machine', 'Bay fourteen, second lift, no toe boards on the open side. Scaffold team told to stop using it until fixed. (fictitious)', null),
    ('b1a00000-0000-4000-8000-0000000000b1', k_tenant, k_company, 2, 'correction', 'Bay 14, second lift: no toe boards on the open side. Scaffold team told to stop using it until fixed. (fictitious)', k_inspector),
    ('b1a00000-0000-4000-8000-0000000000b2', k_tenant, k_company, 1, 'machine', 'Register in the workshop, last two weekly entries not signed. (fictitious)', null);

  insert into bi_risk (id, inspection_id, tenant_id, client_account_id, area_id, finding_id, hazard, consequence,
                       inherent_likelihood, inherent_severity, controls, residual_likelihood, residual_severity) values
    ('b1a00000-0000-4000-8000-0000000000c1', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000082', 'b1a00000-0000-4000-8000-000000000092',
     'Materials falling from an unprotected platform edge', 'Serious injury to people below', 4, 4,
     '[{"level":"engineering","description":"Fit toe boards on every open side"},{"level":"administrative","description":"Barricade below until fixed"}]', 2, 4),
    ('b1a00000-0000-4000-8000-0000000000c2', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000083', 'b1a00000-0000-4000-8000-000000000095',
     'Scaffold used without a recorded inspection', 'Collapse or fall from an unsafe scaffold', 3, 5,
     '[{"level":"administrative","description":"Competent person signs the register before use each week"}]', 1, 5),
    ('b1a00000-0000-4000-8000-0000000000c3', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000082', null,
     'Worker falls while climbing the scaffold', 'Fracture', 2, 4,
     '[{"level":"ppe","description":"Harness above two metres"}]', null, null);

  insert into bi_corrective_action (id, inspection_id, tenant_id, client_account_id, finding_id, risk_id, description, owner_name, due_on, status) values
    ('b1a00000-0000-4000-8000-0000000000d1', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000092', 'b1a00000-0000-4000-8000-0000000000c1',
     'Fit toe boards to every open side of bay 14 and re inspect before use.', 'Sipho Nkosi (fictitious)', current_date + 2, 'open'),
    ('b1a00000-0000-4000-8000-0000000000d2', k_insp, k_tenant, k_company, 'b1a00000-0000-4000-8000-000000000095', 'b1a00000-0000-4000-8000-0000000000c2',
     'Competent person to sign the outstanding register entries and brief the scaffold team.', 'Naledi Dlamini (fictitious)', current_date + 7, 'open');

  -- Submitted: the Fail rule (photo, corrective action, and voice note under the strict policy) holds.
  update bi_inspection set status = 'submitted' where id = k_insp;

  -- 8. The report: an assistive draft citing the demonstration kernel, then sign off.
  v_report := bi_report_save_draft(k_insp_auth, k_insp, jsonb_build_object(
    'label', 'Assistive draft. Competent person sign off required.',
    'demo', true,
    'title', 'Scaffold inspection, Rietvlei Yard (fictitious)',
    'executive_summary', 'Six checklist items inspected across three areas. Two Fail findings need action: toe boards on bay 14 and the unsigned scaffold register. (fictitious demonstration)',
    'areas', jsonb_build_array('Scaffold laydown area', 'Workshop floor', 'Chemical store'),
    'claims', jsonb_build_array(
      jsonb_build_object('text', 'Every open side of a working platform needs edge protection before use.', 'kernel_ref', 'CNC-DEMO-SCAFF-01', 'finding_id', 'b1a00000-0000-4000-8000-000000000092'),
      jsonb_build_object('text', 'A scaffold inspection is recorded before use and at the interval the competent person sets.', 'kernel_ref', 'CNC-DEMO-SCAFF-02', 'finding_id', 'b1a00000-0000-4000-8000-000000000095'),
      jsonb_build_object('text', 'Each Fail finding has an owner, a due date and closure evidence.', 'kernel_ref', 'CNC-DEMO-GEN-01')),
    'voice_note_index', jsonb_build_array(
      jsonb_build_object('vn', 1, 'finding_id', 'b1a00000-0000-4000-8000-000000000092'),
      jsonb_build_object('vn', 2, 'finding_id', 'b1a00000-0000-4000-8000-000000000095')),
    'footer', 'This report is powered by Care Net Consultants Development House (Pty) Ltd'), 'ai_assistive',
    'b1a00000-0000-4000-8000-000000000071');
  v_rid := (v_report ->> 'report_id')::uuid;
  perform bi_report_request_signoff(k_insp_auth, v_rid);
  v_step := bi_step_up_record(k_insp_auth, jsonb_build_object('purpose', 'signoff', 'method', 'totp', 'aal', 'aal2',
              'asserted_epoch', extract(epoch from now()), 'session_ref', encode(extensions.digest('demo session', 'sha256'), 'hex')));
  perform bi_report_sign(k_insp_auth, v_rid, jsonb_build_object('step_up_id', v_step ->> 'step_up_id', 'channel', 'in_app',
            'device_integrity', 'ok', 'confirm_photos', true, 'confirm_voice_notes', true));
  -- Issued: files into Section F (HSF-F-01) and records the MCO package.
  perform bi_report_issue(v_rid, k_company || '/' || v_rid || '/report-demo.pdf',
                          encode(extensions.digest('demo report pdf', 'sha256'), 'hex'), k_company || '/' || v_rid || '/report-demo.json');
  perform bi_mco_register(k_company);

  -- 10. The wallet: this month's included value, a R249,00 top up, one demonstration charge.
  perform bi_wallet_grant_included('b1a00000-0000-4000-8000-000000000031', date_trunc('month', current_date)::date);
  v_wallet := bi_wallet_ensure(k_tenant, k_company);
  perform bi_wallet_topup_apply(v_wallet, 'topup_249', 'demo:topup:0001');
  -- The AI rates are placeholders, so the demonstration charge is written as
  -- already charged (R11,80 against an estimate of R12,34) rather than
  -- priced from invented rates.
  insert into bi_usage_event (wallet_id, tenant_id, client_account_id, auth_user_id, report_id, inspection_id, kind, model_code,
                              estimate_cents, actual_cents, charged_cents, shortfall_cents, status, estimate_key, charge_key, charged_at)
  values (v_wallet, k_tenant, k_company, k_insp_auth, v_rid, k_insp, 'ai_draft', 'ai_quality', 1234, 1180, 1180, 0, 'charged',
          'demo:estimate:0001', 'demo:charge:0001', now())
  returning id into v_ue;
  select l.lot_id into v_lot from bi_wallet_lots(v_wallet) l where l.entry_kind = 'included_credit' order by l.expires_at limit 1;
  insert into bi_wallet_ledger (wallet_id, entry_kind, amount_cents, lot_id, idempotency_key, usage_event_id, note, created_by)
  values (v_wallet, 'charge', -1180, v_lot, 'demo:charge:0001:1', v_ue, 'Demonstration AI draft charge (fictitious)', 'seed')
  on conflict (idempotency_key) do nothing;

  raise notice 'bee_inspect_demo: seeded report %', v_rid;
end;
$seed$;
