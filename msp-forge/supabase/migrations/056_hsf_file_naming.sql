-- CNC MSP FORGE | HSF-NAME-01 v1.2.0 | The File names the Medical Surveillance Plan as a separate product, and registers a company without starting a Plan 24/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 15 (Amendment 7): the Health and Safety
-- File stands on its own and never presents the Medical Surveillance Plan as part
-- of it. The Plan is a separate Care Net product signed by the Occupational
-- Medical Practitioner; the File only holds the signed Plan in Section E as
-- evidence. Amends SPEC B6.6 (row HSF-E-01, see B6.6.1).
-- v1.1.0 (24/09/2026, before 056 was applied): adds step 4, File only company
-- registration (build contract section 15).
-- v1.2.0 (24/09/2026, before 056 was applied): step 2 also carries the guidance
-- corrections of the separation review (findings F1 and F2), and step 3 also
-- refuses guidance that gives the OMP a sign off of the File.
--
-- What this migration does:
--   1. Element HSF-E-01. Migration 048 seeded it as "The released Medical
--      Surveillance Plan from MSP FORGE" (name and duty), which named an internal
--      system to every visitor of the builder and blurred the two products. It
--      now reads as the signed Medical Surveillance Plan, a separate Care Net
--      product signed by the OMP, filed as evidence; its duty (the description
--      the builder shows under the name) says the same in a full sentence.
--      hsf_file_item rows point at the element by id, so every File, existing
--      or new, shows the new name.
--   2. Guidance. Every guidance row whose text changed since 055: the
--      example for HSF-E-01, which had a doubled comma ("signed by its OMP,,
--      covering"), and the first item to submit for HSF-E-01 and for Section E,
--      which called the Plan "released" (the Plan product's own word) and now
--      read "The Medical Surveillance Plan, a separate Care Net product signed
--      by the OMP". Then the separation review (v1.2.0): the Section E intro
--      said "this section is signed off by the OMP only", which made the Plan's
--      signatory a File signatory; it now says the OMP signs the Plan, filed
--      here as evidence, and does not sign the File. The first File order's
--      Section E reason, the first Section E tip and the "why" of HSF-E-01 said
--      the Plan follows from, or is built from, the File's own Section C risk
--      assessment, and the order reason said only certificates of fitness go in
--      the File; none of that holds (the Plan is a separate product built
--      from its own job role mapping, and HSF-E-01 files the signed Plan here),
--      so each now stands on its own. The last Section L tip and the "why" of
--      HSF-L-05 assumed every File company holds a Plan; they now say "if you
--      also hold" one, or name no Plan. These statements are the output of
--        python3 hsf/build_guidance.py --delta
--      pasted as printed; the generator's --check fails until every change to
--      hsf/guidance/ since 055 is carried by a migration after 055.
--   3. A check refuses the migration if HSF-E-01 does not carry the new name
--      and duty, or if any element name or duty, or any guidance text, still
--      carries "MSP FORGE", "HSF FORGE" or a doubled comma, or if any guidance
--      text gives the OMP a sign off of the File or of a section ("signed off
--      by the OMP", "OMP signs off"): the OMP signs only the separate Plan.
--   4. File only company registration: hsf_client_register(p jsonb). The
--      builder (vercel/hsf-builder.html) registered a company through
--      /api/signon and msp_client_signon (migration 043), which calls
--      msp_client_start_assessment (migration 040): that approves the account
--      as a Plan client (audit client_self_approved) and mints a live Plan
--      assessment token in msp_form_access (audit form_access_granted). So a
--      company registering for its File quietly started a Medical Surveillance
--      Plan assessment, and the builder's POPIA tick box was untrue.
--      hsf_client_register records the company account exactly as
--      msp_client_signon does (the same validation, the same lower case email
--      match, the same insert of company_name, contact_name, contact_email,
--      contact_number and notes; on a repeat it only fills in a missing contact
--      number), audits hsf_client_register or hsf_client_register_repeat, and
--      never approves the account, never calls msp_client_start_assessment and
--      never touches msp_form_access. It returns status, reference, existing,
--      company_name, contact_number and declined (account_kind 'declined', as
--      040 decides it); never a token. /api/signon (v1.5.0) calls it when the
--      body carries source 'hsf'.
--      The File needs no approval: hsf_link_account (049), consent, File
--      generation, verification and uploads refuse only a declined account, so
--      the new account, left an applicant, links to its signed in contact and
--      builds its File. If that contact later chooses the Plan, the Plan
--      landing's /api/company-lookup calls msp_client_start_assessment then,
--      as for any account. test/sql/hsf_register_checks.sql proves all of it.
--      Service role only, as 043 grants msp_client_signon (revoked from
--      public, anon and authenticated), with the explicit service role grant
--      of migrations 049 to 055 so it holds whatever the default privileges.
--
-- Migrations 040, 043, 048 and 055 are applied to the live project and stay
-- unchanged; apart from step 4's new function and its grant, nothing here
-- alters a table, a policy or a grant. Idempotent: every update is guarded and
-- the function is created or replaced, so a second run changes no row.

-- 1. HSF-E-01: the signed Medical Surveillance Plan, filed as evidence ---------------------

update hsf_element
   set name = 'The signed Medical Surveillance Plan, a separate Care Net product signed by the OMP, filed as evidence',
       duty = 'The Medical Surveillance Plan is a separate Care Net product, signed by the Occupational Medical Practitioner (OMP). The signed Plan is filed in Section E as evidence; clinical records stay with the occupational health practitioner.'
 where code = 'HSF-E-01'
   and (name, duty) is distinct from (
       'The signed Medical Surveillance Plan, a separate Care Net product signed by the OMP, filed as evidence',
       'The Medical Surveillance Plan is a separate Care Net product, signed by the Occupational Medical Practitioner (OMP). The signed Plan is filed in Section E as evidence; clinical records stay with the occupational health practitioner.');

-- 2. Guidance rows changed since 055 (python3 hsf/build_guidance.py --delta) ----------------

-- meta
update hsf_guidance_meta
   set first_file_order = '[{"section": "A", "reason": "Your company details, sites, COIDA letter of good standing and contractor agreements define what the File covers and who it belongs to. Everything else hangs off this."}, {"section": "B", "reason": "The signed policy, the section 16(2) assignment and your appointments name the people who will build and keep the rest of the File. Without them nobody owns the work."}, {"section": "C", "reason": "Your risk assessment tells you which training, medical surveillance, registers, permits and hygiene surveys you actually need, so do it before you collect those records."}, {"section": "D", "reason": "Once you know the risks, match each person to the training and competence the risk assessment calls for, starting with inductions and the appointees from Section B."}, {"section": "E", "reason": "Your Section C risk assessment shows which exposures need medical surveillance. File the signed Medical Surveillance Plan, a separate Care Net product, and each person''s certificate of fitness here; clinical records stay with the occupational health practitioner."}, {"section": "K", "reason": "Contractors and visitors bring risk onto your site from day one, so get their Files, section 37(2) agreements and site rules in place early."}, {"section": "F", "reason": "List the equipment, machinery and installations your risk assessment found and file their latest inspection records."}, {"section": "G", "reason": "Set up permits for the high risk work your risk assessment identified (hot work, work at height, confined spaces, isolation) before that work next happens."}, {"section": "H", "reason": "Write the emergency plan around your real sites and people, then run and record a drill so you know it works."}, {"section": "I", "reason": "Start the incident register and reporting route now, so the next injury or near miss is recorded and handled properly, including COIDA."}, {"section": "L", "reason": "Committee minutes, representative inspections and toolbox talks show the File is alive and that workers are consulted. They build up month by month, so start the rhythm early."}, {"section": "J", "reason": "Occupational hygiene surveys take time to book and report. Commission them once Section C shows which exposures need measuring."}, {"section": "M", "reason": "Welfare facilities, the workplace environment and waste are usually quick to evidence once the core risk work is done."}, {"section": "O", "reason": "Decide how long you keep each record, where it is stored and who may see it, especially personal and medical information, before the File grows large."}, {"section": "N", "reason": "Audit and review come last on a first File: once the other sections hold evidence, review them, set objectives and track the corrective actions."}]'::jsonb
 where id = 1
   and first_file_order is distinct from '[{"section": "A", "reason": "Your company details, sites, COIDA letter of good standing and contractor agreements define what the File covers and who it belongs to. Everything else hangs off this."}, {"section": "B", "reason": "The signed policy, the section 16(2) assignment and your appointments name the people who will build and keep the rest of the File. Without them nobody owns the work."}, {"section": "C", "reason": "Your risk assessment tells you which training, medical surveillance, registers, permits and hygiene surveys you actually need, so do it before you collect those records."}, {"section": "D", "reason": "Once you know the risks, match each person to the training and competence the risk assessment calls for, starting with inductions and the appointees from Section B."}, {"section": "E", "reason": "Your Section C risk assessment shows which exposures need medical surveillance. File the signed Medical Surveillance Plan, a separate Care Net product, and each person''s certificate of fitness here; clinical records stay with the occupational health practitioner."}, {"section": "K", "reason": "Contractors and visitors bring risk onto your site from day one, so get their Files, section 37(2) agreements and site rules in place early."}, {"section": "F", "reason": "List the equipment, machinery and installations your risk assessment found and file their latest inspection records."}, {"section": "G", "reason": "Set up permits for the high risk work your risk assessment identified (hot work, work at height, confined spaces, isolation) before that work next happens."}, {"section": "H", "reason": "Write the emergency plan around your real sites and people, then run and record a drill so you know it works."}, {"section": "I", "reason": "Start the incident register and reporting route now, so the next injury or near miss is recorded and handled properly, including COIDA."}, {"section": "L", "reason": "Committee minutes, representative inspections and toolbox talks show the File is alive and that workers are consulted. They build up month by month, so start the rhythm early."}, {"section": "J", "reason": "Occupational hygiene surveys take time to book and report. Commission them once Section C shows which exposures need measuring."}, {"section": "M", "reason": "Welfare facilities, the workplace environment and waste are usually quick to evidence once the core risk work is done."}, {"section": "O", "reason": "Decide how long you keep each record, where it is stored and who may see it, especially personal and medical information, before the File grows large."}, {"section": "N", "reason": "Audit and review come last on a first File: once the other sections hold evidence, review them, set objectives and track the corrective actions."}]'::jsonb;

-- section E
update hsf_section_guidance
   set intro = 'Section E shows that people are fit for the work and exposures your risk assessment found, and that their health information is handled confidentially. Its key document is the signed Medical Surveillance Plan, a separate Care Net product filed here as evidence. The occupational medical practitioner (OMP) signs that Plan; the OMP does not sign your File. Care Net screens fitness for work and does not diagnose. Clinical records stay with the occupational health practitioner; your File holds only the outcome for each person: fit, fit with restrictions or unfit.',
       what_goes_here = '["The Medical Surveillance Plan, a separate Care Net product signed by the OMP", "Certificates of fitness per employee: baseline, periodic and exit", "Construction, driving permit and mine fitness certificates where that work applies", "Outcomes of the specific examinations your exposures call for, such as lead, noise or hazardous chemical agents", "A register of fitness restrictions and how each one was reflected in the person''s job", "Proof that occupational diseases were reported (date, body notified and reference), first aid records and a note on how medical records are kept confidential"]'::jsonb,
       first_file_tips = '["Finish your risk assessment in Section C first; it shows which exposures call for medical surveillance and which specific examinations your people need.", "Never upload clinical notes, test results or doctors'' letters to your File. Upload only the certificate of fitness showing the outcome.", "Put each person''s certificate expiry date in your training and medical diary so nobody works past it.", "If a certificate says fit with restrictions, record what you changed in the person''s job; that record matters as much as the certificate."]'::jsonb
 where section_code = 'E'
   and (intro, what_goes_here, first_file_tips) is distinct from (
       'Section E shows that people are fit for the work and exposures your risk assessment found, and that their health information is handled confidentially. Its key document is the signed Medical Surveillance Plan, a separate Care Net product filed here as evidence. The occupational medical practitioner (OMP) signs that Plan; the OMP does not sign your File. Care Net screens fitness for work and does not diagnose. Clinical records stay with the occupational health practitioner; your File holds only the outcome for each person: fit, fit with restrictions or unfit.',
       '["The Medical Surveillance Plan, a separate Care Net product signed by the OMP", "Certificates of fitness per employee: baseline, periodic and exit", "Construction, driving permit and mine fitness certificates where that work applies", "Outcomes of the specific examinations your exposures call for, such as lead, noise or hazardous chemical agents", "A register of fitness restrictions and how each one was reflected in the person''s job", "Proof that occupational diseases were reported (date, body notified and reference), first aid records and a note on how medical records are kept confidential"]'::jsonb,
       '["Finish your risk assessment in Section C first; it shows which exposures call for medical surveillance and which specific examinations your people need.", "Never upload clinical notes, test results or doctors'' letters to your File. Upload only the certificate of fitness showing the outcome.", "Put each person''s certificate expiry date in your training and medical diary so nobody works past it.", "If a certificate says fit with restrictions, record what you changed in the person''s job; that record matters as much as the certificate."]'::jsonb);

-- section L
update hsf_section_guidance
   set first_file_tips = '["Keep the committee action list separate from the minutes and carry open items forward until they are closed.", "Answer every representative''s recommendation in writing, even if the answer is no, and give the reason.", "Photograph your notice board once a year and file the photo; it is the simplest proof of what was displayed.", "When you add a new process, chemical or site, update your risk assessment; if you also hold a Medical Surveillance Plan, a separate Care Net product, tell Care Net so that Plan can be updated."]'::jsonb
 where section_code = 'L'
   and first_file_tips is distinct from '["Keep the committee action list separate from the minutes and carry open items forward until they are closed.", "Answer every representative''s recommendation in writing, even if the answer is no, and give the reason.", "Photograph your notice board once a year and file the photo; it is the simplest proof of what was displayed.", "When you add a new process, chemical or site, update your risk assessment; if you also hold a Medical Surveillance Plan, a separate Care Net product, tell Care Net so that Plan can be updated."]'::jsonb;

-- element HSF-E-01
update hsf_element_guidance
   set what_to_submit = '["The Medical Surveillance Plan, a separate Care Net product signed by the OMP", "The list of exposure groups and jobs the Plan covers", "Record of the yearly review and any changes"]'::jsonb,
       why = 'The Plan is Section E''s key evidence: it sets out which people need which examinations and how often. It is a separate Care Net product signed by the occupational medical practitioner, and it is reviewed once a year and whenever your exposures change.',
       example = 'Example: Ndlovu Engineering in Middelburg files its Medical Surveillance Plan, a separate Care Net product signed by its OMP, covering welders for noise and fumes and stores staff for manual handling only.'
 where element_code = 'HSF-E-01'
   and (what_to_submit, why, example) is distinct from (
       '["The Medical Surveillance Plan, a separate Care Net product signed by the OMP", "The list of exposure groups and jobs the Plan covers", "Record of the yearly review and any changes"]'::jsonb,
       'The Plan is Section E''s key evidence: it sets out which people need which examinations and how often. It is a separate Care Net product signed by the occupational medical practitioner, and it is reviewed once a year and whenever your exposures change.',
       'Example: Ndlovu Engineering in Middelburg files its Medical Surveillance Plan, a separate Care Net product signed by its OMP, covering welders for noise and fumes and stores staff for manual handling only.');

-- element HSF-L-05
update hsf_element_guidance
   set why = 'When your processes, chemicals, sites or workforce change, your medical surveillance and your client''s safety planning must change too. The log shows each change was notified to whoever runs your medical surveillance and to your client, so their plans stay accurate.'
 where element_code = 'HSF-L-05'
   and why is distinct from 'When your processes, chemicals, sites or workforce change, your medical surveillance and your client''s safety planning must change too. The log shows each change was notified to whoever runs your medical surveillance and to your client, so their plans stay accurate.';

-- 3. Refuse a library or guidance text that still names an internal system ----------------

do $$
declare
  v_pat constant text := '(MSP|HSF) FORGE|,[[:space:]]*,';
  v_omp constant text := 'signed off by (the |its |your )?(OMP|occupational medical practitioner)\M|\m(OMP|occupational medical practitioner)( only)? signs? off\M';
  v_bad text;
begin
  if not exists (select 1 from hsf_element
                  where code = 'HSF-E-01'
                    and name = 'The signed Medical Surveillance Plan, a separate Care Net product signed by the OMP, filed as evidence'
                    and duty = 'The Medical Surveillance Plan is a separate Care Net product, signed by the Occupational Medical Practitioner (OMP). The signed Plan is filed in Section E as evidence; clinical records stay with the occupational health practitioner.') then
    raise exception 'HSF-NAME-01: element HSF-E-01 is missing or does not carry its new name and duty';
  end if;
  select string_agg(x, ', ' order by x) into v_bad from (
    select 'element ' || code as x from hsf_element where name ~ v_pat or duty ~ v_pat
    union all select 'element guidance ' || element_code from hsf_element_guidance
      where concat_ws(' ', what_to_submit::text, why, example, common_gaps::text) ~ v_pat
    union all select 'appointment guidance ' || appointment_code from hsf_appointment_guidance
      where concat_ws(' ', what_to_submit::text, why, example, common_gaps::text) ~ v_pat
    union all select 'class guidance ' || class_code from hsf_class_guidance
      where concat_ws(' ', what_to_submit::text, why, example, common_gaps::text) ~ v_pat
    union all select 'section guidance ' || section_code from hsf_section_guidance
      where concat_ws(' ', intro, what_goes_here::text, first_file_tips::text) ~ v_pat
    union all select 'guidance meta' from hsf_guidance_meta
      where concat_ws(' ', note, first_file_intro, first_file_order::text, before_you_start::text) ~ v_pat) b;
  if v_bad is not null then
    raise exception 'HSF-NAME-01: visible text still names an internal system or has a doubled comma: %', v_bad;
  end if;
  -- The OMP signs the separate Medical Surveillance Plan, never the File or a section of it.
  select string_agg(x, ', ' order by x) into v_bad from (
    select 'element guidance ' || element_code as x from hsf_element_guidance
      where concat_ws(' ', what_to_submit::text, why, example, common_gaps::text) ~* v_omp
    union all select 'appointment guidance ' || appointment_code from hsf_appointment_guidance
      where concat_ws(' ', what_to_submit::text, why, example, common_gaps::text) ~* v_omp
    union all select 'class guidance ' || class_code from hsf_class_guidance
      where concat_ws(' ', what_to_submit::text, why, example, common_gaps::text) ~* v_omp
    union all select 'section guidance ' || section_code from hsf_section_guidance
      where concat_ws(' ', intro, what_goes_here::text, first_file_tips::text) ~* v_omp
    union all select 'guidance meta' from hsf_guidance_meta
      where concat_ws(' ', note, first_file_intro, first_file_order::text, before_you_start::text) ~* v_omp) b;
  if v_bad is not null then
    raise exception 'HSF-NAME-01: guidance gives the OMP a sign off of the File: %', v_bad;
  end if;
end;
$$;

-- 4. File only company registration (no Plan assessment) ---------------------------------

create or replace function hsf_client_register(p jsonb)
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
  v_acc msp_client_account%rowtype;
begin
  if v_company = '' or v_contact = '' or v_email = '' then
    raise exception 'company name, contact name, and email are required';
  end if;
  if v_number is not null and length(v_number) > 40 then
    raise exception 'contact number is too long';
  end if;

  -- One registration at a time per email, so a double submit makes one account.
  perform pg_advisory_xact_lock(hashtext('hsf_client_register'), hashtext(v_email));

  select id into v_id
    from msp_client_account
   where lower(contact_email) = v_email
   order by created_at desc
   limit 1;

  if v_id is not null then
    v_existing := true;
    -- A repeat registration may bring a number the account never had.
    if v_number is not null then
      update msp_client_account
         set contact_number = v_number
       where id = v_id and contact_number is null;
    end if;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'hsf_client_register_repeat',
            jsonb_build_object('client_account_id', v_id, 'email', v_email));
  else
    insert into msp_client_account (company_name, contact_name, contact_email, contact_number, notes)
    values (v_company, v_contact, v_email, v_number, v_notes)
    returning id into v_id;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'hsf_client_register',
            jsonb_build_object('client_account_id', v_id, 'company', v_company, 'email', v_email));
  end if;

  -- The account as it stands; its kind is read, never changed.
  select * into v_acc from msp_client_account where id = v_id;

  return jsonb_build_object(
    'status', 'received',
    'reference', v_acc.id,
    'existing', v_existing,
    'company_name', v_acc.company_name,
    'contact_number', v_acc.contact_number,
    'declined', v_acc.account_kind = 'declined');
end;
$$;
revoke execute on function hsf_client_register(jsonb) from public, anon, authenticated;
grant execute on function hsf_client_register(jsonb) to service_role;
comment on function hsf_client_register is 'Server side only (/api/signon with source hsf): records a company registered from the Health and Safety File builder (company, contact, email, optional contact_number, notes) and returns its reference. Never approves the account, never starts a Medical Surveillance Plan assessment and never issues an assessment token; the Plan starts only if the contact later chooses it (msp_client_start_assessment through /api/company-lookup). Idempotent on contact_email. Audited as hsf_client_register or hsf_client_register_repeat. Migration 056.';

notify pgrst, 'reload schema';
