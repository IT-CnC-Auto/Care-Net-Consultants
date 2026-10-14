-- CNC MSP FORGE | DOC-GEN-02 v1.0.0 | Plans rendered on the server 14/10/2026
-- IT gap analysis CNC-IT-MSP-019 item B: the Plan was rendered by IT on a desktop
-- (factory/render_pack.js plus Word) and mailed by hand. The release email (item E)
-- attaches the Plan, so it has to exist on the server, per reference.
--
-- This migration:
--   1. private storage buckets msp-factory (the brand images the renderer needs, seeded
--      from the repository at a pinned commit) and msp-plans (the rendered Plans);
--   2. msp_document gains reference, plan_id, marked, file_name, bytes, sha256 and
--      source, so each rendered file is traceable to the drafting run it came from;
--   3. msp_plan_render_input(reference): one drafting run (all six stages written by the
--      same msp_pipeline_persist call), the practitioner sign off record, the next
--      version number and the PDF settings. Only a run whose checks passed renders.
--   4. msp_plan_render_record: records a rendered DOCX or PDF;
--   5. msp_plan_render_call / msp_plan_render_kick: call the msp-plan-render edge
--      function with the worker key from Vault (kick: forge_admin or the SQL editor);
--   6. settings integration.msp_render_url, integration.msp_pdf_site (pending until a
--      SharePoint site is granted to the mail app with Sites.Selected) and
--      integration.msp_pdf_folder.
-- The PLANNING ONLY marking is decided inside the renderer from msp_plan_signoff,
-- read straight from the database: no caller can ask for an unmarked Plan.

-- 1. Buckets -----------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('msp-factory', 'msp-factory', false, 2097152, array['image/png', 'application/json']),
  ('msp-plans', 'msp-plans', false, 15728640,
   array['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/pdf'])
on conflict (id) do nothing;
-- No storage policies: only the service role (the edge function) reads or writes them.

-- 2. The document record ---------------------------------------------------------------
alter table msp_document add column if not exists reference text;
alter table msp_document add column if not exists plan_id uuid;
alter table msp_document add column if not exists marked boolean;
alter table msp_document add column if not exists file_name text;
alter table msp_document add column if not exists bytes int;
alter table msp_document add column if not exists sha256 text;
alter table msp_document add column if not exists source text;
comment on column msp_document.plan_id is 'The compose draft (msp_draft.id) the file was rendered from.';
comment on column msp_document.marked is 'True when every page carries the PLANNING ONLY marking (no practitioner approval and signature on record at render time).';

-- 3. Settings ----------------------------------------------------------------------------
insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('integration.msp_render_url', 'https://pboebfnujzffgwctsplw.supabase.co/functions/v1/msp-plan-render', 'text', null, null, 'integration',
   'Address of the msp-plan-render edge function.'),
  ('integration.msp_pdf_site', 'pending', 'text', null, null, 'integration',
   'SharePoint site used to convert the Plan to PDF (site id, or hostname:/sites/path). Pending until the site is granted to the mail app with Sites.Selected; until then only the DOCX is produced.'),
  ('integration.msp_pdf_folder', 'MSP Plan rendering', 'text', null, null, 'integration',
   'Folder in that site''s document library where a Plan is placed for conversion and deleted straight after.')
on conflict (key) do nothing;

insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
select k, null, v, 'migration_073', 'Plans rendered on the server (item B)'
  from (values ('integration.msp_render_url', 'https://pboebfnujzffgwctsplw.supabase.co/functions/v1/msp-plan-render'),
               ('integration.msp_pdf_site', 'pending'), ('integration.msp_pdf_folder', 'MSP Plan rendering')) as x(k, v)
 where not exists (select 1 from msp_env_parameter_history h where h.key = x.k);

-- 4. What the renderer needs ---------------------------------------------------------------
create or replace function msp_plan_render_input(p_reference text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eng msp_engagement%rowtype;
  v_compose msp_draft%rowtype;
  v_run jsonb;
  v_passed boolean;
begin
  select * into v_eng from msp_engagement where reference = p_reference;
  if v_eng.id is null then raise exception 'no engagement %', p_reference; end if;
  select * into v_compose from msp_draft where engagement_id = v_eng.id and stage = 'compose'
   order by created_at desc limit 1;
  if v_compose.id is null then raise exception 'engagement % has no drafted Plan', p_reference; end if;
  -- One drafting run: msp_pipeline_persist writes all six stages in one transaction.
  select jsonb_object_agg(d.stage, d.stage_output) into v_run
    from msp_draft d where d.engagement_id = v_eng.id and d.created_at = v_compose.created_at;
  v_passed := coalesce((v_run #>> '{validate,passed}')::boolean, false);
  if not v_passed then
    raise exception 'the latest Plan for % did not pass its checks; correct and redraft it first', p_reference;
  end if;
  return jsonb_build_object(
    'reference', v_eng.reference, 'status', v_eng.status, 'plan_id', v_compose.id, 'drafted_at', v_compose.created_at,
    'draft', jsonb_build_object('classification', v_run->'classify', 'framed', v_run->'frame', 'profile', v_run->'profile',
                                'prescribed', v_run->'prescribe', 'composed', v_run->'compose', 'validation', v_run->'validate'),
    'signoff', msp_plan_signoff(p_reference),
    'version', 1 + (select count(*) from msp_document x where x.engagement_id = v_eng.id and x.artefact_kind = 'docx'),
    'settings', jsonb_build_object('pdf_site', msp_env_get('integration.msp_pdf_site'),
                                   'pdf_folder', msp_env_get('integration.msp_pdf_folder')));
end;
$$;
revoke execute on function msp_plan_render_input(text) from public, anon, authenticated;
comment on function msp_plan_render_input is 'Server side only: the latest drafting run of a Plan (checks passed), its practitioner sign off record, the next version number and the PDF settings.';

-- 5. The record of a rendered file -------------------------------------------------------------
create or replace function msp_plan_render_record(p_reference text, p_plan_id uuid, p_kind text, p_path text, p_version int,
                                                  p_marked boolean, p_file_name text, p_bytes int, p_sha256 text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng uuid;
  v_id uuid;
begin
  select id into v_eng from msp_engagement where reference = p_reference;
  if v_eng is null then raise exception 'no engagement %', p_reference; end if;
  insert into msp_document (engagement_id, artefact_kind, storage_path, version, reference, plan_id, marked, file_name, bytes, sha256, source)
  values (v_eng, p_kind, p_path, p_version, p_reference, p_plan_id, p_marked, p_file_name, p_bytes, p_sha256, 'msp-plan-render')
  returning id into v_id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'msp-plan-render', 'plan_rendered',
          jsonb_build_object('document_id', v_id, 'kind', p_kind, 'version', p_version, 'marked', p_marked,
                             'plan_id', p_plan_id, 'bytes', p_bytes, 'sha256', p_sha256));
  return v_id;
end;
$$;
revoke execute on function msp_plan_render_record(text, uuid, text, text, int, boolean, text, int, text) from public, anon, authenticated;

-- 6. Calling the renderer ------------------------------------------------------------------------
create or replace function msp_plan_render_call(p_reference text, p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := (select decrypted_secret from vault.decrypted_secrets where name = 'msp_worker_key');
begin
  if v_key is null then raise exception 'worker key missing from Vault'; end if;
  return net.http_post(
    url := msp_env_get('integration.msp_render_url'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-msp-worker-key', v_key),
    body := coalesce(p_body, '{}'::jsonb) || jsonb_build_object('reference', p_reference),
    timeout_milliseconds := 120000);
end;
$$;
revoke execute on function msp_plan_render_call(text, jsonb) from public, anon, authenticated;

create or replace function msp_plan_render_kick(p_reference text, p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (msp_caller_is('forge_admin') or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'rendering a Plan requires the forge_admin role';
  end if;
  perform msp_plan_render_input(p_reference);  -- fails early, with the reason, for a Plan that cannot render
  return jsonb_build_object('reference', p_reference,
    'request_id', msp_plan_render_call(p_reference, jsonb_build_object('dry_run', coalesce(p_dry_run, false))));
end;
$$;
revoke execute on function msp_plan_render_kick(text, boolean) from public, anon;
grant execute on function msp_plan_render_kick(text, boolean) to authenticated;
comment on function msp_plan_render_kick is 'forge_admin or the SQL editor: render the latest Plan of a reference to DOCX (and PDF once a SharePoint site is granted), stored in msp-plans and recorded in msp_document. The result lands in net._http_response under the returned request id.';

notify pgrst, 'reload schema';
