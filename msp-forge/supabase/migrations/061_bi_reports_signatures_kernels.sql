-- CNC HSF FORGE | BI-RPT-01 v1.0.0 | Bee-Inspect reports, sign off, kernels and Section F filing 26/09/2026
-- Built to hsf/BUILD-CONTRACT.md 16 and hsf/BEE-INSPECT-BUILD-PROMPT.md B6, B7, B9
-- and sections 3 and 6, phase P3.
--
-- What this migration does:
--   1. The report kernel store: bi_kernel_version, bi_kernel_doc, bi_kernel_chunk
--      (pgvector embedding, extensions.vector(1536) as in msp_precedent; the
--      local replay rewrites it to real[]). Global documents (OHS Act and
--      regulations, Construction Regulations, ISO 45001 mapping, Care Net
--      methodology) and tenant procedures. Nothing is loaded here: the source
--      is {{kernel_source}}.
--   2. bi_report and bi_report_version: the structured report JSON, versioned
--      and append only. An AI draft carries the label "Assistive draft.
--      Competent person sign off required." and every legal claim carries a
--      kernel reference (claims[].kernel_ref naming a bi_kernel_chunk.ref of a
--      released kernel version).
--   3. bi_signature: the competent person's signature on one report version,
--      with the step up MFA assertion it consumed (bi_step_up, 059), the
--      channel (in app or DocuSeal), device integrity and the reviewer's
--      confirmation of photos and voice notes. Append only.
--   4. The Issued guard (bi_report_guard): a report becomes Issued only from
--      Awaiting sign off, with a signature on its current version by a cleared
--      inspector whose competence scope covers the template, a step up
--      assertion within the window, no compromised device, every claim cited,
--      under the strict policy every voice note accounted for, and the PDF and
--      JSON stored (paths and fingerprint). Unsigned reports stay Draft or
--      Awaiting sign off. Clients cannot write reports at all.
--   5. Section F filing (bi_hsf_section_f_sync): when a report becomes Issued
--      it is recorded against the company's File. The File tables are not
--      altered: a new link table bi_report_file_link holds the report to File
--      link, and the Section F element the template maps to (for example
--      HSF-F-01 scaffolds) receives a new hsf_evidence version (source
--      engine_generated, the PDF fingerprint), its item becomes uploaded and
--      the File's compliance figure is recomputed (hsf_compute_compliance,
--      051), exactly as a client upload does in hsf_mark_uploaded (049). If
--      the company has no File yet, or the element is not on its File, the
--      link records that and a later run files it.
--   6. bi_transfer_package: the MCO bridge "push report package to Supabase"
--      (B9): one manifest per Issued report, status supabase_stored.
--      mco_ingested is reserved and refused until {{mco_endpoint}} exists.
--
-- Not applied to the live project. hsf_file, hsf_file_item and hsf_evidence are
-- written only through their existing rules (the append only evidence guard of
-- 047 applies); no applied table is altered.

-- 1. Kernels -------------------------------------------------------------------------------

create table bi_kernel_version (
  id uuid primary key default gen_random_uuid(),
  semver text not null unique check (semver ~ '^[A-Z]*-?[0-9]+\.[0-9]+(\.[0-9]+)?$'),
  source text not null,
  status text not null default 'draft' check (status in ('draft','released','retired')),
  released_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  check (status = 'draft' or released_at is not null)
);
comment on table bi_kernel_version is 'BI-RPT-01 (prompt B6). A version of the report kernel store. source records where the content came from ({{kernel_source}}, still open). A report version records the kernel version it was drafted against.';

create table bi_kernel_doc (
  id uuid primary key default gen_random_uuid(),
  kernel_version_id uuid not null references bi_kernel_version(id),
  tenant_id uuid references bi_tenant(id),
  code text not null check (code ~ '^[A-Z][A-Z0-9-]{2,60}$'),
  title text not null,
  source_kind text not null check (source_kind in ('ohs_act','regulation','construction_regulations','iso45001_mapping','cnc_methodology','tenant_procedure')),
  instrument_id uuid references msp_legal_instrument(id),
  created_at timestamptz not null default now(),
  unique (kernel_version_id, code),
  check ((source_kind = 'tenant_procedure') = (tenant_id is not null))
);
comment on table bi_kernel_doc is 'BI-RPT-01 (prompt B6). A document of the report kernel: the OHS Act and its regulations, the Construction Regulations, the ISO 45001 mapping, Care Net''s methodology (global, tenant_id null) or a tenant''s own procedure. instrument_id links a legal document to the Cognitive Kernel instrument (msp_legal_instrument) so the report cites only what the kernel holds.';

create table bi_kernel_chunk (
  id uuid primary key default gen_random_uuid(),
  doc_id uuid not null references bi_kernel_doc(id),
  ordinal int not null check (ordinal >= 1),
  ref text not null check (ref ~ '^[A-Z][A-Z0-9-]{2,80}$'),
  content text not null,
  token_count int check (token_count > 0),
  embedding extensions.vector(1536),
  created_at timestamptz not null default now(),
  unique (doc_id, ordinal)
);
comment on table bi_kernel_chunk is 'BI-RPT-01 (prompt B6). A retrievable chunk of a kernel document with its embedding. ref is what a report claim cites (claims[].kernel_ref). The similarity index is added when the kernel is loaded (P5), with the embedding model chosen then.';
create index bi_kernel_chunk_ref_idx on bi_kernel_chunk(ref);

create function bi_kernel_ref_exists(p_ref text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from bi_kernel_chunk c join bi_kernel_doc d on d.id = c.doc_id
                   join bi_kernel_version v on v.id = d.kernel_version_id
                  where c.ref = p_ref and v.status = 'released');
$$;
comment on function bi_kernel_ref_exists is 'BI-RPT-01. True when the reference names a chunk of a released kernel version.';

-- 2. Reports ----------------------------------------------------------------------------------

create table bi_report (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null unique references bi_inspection(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  title text not null check (length(btrim(title)) between 1 and 200),
  status text not null default 'draft' check (status in ('draft','awaiting_signoff','issued','withdrawn')),
  current_version_id uuid,
  issued_version_id uuid,
  issued_at timestamptz,
  pdf_path text,
  pdf_sha256 text check (pdf_sha256 ~ '^[0-9a-f]{64}$'),
  json_path text,
  reviewer_user_id uuid references bi_app_user(id),
  reviewer_engagement_ref text,
  share_token_hash text check (share_token_hash ~ '^[0-9a-f]{64}$'),
  share_expires_at timestamptz,
  section_f_synced_at timestamptz,
  withdrawn_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bi_report_issued_complete check (status not in ('issued','withdrawn') or
    (issued_version_id is not null and issued_at is not null and pdf_path is not null and pdf_sha256 is not null and json_path is not null)),
  constraint bi_report_reviewer_pair check ((reviewer_user_id is null) = (reviewer_engagement_ref is null))
);
comment on table bi_report is 'BI-RPT-01 (prompt B6, B7). The inspection or risk assessment report of one inspection. Draft and Awaiting sign off until a competent person signs; Issued only through the guard (bi_report_guard); Withdrawn only by Care Net with a reason. Issued means the PDF and JSON are stored (private bucket bi-reports, paths and fingerprint here), the report is filed into the File''s Section F and can be shared by a link that expires. reviewer_user_id is a competent person engaged through Bee-Matched when the inspector is not cleared for the scope (engagement letter reference required). No client writes.';
create index bi_report_company_idx on bi_report(client_account_id, tenant_id);

create table bi_report_version (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references bi_report(id),
  version int not null check (version >= 1),
  content jsonb not null check (jsonb_typeof(content) = 'object'),
  draft_source text not null check (draft_source in ('template','ai_assistive')),
  kernel_version_id uuid references bi_kernel_version(id),
  voice_notes_total int not null default 0,
  voice_notes_referenced int not null default 0,
  created_by uuid references bi_app_user(id),
  created_at timestamptz not null default now(),
  unique (report_id, version),
  constraint bi_report_version_label check (draft_source <> 'ai_assistive'
    or coalesce(content ->> 'label', '') = 'Assistive draft. Competent person sign off required.')
);
comment on table bi_report_version is 'BI-RPT-01 (prompt B6). One version of a report''s structured JSON (executive summary, areas, findings, equipment, risk register extract, corrective actions, claims with kernel references, voice note index). An AI draft carries the label "Assistive draft. Competent person sign off required.". voice_notes_total and voice_notes_referenced give the preview "Voice notes: N accounted for, M missing". Append only.';
create trigger bi_report_version_append_only before update or delete on bi_report_version for each row execute function bi_append_only();

alter table bi_report add constraint bi_report_current_version_fk foreign key (current_version_id) references bi_report_version(id);
alter table bi_report add constraint bi_report_issued_version_fk foreign key (issued_version_id) references bi_report_version(id);

create table bi_signature (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references bi_report(id),
  report_version_id uuid not null references bi_report_version(id),
  signer_user_id uuid not null references bi_app_user(id),
  signer_role text not null check (signer_role in ('inspector','reviewer')),
  channel text not null check (channel in ('in_app','docuseal')),
  docuseal_submission_ref text,
  step_up_id uuid not null unique references bi_step_up(id),
  device_integrity text not null check (device_integrity in ('ok','unknown')),
  confirmed_photos boolean not null check (confirmed_photos),
  confirmed_voice_notes boolean not null check (confirmed_voice_notes),
  qualification_ids uuid[] not null default '{}',
  signed_at timestamptz not null default now(),
  check ((channel = 'docuseal') = (docuseal_submission_ref is not null))
);
comment on table bi_signature is 'BI-RPT-01 (prompt B3, B7). A competent person''s signature on one report version: who, as inspector or engaged reviewer, through the app or DocuSeal, the step up MFA assertion it consumed, the device integrity (a rooted or jailbroken device is refused, so compromised is not a stored value) and the confirmation that the photos and voice notes were reviewed. Append only; written only by bi_report_sign.';
create trigger bi_signature_append_only before update or delete on bi_signature for each row execute function bi_append_only();

-- 3. Rules shared by the guard and the functions ----------------------------------------------------

create function bi_report_claim_problems(p_content jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  -- Every legal claim must carry a kernel reference that a released kernel holds.
  select coalesce(jsonb_agg(jsonb_build_object('index', c.ordinality - 1, 'kernel_ref', c.value ->> 'kernel_ref')), '[]'::jsonb)
    from jsonb_array_elements(case when jsonb_typeof(p_content -> 'claims') = 'array' then p_content -> 'claims' else '[]'::jsonb end)
         with ordinality c
   where coalesce(btrim(c.value ->> 'kernel_ref'), '') = ''
      or not bi_kernel_ref_exists(c.value ->> 'kernel_ref');
$$;
comment on function bi_report_claim_problems is 'BI-RPT-01 (prompt B6). The claims of a report JSON that carry no kernel reference, or one no released kernel version holds. Empty when every claim is cited.';

create function bi_report_voice_counts(p_inspection_id uuid, p_content jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with vn as (select v.vn_number from bi_voice_note v where v.inspection_id = p_inspection_id),
  cited as (
    select distinct (x.value ->> 'vn')::int as n
      from jsonb_array_elements(case when jsonb_typeof(p_content -> 'voice_note_index') = 'array'
                                     then p_content -> 'voice_note_index' else '[]'::jsonb end) x
     where (x.value ->> 'vn') ~ '^[0-9]{1,6}$')
  select jsonb_build_object('total', (select count(*) from vn),
                            'accounted', (select count(*) from vn where vn.vn_number in (select n from cited)),
                            'missing', (select count(*) from vn where vn.vn_number not in (select n from cited)));
$$;
comment on function bi_report_voice_counts is 'BI-RPT-01 (prompt B6). The voice note preview: how many of the inspection''s voice notes the report''s voice_note_index accounts for, and how many are missing.';

create function bi_signer_cleared(p_app_user_id uuid, p_category text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from bi_inspector_profile p
                  where p.app_user_id = p_app_user_id and p.status = 'cleared'
                    and p_category = any(p.competence_scope))
     and not exists (select 1 from bi_inspector_qualification q
                      where q.app_user_id = p_app_user_id
                        and (q.status = 'expired' or (q.status = 'verified' and q.expires_on < current_date)));
$$;
comment on function bi_signer_cleared is 'BI-RPT-01 (prompt B4, B7). A competent person for the scope: cleared, the template category in their competence scope, and no expired qualification.';

-- 4. The Issued guard -------------------------------------------------------------------------------

create function bi_report_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_sig bi_signature;
  v_step bi_step_up;
  v_insp bi_inspection;
  v_cat text;
  v_ver bi_report_version;
  v_counts jsonb;
  v_window int;
begin
  if tg_op = 'DELETE' then
    raise exception 'Reports are withdrawn, never deleted';
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'draft' or new.issued_at is not null or new.issued_version_id is not null then
      raise exception 'A report starts as a draft';
    end if;
    select * into v_insp from bi_inspection where id = new.inspection_id;
    new.tenant_id := v_insp.tenant_id;
    new.client_account_id := v_insp.client_account_id;
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id or new.client_account_id is distinct from old.client_account_id
     or new.inspection_id is distinct from old.inspection_id then
    raise exception 'A report never moves to another inspection, tenant or company';
  end if;

  if old.status in ('issued','withdrawn') then
    -- An Issued report changes only by withdrawal, its Section F filing time and its share link.
    if (to_jsonb(new) - array['status','withdrawn_reason','section_f_synced_at','share_token_hash','share_expires_at','updated_at'])
       is distinct from (to_jsonb(old) - array['status','withdrawn_reason','section_f_synced_at','share_token_hash','share_expires_at','updated_at']) then
      raise exception 'An Issued report is never edited';
    end if;
    if new.status is distinct from old.status and not (old.status = 'issued' and new.status = 'withdrawn'
         and length(btrim(coalesce(new.withdrawn_reason, ''))) >= 10) then
      raise exception 'An Issued report can only be withdrawn, with a reason';
    end if;
    return new;
  end if;

  if new.status = 'withdrawn' then
    raise exception 'Only an Issued report is withdrawn';
  end if;
  if new.status = 'awaiting_signoff' and old.status = 'draft' and new.current_version_id is null then
    raise exception 'A report needs a version before sign off';
  end if;
  if new.status in ('draft','awaiting_signoff') then
    if new.issued_at is not null or new.issued_version_id is not null then
      raise exception 'Only an Issued report carries an issue date';
    end if;
    return new;
  end if;

  -- new.status = 'issued'
  if old.status <> 'awaiting_signoff' then
    raise exception 'A report is Issued only from Awaiting sign off';
  end if;
  select * into v_ver from bi_report_version where id = new.current_version_id and report_id = new.id;
  if v_ver.id is null then
    raise exception 'Issued refused: the report has no current version';
  end if;
  select s.* into v_sig from bi_signature s
   where s.report_id = new.id and s.report_version_id = v_ver.id
   order by s.signed_at desc limit 1;
  if v_sig.id is null then
    raise exception 'Issued refused: no competent person has signed this version. Unsigned reports stay Draft or Awaiting sign off.'
      using errcode = '42501';
  end if;
  select * into v_insp from bi_inspection where id = new.inspection_id;
  select t.category into v_cat from bi_template t where t.id = v_insp.template_id;
  if not bi_signer_cleared(v_sig.signer_user_id, v_cat) then
    raise exception 'Issued refused: the signer is not a cleared competent person for %', v_cat using errcode = '42501';
  end if;
  select * into v_step from bi_step_up where id = v_sig.step_up_id;
  v_window := case when v_sig.channel = 'docuseal' then 1440 else coalesce(msp_env_get_int('bi.step_up_window_minutes'), 10) end;
  if v_step.id is null or v_step.purpose <> 'signoff' or v_step.aal <> 'aal2'
     or v_step.auth_user_id <> (select u.auth_user_id from bi_app_user u where u.id = v_sig.signer_user_id)
     or v_step.asserted_at > v_sig.signed_at + interval '1 minute'
     or v_step.asserted_at < v_sig.signed_at - make_interval(mins => v_window) then
    raise exception 'Issued refused: the signature has no valid step up MFA assertion' using errcode = '42501';
  end if;
  if jsonb_array_length(bi_report_claim_problems(v_ver.content)) > 0 then
    raise exception 'Issued refused: every legal claim must carry a kernel reference';
  end if;
  v_counts := bi_report_voice_counts(new.inspection_id, v_ver.content);
  if v_insp.voice_note_policy = 'strict' and (v_counts ->> 'missing')::int > 0 then
    raise exception 'Issued refused: % voice note(s) missing from the report (strict policy)', v_counts ->> 'missing';
  end if;
  if v_insp.status not in ('submitted','closed') then
    raise exception 'Issued refused: the inspection is not submitted';
  end if;
  if new.pdf_path is null or new.pdf_sha256 is null or new.json_path is null then
    raise exception 'Issued refused: the PDF and JSON must be stored first';
  end if;
  new.issued_version_id := v_ver.id;
  new.issued_at := coalesce(new.issued_at, now());
  return new;
end;
$$;
comment on function bi_report_guard is 'BI-RPT-01 (prompt sections 0 and 3.3, B3, B6, B7). The Issued guard. Insert only as a draft. Issued only from Awaiting sign off with: a signature on the current version by a cleared inspector whose scope covers the template category and with no expired qualification; a step up MFA assertion (purpose signoff, aal2, same person) at most bi.step_up_window_minutes (1 440 for DocuSeal) before signing; every claim cited from a released kernel; under the strict policy no voice note missing; a submitted inspection; the PDF and JSON stored. An Issued report is never edited; it may only be withdrawn with a reason.';
create trigger bi_report_guard before insert or update or delete on bi_report for each row execute function bi_report_guard();

create function bi_report_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger bi_report_touch before update on bi_report for each row execute function bi_report_touch();

-- 5. Section F link and MCO transfer package ----------------------------------------------------------

create table bi_report_file_link (
  report_id uuid primary key references bi_report(id),
  client_account_id uuid not null references msp_client_account(id),
  file_id uuid references hsf_file(id),
  file_item_id uuid references hsf_file_item(id),
  element_code text references hsf_element(code),
  evidence_id uuid references hsf_evidence(id),
  status text not null check (status in ('linked','section_only','no_file','revoked')),
  attempts int not null default 1,
  synced_at timestamptz not null default now(),
  check (status <> 'linked' or (file_item_id is not null and evidence_id is not null)),
  check (status not in ('linked','section_only') or file_id is not null)
);
comment on table bi_report_file_link is 'BI-RPT-01 (prompt B7). Where an Issued report sits in the company''s free File. linked: filed as evidence on the Section F element its template maps to. section_only: the File has no such element (not applicable to it), so the report is listed in Section F without an element. no_file: the company has no File yet; a later run (hsf-section-f-sync) files it. revoked: the report was withdrawn and its evidence revoked. Written only by bi_hsf_section_f_sync and bi_report_withdraw.';
create index bi_report_file_link_file_idx on bi_report_file_link(file_id);

create table bi_transfer_package (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null unique references bi_report(id),
  client_account_id uuid not null references msp_client_account(id),
  package_version text not null default 'inspect_package_v1' check (package_version = 'inspect_package_v1'),
  manifest jsonb not null,
  json_path text not null,
  artifacts_path text,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'supabase_stored' check (status in ('supabase_stored','mco_ingested')),
  mco_ref text,
  created_at timestamptz not null default now(),
  ingested_at timestamptz
);
comment on table bi_transfer_package is 'BI-RPT-01 (prompt B9). The report package pushed to Supabase for MyClinicOnline: manifest (report, company, site and department nodes, file paths, fingerprint), status supabase_stored. mco_ingested and artifacts.zip are reserved for the later bridge and refused until {{mco_endpoint}} exists (bi_transfer_package_guard).';

create function bi_transfer_package_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_transfer_package rows are never deleted';
  end if;
  if new.status = 'mco_ingested' then
    raise exception 'mco_ingested is reserved until the MyClinicOnline endpoint exists ({{mco_endpoint}})';
  end if;
  if tg_op = 'UPDATE' and to_jsonb(new) is distinct from to_jsonb(old) then
    raise exception 'bi_transfer_package is written once';
  end if;
  return new;
end;
$$;
create trigger bi_transfer_package_guard before insert or update or delete on bi_transfer_package for each row execute function bi_transfer_package_guard();

create function bi_hsf_section_f_sync(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_link bi_report_file_link;
  v_file_id uuid;
  v_element text;
  v_item hsf_file_item;
  v_version int;
  v_prev uuid;
  v_ev uuid;
  v_signer text;
  v_status text;
begin
  select * into v_r from bi_report where id = p_report_id;
  if v_r.id is null or v_r.status <> 'issued' then
    raise exception 'Only an Issued report is filed into Section F.' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtext('bi_section_f'), hashtext(p_report_id::text));
  select * into v_link from bi_report_file_link where report_id = p_report_id;
  if v_link.report_id is not null and v_link.status in ('linked','section_only','revoked') then
    return jsonb_build_object('report_id', p_report_id, 'status', v_link.status, 'file_id', v_link.file_id,
                              'element_code', v_link.element_code, 'already', true);
  end if;

  -- The company's current File: the newest that is not superseded or archived.
  select f.id into v_file_id from hsf_file f
   where f.client_account_id = v_r.client_account_id and f.status not in ('superseded','archived')
   order by f.created_at desc, f.id limit 1;
  select t.section_f_element_code into v_element
    from bi_inspection i join bi_template t on t.id = i.template_id where i.id = v_r.inspection_id;

  if v_file_id is null then
    v_status := 'no_file';
  else
    select fi.* into v_item from hsf_file_item fi join hsf_element e on e.id = fi.element_id
     where fi.file_id = v_file_id and e.code = v_element and e.section_code = 'F'
     order by fi.site_ref nulls first, fi.id limit 1
     for update of fi;
    if v_item.id is null then
      v_status := 'section_only';
    else
      v_status := 'linked';
      select u.display_name into v_signer from bi_signature s join bi_app_user u on u.id = s.signer_user_id
       where s.report_id = v_r.id and s.report_version_id = v_r.issued_version_id order by s.signed_at desc limit 1;
      select coalesce(max(e.version), 0) + 1 into v_version from hsf_evidence e where e.file_item_id = v_item.id;
      select e.id into v_prev from hsf_evidence e where e.file_item_id = v_item.id order by e.version desc limit 1;
      -- The same append only evidence ledger a client upload writes (049),
      -- source engine_generated: the fingerprint is the Issued PDF's. The PDF
      -- stays in Bee-Inspect's own private bucket (bi-reports), so storage_path
      -- (the File's staging path) is left null and the link row holds the path.
      insert into hsf_evidence (file_item_id, version, supersedes_id, source, storage_path, sha256, supplied_by, valid_from)
      values (v_item.id, v_version, v_prev, 'engine_generated', null, v_r.pdf_sha256,
              'Bee-Inspect report signed by ' || coalesce(v_signer, 'a competent person'), v_r.issued_at::date)
      returning id into v_ev;
      if v_item.status in ('outstanding','expired') then
        update hsf_file_item set status = 'uploaded', reason = null where id = v_item.id;
      end if;
      perform hsf_compute_compliance(v_file_id);
    end if;
  end if;

  insert into bi_report_file_link (report_id, client_account_id, file_id, file_item_id, element_code, evidence_id, status)
  values (v_r.id, v_r.client_account_id, v_file_id, v_item.id, v_element, v_ev, v_status)
  on conflict (report_id) do update
     set file_id = excluded.file_id, file_item_id = excluded.file_item_id, element_code = excluded.element_code,
         evidence_id = excluded.evidence_id, status = excluded.status,
         attempts = bi_report_file_link.attempts + 1, synced_at = now();

  if v_status in ('linked','section_only') then
    update bi_report set section_f_synced_at = now() where id = v_r.id;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('bee-inspect', 'bi_report_filed_section_f',
            jsonb_build_object('report_id', v_r.id, 'element_code', v_element, 'status', v_status,
                               'evidence_version', v_version, 'sha256', v_r.pdf_sha256), v_file_id);
  end if;
  perform bi_audit(null, 'section_f_sync', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('status', v_status, 'file_id', v_file_id, 'element_code', v_element));
  return jsonb_build_object('report_id', v_r.id, 'status', v_status, 'file_id', v_file_id, 'element_code', v_element,
                            'evidence_id', v_ev, 'already', false);
end;
$$;
comment on function bi_hsf_section_f_sync is 'BI-RPT-01 (prompt B7, the hsf-section-f-sync function). Files an Issued report into the company''s current File: a new hsf_evidence version (engine_generated, the PDF fingerprint, supplied by "Bee-Inspect report signed by <name>") on the Section F element its template maps to, the item set to uploaded when it was outstanding or expired, compliance recomputed and audited in msp_audit against the File. Records section_only when the element is not on the File and no_file when there is no File yet (a later run retries). Idempotent. Runs automatically when a report becomes Issued.';

create function bi_transfer_package_store(p_report_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_id uuid;
begin
  select * into v_r from bi_report where id = p_report_id and status = 'issued';
  if v_r.id is null then
    raise exception 'Only an Issued report has a transfer package.' using errcode = 'P0002';
  end if;
  insert into bi_transfer_package (report_id, client_account_id, manifest, json_path, sha256)
  select v_r.id, v_r.client_account_id,
         jsonb_build_object('package_version', 'inspect_package_v1', 'report_id', v_r.id, 'issued_at', v_r.issued_at,
           'client_account_id', v_r.client_account_id, 'mco_company_ref', a.mco_company_ref,
           'site_id', i.site_id,
           'department_ids', (select coalesce(jsonb_agg(distinct b.department_id), '[]'::jsonb)
                                from bi_inspection_area ar join bi_room rm on rm.id = ar.room_id
                                join bi_building b on b.id = rm.building_id where ar.inspection_id = i.id),
           'pdf_path', v_r.pdf_path, 'pdf_sha256', v_r.pdf_sha256, 'json_path', v_r.json_path),
         v_r.json_path, v_r.pdf_sha256
    from bi_inspection i join msp_client_account a on a.id = i.client_account_id
   where i.id = v_r.inspection_id
  on conflict (report_id) do nothing
  returning id into v_id;
  return coalesce(v_id, (select id from bi_transfer_package where report_id = p_report_id));
end;
$$;
comment on function bi_transfer_package_store is 'BI-RPT-01 (prompt B9). Records the report package of an Issued report for MyClinicOnline, status supabase_stored. Idempotent. Runs automatically when a report becomes Issued.';

create function bi_report_after_issue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform bi_hsf_section_f_sync(new.id);
  perform bi_transfer_package_store(new.id);
  perform bi_audit(null, 'report_issued', new.tenant_id, new.client_account_id, 'report', new.id,
                   jsonb_build_object('version_id', new.issued_version_id, 'pdf_sha256', new.pdf_sha256));
  return null;
end;
$$;
create trigger bi_report_after_issue after update on bi_report
  for each row when (old.status is distinct from 'issued' and new.status = 'issued')
  execute function bi_report_after_issue();

-- 6. Report functions (service role; the Edge Functions verify the JWT first) ---------------------------

create function bi_report_save_draft(p_auth_user uuid, p_inspection_id uuid, p_content jsonb, p_source text, p_kernel_version_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_i bi_inspection;
  v_me bi_app_user;
  v_r bi_report;
  v_v int;
  v_vid uuid;
  v_counts jsonb;
  v_claims jsonb;
begin
  select * into v_i from bi_inspection where id = p_inspection_id;
  v_me := bi_app_user_of(p_auth_user);
  if v_i.id is null or v_me.id is null or not ('inspector' = any(bi_user_roles(p_auth_user, v_i.tenant_id, v_i.client_account_id))) then
    raise exception 'That inspection was not found.' using errcode = 'P0002';
  end if;
  if p_source not in ('template','ai_assistive') or p_content is null or jsonb_typeof(p_content) <> 'object' then
    raise exception 'bi_report_save_draft: content must be an object and the source template or ai_assistive' using errcode = '22023';
  end if;
  v_claims := bi_report_claim_problems(p_content);
  if jsonb_array_length(v_claims) > 0 then
    raise exception 'Every legal claim must carry a kernel reference (% claim(s) without one).', jsonb_array_length(v_claims)
      using errcode = '23514', detail = v_claims::text;
  end if;
  select * into v_r from bi_report where inspection_id = v_i.id for update;
  if v_r.id is null then
    insert into bi_report (inspection_id, tenant_id, client_account_id, title)
    values (v_i.id, v_i.tenant_id, v_i.client_account_id, v_i.title)
    returning * into v_r;
  elsif v_r.status in ('issued','withdrawn') then
    raise exception 'An Issued report is never edited.';
  end if;
  select coalesce(max(version), 0) + 1 into v_v from bi_report_version where report_id = v_r.id;
  v_counts := bi_report_voice_counts(v_i.id, p_content);
  insert into bi_report_version (report_id, version, content, draft_source, kernel_version_id, voice_notes_total, voice_notes_referenced, created_by)
  values (v_r.id, v_v, p_content, p_source, p_kernel_version_id, (v_counts ->> 'total')::int, (v_counts ->> 'accounted')::int, v_me.id)
  returning id into v_vid;
  -- A new version always goes back to Draft: a signature belongs to the version it signed.
  update bi_report set current_version_id = v_vid, status = 'draft' where id = v_r.id;
  perform bi_audit(p_auth_user, 'report_version_saved', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('version', v_v, 'source', p_source));
  return jsonb_build_object('report_id', v_r.id, 'version_id', v_vid, 'version', v_v, 'status', 'draft',
                            'voice_notes', v_counts, 'label', p_content ->> 'label');
end;
$$;
comment on function bi_report_save_draft is 'BI-RPT-01. Saves a new report version (template or AI assistive; an AI draft must carry the label) for an inspector of the company. Refuses claims without a kernel reference. Returns the voice note counts for the preview. Audited.';

create function bi_report_request_signoff(p_auth_user uuid, p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_i bi_inspection;
  v_counts jsonb;
begin
  select * into v_r from bi_report where id = p_report_id for update;
  if v_r.id is null or not ('inspector' = any(bi_user_roles(p_auth_user, v_r.tenant_id, v_r.client_account_id))) then
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  select * into v_i from bi_inspection where id = v_r.inspection_id;
  if v_i.status not in ('submitted','closed') then
    raise exception 'Submit the inspection before asking for sign off.';
  end if;
  v_counts := bi_report_voice_counts(v_i.id, (select content from bi_report_version where id = v_r.current_version_id));
  if v_i.voice_note_policy = 'strict' and (v_counts ->> 'missing')::int > 0 then
    raise exception 'Voice notes: % accounted for, % missing. The strict policy needs every voice note in the report.',
      v_counts ->> 'accounted', v_counts ->> 'missing';
  end if;
  update bi_report set status = 'awaiting_signoff' where id = v_r.id;
  perform bi_audit(p_auth_user, 'report_signoff_requested', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id, v_counts);
  return jsonb_build_object('report_id', v_r.id, 'status', 'awaiting_signoff', 'voice_notes', v_counts);
end;
$$;
comment on function bi_report_request_signoff is 'BI-RPT-01. Draft to Awaiting sign off, after the inspection is submitted; under the strict policy refused while a voice note is missing. Audited.';

create function bi_report_assign_reviewer(p_auth_user uuid, p_report_id uuid, p_reviewer_user_id uuid, p_engagement_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
begin
  select * into v_r from bi_report where id = p_report_id for update;
  if v_r.id is null or not (bi_user_is_ops(p_auth_user) or 'inspector' = any(bi_user_roles(p_auth_user, v_r.tenant_id, v_r.client_account_id))) then
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  if length(btrim(coalesce(p_engagement_ref, ''))) < 3 then
    raise exception 'A reviewer needs an engagement letter reference.';
  end if;
  update bi_report set reviewer_user_id = p_reviewer_user_id, reviewer_engagement_ref = btrim(p_engagement_ref) where id = v_r.id;
  perform bi_audit(p_auth_user, 'report_reviewer_assigned', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('reviewer_user_id', p_reviewer_user_id, 'engagement_ref', p_engagement_ref));
  return jsonb_build_object('report_id', v_r.id, 'reviewer_user_id', p_reviewer_user_id);
end;
$$;
comment on function bi_report_assign_reviewer is 'BI-RPT-01 (prompt B7). When the inspector is not cleared for the scope: records the competent person engaged through Bee-Matched ({{bee_matched_url}}; WhatsApp a sales executive until it is live) and the engagement letter reference. Audited.';

create function bi_report_sign(p_auth_user uuid, p_report_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_me bi_app_user;
  v_step bi_step_up;
  v_role text;
  v_cat text;
  v_channel text := coalesce(p ->> 'channel', 'in_app');
  v_integrity text := coalesce(p ->> 'device_integrity', 'unknown');
  v_window int;
  v_id uuid;
begin
  select * into v_r from bi_report where id = p_report_id for update;
  v_me := bi_app_user_of(p_auth_user);
  if v_r.id is null or v_me.id is null then
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  if v_r.reviewer_user_id = v_me.id then
    v_role := 'reviewer';
  elsif 'inspector' = any(bi_user_roles(p_auth_user, v_r.tenant_id, v_r.client_account_id)) then
    v_role := 'inspector';
  else
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  if v_r.status <> 'awaiting_signoff' then
    raise exception 'Only a report Awaiting sign off is signed.';
  end if;
  if v_integrity = 'compromised' then
    raise exception 'This device looks rooted or jailbroken, so it cannot sign. Please sign on another device.' using errcode = '42501';
  end if;
  if coalesce((p ->> 'confirm_photos')::boolean, false) is false or coalesce((p ->> 'confirm_voice_notes')::boolean, false) is false then
    raise exception 'Confirm that you reviewed the photos and the voice notes before signing.';
  end if;
  select t.category into v_cat from bi_inspection i join bi_template t on t.id = i.template_id where i.id = v_r.inspection_id;
  if not bi_signer_cleared(v_me.id, v_cat) then
    raise exception 'You are not cleared to sign % reports. Find a competent person through Bee-Matched.', v_cat using errcode = '42501';
  end if;
  select * into v_step from bi_step_up where id = nullif(p ->> 'step_up_id', '')::uuid for update;
  v_window := case when v_channel = 'docuseal' then 1440 else coalesce(msp_env_get_int('bi.step_up_window_minutes'), 10) end;
  if v_step.id is null or v_step.auth_user_id <> p_auth_user or v_step.purpose <> 'signoff' or v_step.consumed_at is not null
     or v_step.asserted_at < now() - make_interval(mins => v_window) then
    raise exception 'Verify your second factor again before signing.' using errcode = '28000';
  end if;
  update bi_step_up set consumed_at = now() where id = v_step.id;
  insert into bi_signature (report_id, report_version_id, signer_user_id, signer_role, channel, docuseal_submission_ref, step_up_id,
                            device_integrity, confirmed_photos, confirmed_voice_notes, qualification_ids)
  values (v_r.id, v_r.current_version_id, v_me.id, v_role, v_channel, nullif(p ->> 'docuseal_submission_ref', ''), v_step.id,
          v_integrity, true, true,
          coalesce((select array_agg(q.id) from bi_inspector_qualification q where q.app_user_id = v_me.id and q.status = 'verified'), '{}'))
  returning id into v_id;
  perform bi_audit(p_auth_user, 'report_signed', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('signature_id', v_id, 'role', v_role, 'channel', v_channel, 'version_id', v_r.current_version_id));
  return jsonb_build_object('report_id', v_r.id, 'signature_id', v_id, 'status', v_r.status);
end;
$$;
comment on function bi_report_sign is 'BI-RPT-01 (prompt B3, B7). Records a competent person''s signature on the current version of a report Awaiting sign off: the company''s inspector or the engaged reviewer, cleared for the template category, on a device that is not rooted or jailbroken, having confirmed the photos and voice notes, with an unconsumed step up assertion (purpose signoff) recorded within bi.step_up_window_minutes (24 hours for DocuSeal), which it consumes. Does not issue: issuing needs the PDF (bi_report_issue). Audited.';

create function bi_report_issue(p_report_id uuid, p_pdf_path text, p_pdf_sha256 text, p_json_path text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link jsonb;
begin
  update bi_report set status = 'issued', pdf_path = p_pdf_path, pdf_sha256 = p_pdf_sha256, json_path = p_json_path
   where id = p_report_id;
  if not found then
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  select to_jsonb(l) into v_link from bi_report_file_link l where l.report_id = p_report_id;
  return jsonb_build_object('report_id', p_report_id, 'status', 'issued', 'section_f', v_link);
end;
$$;
comment on function bi_report_issue is 'BI-RPT-01 (prompt B7). Called by the renderer once the PDF and JSON are stored: moves the report to Issued, which the guard allows only with a valid signature, and which files it into Section F and records its transfer package. Service role only.';

create function bi_report_withdraw(p_auth_user uuid, p_report_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_link bi_report_file_link;
begin
  if not bi_user_is_ops(p_auth_user) then
    raise exception 'Only Care Net withdraws an Issued report.' using errcode = '42501';
  end if;
  select * into v_r from bi_report where id = p_report_id for update;
  update bi_report set status = 'withdrawn', withdrawn_reason = p_reason, share_token_hash = null, share_expires_at = null
   where id = p_report_id and status = 'issued';
  if not found then
    raise exception 'Only an Issued report is withdrawn.' using errcode = 'P0002';
  end if;
  select * into v_link from bi_report_file_link where report_id = p_report_id for update;
  if v_link.status = 'linked' then
    update hsf_evidence set revoked_at = now() where id = v_link.evidence_id and revoked_at is null;
    if not exists (select 1 from hsf_evidence e where e.file_item_id = v_link.file_item_id and e.revoked_at is null) then
      update hsf_file_item set status = 'outstanding' where id = v_link.file_item_id and status = 'uploaded';
    end if;
    perform hsf_compute_compliance(v_link.file_id);
  end if;
  if v_link.report_id is not null then
    update bi_report_file_link set status = 'revoked', synced_at = now() where report_id = p_report_id;
  end if;
  perform bi_audit(p_auth_user, 'report_withdrawn', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('reason', p_reason));
  return jsonb_build_object('report_id', p_report_id, 'status', 'withdrawn');
end;
$$;
comment on function bi_report_withdraw is 'BI-RPT-01. Care Net withdraws an Issued report with a reason: its share link stops, its Section F evidence is revoked and the item returns to outstanding when nothing else holds it. Audited.';

create function bi_report_share_create(p_auth_user uuid, p_report_id uuid, p_days int default 14)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_until timestamptz := now() + make_interval(days => greatest(1, least(coalesce(p_days, 14), 30)));
begin
  select * into v_r from bi_report where id = p_report_id for update;
  if v_r.id is null or v_r.status <> 'issued'
     or not (bi_user_roles(p_auth_user, v_r.tenant_id, v_r.client_account_id) && array['inspector','company_admin']) then
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  update bi_report set share_token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'), share_expires_at = v_until where id = v_r.id;
  perform bi_audit(p_auth_user, 'report_share_created', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('expires_at', v_until));
  return jsonb_build_object('report_id', v_r.id, 'token', v_token, 'expires_at', v_until);
end;
$$;
comment on function bi_report_share_create is 'BI-RPT-01 (prompt B7). A secure share link for an Issued report: a random token shown once (only its SHA 256 is kept), valid 1 to 30 days (default 14). A new link replaces the old one. Audited.';

create function bi_section_f_reports(p_auth_user uuid, p_file_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'report_id', r.id, 'title', r.title, 'site', s.name, 'date', r.issued_at,
           'signed_by', (select u.display_name from bi_signature g join bi_app_user u on u.id = g.signer_user_id
                          where g.report_id = r.id and g.report_version_id = r.issued_version_id order by g.signed_at desc limit 1),
           'status', r.status, 'element_code', l.element_code, 'filing', l.status)
         order by r.issued_at desc), '[]'::jsonb)
    from bi_report_file_link l
    join bi_report r on r.id = l.report_id
    join bi_inspection i on i.id = r.inspection_id
    join bi_site s on s.id = i.site_id
   where l.file_id = p_file_id and l.status in ('linked','section_only')
     and hsf_can_access_file(p_auth_user, p_file_id);
$$;
comment on function bi_section_f_reports is 'BI-RPT-01 (prompt A3). The Section F "Inspection reports" list of a File for its owner or staff: title, site, date, signed by, status. Service role only (the File site''s API calls it after verifying the user).';

create function bi_hsf_section_f_sync_pending(p_limit int default 25)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_out jsonb := '[]'::jsonb;
begin
  for r in
    select b.id from bi_report b left join bi_report_file_link l on l.report_id = b.id
     where b.status = 'issued' and (l.report_id is null or l.status = 'no_file')
     order by b.issued_at limit greatest(1, least(coalesce(p_limit, 25), 200))
  loop
    v_out := v_out || jsonb_build_array(bi_hsf_section_f_sync(r.id));
  end loop;
  return jsonb_build_object('processed', jsonb_array_length(v_out), 'results', v_out);
end;
$$;
comment on function bi_hsf_section_f_sync_pending is 'BI-RPT-01. For the hsf-section-f-sync Edge Function: retries every Issued report not yet filed (no link, or no File at the last attempt). Service role only.';

-- 7. Row Level Security -------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['bi_kernel_version','bi_kernel_doc','bi_kernel_chunk','bi_report','bi_report_version','bi_signature',
                           'bi_report_file_link','bi_transfer_package'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;
grant select on bi_kernel_version, bi_kernel_doc, bi_kernel_chunk, bi_report, bi_report_version, bi_signature, bi_report_file_link to authenticated;

create function bi_can_read_report(p_report_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from bi_report r
                  where r.id = p_report_id
                    and (bi_can(r.tenant_id, r.client_account_id, case when r.status = 'issued' then 'read_report_issued' else 'read_report_draft' end)
                         or (r.reviewer_user_id is not null and r.reviewer_user_id = bi_my_app_user_id())));
$$;
comment on function bi_can_read_report is 'BI-RPT-01. RLS helper: Issued reports for ops, inspectors, assistants and company admins of the company in the tenant; drafts for ops, inspectors and company admins; and the engaged reviewer.';
revoke execute on function bi_can_read_report(uuid) from public, anon;
grant execute on function bi_can_read_report(uuid) to authenticated, service_role;

create policy bi_kernel_version_read on bi_kernel_version for select to authenticated using (status = 'released' or bi_is_ops());
create policy bi_kernel_doc_read on bi_kernel_doc for select to authenticated
  using (bi_is_ops() or tenant_id is null or tenant_id = bi_my_tenant());
create policy bi_kernel_chunk_read on bi_kernel_chunk for select to authenticated
  using (exists (select 1 from bi_kernel_doc d where d.id = doc_id and (bi_is_ops() or d.tenant_id is null or d.tenant_id = bi_my_tenant())));
create policy bi_report_read on bi_report for select to authenticated using (bi_can_read_report(id));
create policy bi_report_version_read on bi_report_version for select to authenticated using (bi_can_read_report(report_id));
create policy bi_signature_read on bi_signature for select to authenticated using (bi_can_read_report(report_id));
create policy bi_report_file_link_read on bi_report_file_link for select to authenticated
  using (bi_can_read_report(report_id) or (file_id is not null and hsf_can_read_file(file_id)));
-- bi_transfer_package: no authenticated policy (server side and ops through functions).

do $$
declare
  f text;
begin
  foreach f in array array['bi_kernel_ref_exists(text)','bi_report_claim_problems(jsonb)','bi_report_voice_counts(uuid, jsonb)',
                           'bi_signer_cleared(uuid, text)','bi_hsf_section_f_sync(uuid)','bi_transfer_package_store(uuid)',
                           'bi_report_save_draft(uuid, uuid, jsonb, text, uuid)','bi_report_request_signoff(uuid, uuid)',
                           'bi_report_assign_reviewer(uuid, uuid, uuid, text)','bi_report_sign(uuid, uuid, jsonb)',
                           'bi_report_issue(uuid, text, text, text)','bi_report_withdraw(uuid, uuid, text)',
                           'bi_report_share_create(uuid, uuid, int)','bi_section_f_reports(uuid, uuid)',
                           'bi_hsf_section_f_sync_pending(int)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array['bi_report_guard()','bi_report_touch()','bi_transfer_package_guard()','bi_report_after_issue()'] loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
