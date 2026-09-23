-- CNC MSP FORGE | HSF-GEN-01 v1.0.0 | HSF skeleton generation, compliance and the client read paths 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 3 (051) and SPEC.md Part B, B9.3 and B9.4.
--
-- What this migration does:
--   1. hsf_trigger_applies: the trigger rule of hsf/build_samples.py (U, compound
--      "A and B" and "A or B", plain codes).
--   2. hsf_generate_file: writes the skeleton of a File (hsf_file, draft,
--      revision 1, and one outstanding hsf_file_item per applicable element).
--      Generating a skeleton holds no documents, so no consent is needed for it;
--      consent is needed for uploads only (049).
--   3. hsf_compute_compliance (SPEC B9.4): linked_mco or uploaded over every
--      item not marked not applicable, per section and overall; the overall is
--      the ratio across all items, not a mean of sections. Cached on hsf_file.
--   4. hsf_my_files, hsf_file_detail and hsf_set_item_status for the web tier.
--
-- All functions are security definer with a fixed search path and executable by
-- the service role only. The web tier verifies the person's access token and
-- passes their auth user id. Every write is audited in msp_audit with the File.
--
-- Not built in this release (open, see the build report): per appointment, per
-- course, per licence class, per examination class and per site expansion of
-- items (B9.3.4), and the MCO and MSP evidence pass (B9.3.6). One item is written
-- per element, with site_ref null.

-- 1. Parameter (SPEC B9.4) --------------------------------------------------------------

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description, updated_by) values
  ('hsf.compliance_scope', 'true', 'boolean', null, null, 'hsf',
   'SPEC B9.4. true: an item marked not applicable (with its written reason) leaves the denominator of the compliance figure. false: it counts against the File.',
   'migration_051')
on conflict (key) do nothing;

-- 2. Helpers --------------------------------------------------------------------------------

create or replace function hsf_trigger_applies(p_trigger text, p_raised text[])
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  t text := btrim(coalesce(p_trigger, ''));
  v_raised text[] := coalesce(p_raised, '{}'::text[]);
begin
  if t = '' or t = 'U' or t like 'Per %' then
    return true;
  end if;
  if t like '% and %' then
    return (select bool_and(btrim(x) = any(v_raised)) from unnest(string_to_array(t, ' and ')) x);
  end if;
  if t like '% or %' then
    return (select bool_or(btrim(x) = any(v_raised)) from unnest(string_to_array(t, ' or ')) x);
  end if;
  return t = any(v_raised);
end;
$$;
comment on function hsf_trigger_applies is 'The trigger rule of hsf/build_samples.py: null, U or Per ... always applies; A and B needs every code raised; A or B needs one; a plain code needs itself.';

create or replace function hsf_user_is_staff(p_auth_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- The web tier passes the verified auth user id; staff roles live in the user's
  -- app metadata (msp_roles), the same claim msp_has_role reads from the JWT.
  select coalesce((select (to_jsonb(u) -> 'raw_app_meta_data' -> 'msp_roles')
                            ?| array['forge_admin','forge_omp','forge_safety_reviewer']
                     from auth.users u where u.id = p_auth_user), false);
$$;
comment on function hsf_user_is_staff is 'True when the auth user carries forge_admin, forge_omp or forge_safety_reviewer in app_metadata.msp_roles.';

create or replace function hsf_can_access_file(p_auth_user uuid, p_file_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_auth_user is not null
     and (exists (select 1 from hsf_file f join msp_client_account a on a.id = f.client_account_id
                   where f.id = p_file_id and a.auth_user_id = p_auth_user)
          or (hsf_user_is_staff(p_auth_user) and exists (select 1 from hsf_file f where f.id = p_file_id)));
$$;
comment on function hsf_can_access_file is 'The owning client account''s contact, or staff.';

-- The figures only, without writing the cache: used by the read paths.
create or replace function hsf_compliance_figures(p_file_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with scope as (
    select coalesce(msp_env_get_bool('hsf.compliance_scope'), true) as na_leaves
  ),
  items as (
    select e.section_code, fi.status
      from hsf_file_item fi join hsf_element e on e.id = fi.element_id
     where fi.file_id = p_file_id
  ),
  per_section as (
    select s.code, s.name, s.ordinal,
           count(i.status) as items,
           count(i.status) filter (where i.status <> 'not_applicable' or not sc.na_leaves) as applicable,
           count(i.status) filter (where i.status in ('linked_mco','uploaded')) as evidenced
      from hsf_section s
      cross join scope sc
      left join items i on i.section_code = s.code
     group by s.code, s.name, s.ordinal
  ),
  overall as (
    select sum(items)::int as items, sum(applicable)::int as applicable, sum(evidenced)::int as evidenced
      from per_section
  )
  select jsonb_build_object(
    'file_id', p_file_id,
    'overall', jsonb_build_object(
      'pct', case when o.applicable > 0 then round(100.0 * o.evidenced / o.applicable, 1) end,
      'items', o.items, 'applicable', o.applicable, 'evidenced', o.evidenced,
      'counts', coalesce((select jsonb_object_agg(c.status, c.n)
                            from (select status, count(*) as n from items group by status) c), '{}'::jsonb)),
    'sections', (select jsonb_agg(jsonb_build_object(
                          'code', p.code, 'name', p.name, 'items', p.items, 'applicable', p.applicable,
                          'evidenced', p.evidenced,
                          'compliance_pct', case when p.applicable > 0 then round(100.0 * p.evidenced / p.applicable, 1) end)
                        order by p.ordinal)
                   from per_section p))
    from overall o;
$$;
comment on function hsf_compliance_figures is 'SPEC B9.4 figures for a File without writing the cache: per section and overall, linked_mco or uploaded over every item not marked not applicable (hsf.compliance_scope). A section with nothing applicable has a null figure.';

do $$
declare
  f text;
begin
  foreach f in array array['hsf_trigger_applies(text, text[])','hsf_user_is_staff(uuid)',
                           'hsf_can_access_file(uuid, uuid)','hsf_compliance_figures(uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- 3. Compliance (cached) ---------------------------------------------------------------------

create or replace function hsf_compute_compliance(p_file_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old numeric;
  v_fig jsonb;
  v_pct numeric;
begin
  select f.compliance_pct into v_old from hsf_file f where f.id = p_file_id for update;
  if not found then
    raise exception 'That File was not found.';
  end if;
  v_fig := hsf_compliance_figures(p_file_id);
  v_pct := (v_fig -> 'overall' ->> 'pct')::numeric;
  if v_pct is distinct from v_old then
    update hsf_file set compliance_pct = v_pct where id = p_file_id;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-engine', 'hsf_compliance_computed',
            jsonb_build_object('from', v_old, 'to', v_pct, 'overall', v_fig -> 'overall'), p_file_id);
  end if;
  return v_fig;
end;
$$;
comment on function hsf_compute_compliance is 'SPEC B9.4. Computes the compliance figures of a File and caches the overall figure on hsf_file.compliance_pct. A change of the cached figure is audited.';

-- 4. Generation (SPEC B9.3) ------------------------------------------------------------------

create or replace function hsf_generate_file(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ind msp_industry;
  v_sub msp_subindustry;
  v_regime text;
  v_triggers text[];
  v_bad text;
  v_scope jsonb;
  v_site jsonb;
  v_file_id uuid;
  v_reference text;
  v_items int;
  v_headcount text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'The File details are missing.';
  end if;
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before building a File.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot build a File. Please WhatsApp a sales executive.';
  end if;

  select i.* into v_ind from msp_industry i where i.code = upper(btrim(coalesce(p ->> 'industry_code', '')));
  if v_ind.id is null then
    raise exception 'Choose your industry.';
  end if;
  if nullif(btrim(coalesce(p ->> 'subindustry_code', '')), '') is not null then
    select s.* into v_sub from msp_subindustry s
     where s.code = upper(btrim(p ->> 'subindustry_code')) and s.industry_id = v_ind.id;
    if v_sub.id is null then
      raise exception 'The subindustry is not part of the chosen industry.';
    end if;
  end if;

  -- Triggers: every code must be in the SPEC B9.2 vocabulary (or U).
  if p ? 'triggers' and jsonb_typeof(p -> 'triggers') not in ('array','null') then
    raise exception 'Activities must be a list of trigger codes.';
  end if;
  select coalesce(array_agg(distinct t order by t), '{}'::text[]) into v_triggers
    from jsonb_array_elements_text(case when jsonb_typeof(p -> 'triggers') = 'array' then p -> 'triggers' else '[]'::jsonb end) t;
  select string_agg(t, ', ' order by t) into v_bad
    from unnest(v_triggers) t
   where t <> 'U' and not exists (select 1 from hsf_trigger g where g.code = t and g.code !~ ' (and|or) ');
  if v_bad is not null then
    raise exception 'Unknown activity code: %', v_bad;
  end if;

  -- RULE-HSF-REGIME: a mine is under the Mine Health and Safety Act, every other
  -- industry under the OHS Act. The mine regime is a kernel fact and raises T-MINING.
  v_regime := case when v_ind.code = 'MINING' then 'MHSA' else 'OHSA' end;
  if v_regime = 'MHSA' and not ('T-MINING' = any(v_triggers)) then
    v_triggers := array_append(v_triggers, 'T-MINING');
  end if;

  -- Scope: at least one site with a name.
  if jsonb_typeof(p -> 'scope') <> 'object' or jsonb_typeof(p -> 'scope' -> 'sites') <> 'array'
     or jsonb_array_length(p -> 'scope' -> 'sites') < 1 then
    raise exception 'Tell us which sites the File covers.';
  end if;
  for v_site in select value from jsonb_array_elements(p -> 'scope' -> 'sites') loop
    if jsonb_typeof(v_site) <> 'object' or length(btrim(coalesce(v_site ->> 'name', ''))) not between 1 and 200 then
      raise exception 'Every site needs a name of up to 200 characters.';
    end if;
  end loop;
  v_headcount := p -> 'scope' ->> 'headcount';
  if v_headcount is not null and v_headcount !~ '^[0-9]{1,7}$' then
    raise exception 'The headcount must be a whole number.';
  end if;
  v_scope := jsonb_strip_nulls(jsonb_build_object(
    'sites', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                       'name', btrim(s ->> 'name'),
                       'address', nullif(btrim(coalesce(s ->> 'address', '')), ''))))
                from jsonb_array_elements(p -> 'scope' -> 'sites') s),
    'project_reference', nullif(btrim(coalesce(p -> 'scope' ->> 'project_reference', '')), ''),
    'headcount', v_headcount::int,
    'triggers', to_jsonb(v_triggers)));

  insert into hsf_file (client_account_id, industry_id, subindustry_id, regime, scope, revision, status)
  values (v_acc.id, v_ind.id, v_sub.id, v_regime, v_scope, 1, 'draft')
  returning id, reference into v_file_id, v_reference;

  -- B9.3.2 and B9.3.3: universal elements whose trigger is raised, the industry
  -- overlay (and the universal elements the overlay makes mandatory), filtered
  -- to the regime; under the MHSA an element with an MHSA equivalent is swapped.
  insert into hsf_file_item (file_id, element_id, status)
  select distinct v_file_id,
         case when v_regime = 'MHSA' and e.mhsa_equivalent_id is not null then e.mhsa_equivalent_id else e.id end,
         'outstanding'
    from hsf_element e
   where e.status = 'active'
     and e.regime in ('BOTH', v_regime)
     and ((e.universal and hsf_trigger_applies(e.trigger_code, v_triggers))
          or exists (select 1 from hsf_element_industry x
                      where x.element_id = e.id
                        and x.industry_id = v_ind.id
                        and (x.subindustry_id is null or x.subindustry_id = v_sub.id)
                        and x.applicability = 'mandatory'));
  get diagnostics v_items = row_count;

  perform hsf_compute_compliance(v_file_id);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_file_generated',
          jsonb_build_object('reference', v_reference, 'industry_code', v_ind.code, 'subindustry_code', v_sub.code,
                             'regime', v_regime, 'triggers', to_jsonb(v_triggers), 'items', v_items),
          v_file_id);

  return jsonb_build_object('file_id', v_file_id, 'reference', v_reference, 'regime', v_regime, 'items', v_items);
end;
$$;
comment on function hsf_generate_file is 'Contract 051 and SPEC B9.3. Writes a draft File (revision 1) with one outstanding item per applicable element: universal elements whose trigger applies, the industry overlay, the regime filter (MHSA for MINING, else OHSA). No consent needed: the skeleton holds no documents. Audited.';

-- 5. Read paths ---------------------------------------------------------------------------------

create or replace function hsf_my_files(p_auth_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'file_id', f.id,
           'reference', f.reference,
           'industry_code', i.code,
           'industry_name', i.name,
           'regime', f.regime,
           'status', f.status,
           'revision', f.revision,
           'compliance_pct', (hsf_compliance_figures(f.id) -> 'overall' ->> 'pct')::numeric,
           'created_at', f.created_at)
         order by f.created_at desc, f.reference desc), '[]'::jsonb)
    from hsf_file f
    join msp_client_account a on a.id = f.client_account_id
    join msp_industry i on i.id = f.industry_id
   where p_auth_user is not null and a.auth_user_id = p_auth_user;
$$;
comment on function hsf_my_files is 'Contract 051. The Files of the auth user''s company account, newest first, with the compliance figure computed live.';

create or replace function hsf_file_detail(p_auth_user uuid, p_file_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_fig jsonb;
  v_file jsonb;
  v_sections jsonb;
begin
  if not hsf_can_access_file(p_auth_user, p_file_id) then
    raise exception 'That File was not found.';
  end if;
  v_fig := hsf_compliance_figures(p_file_id);

  select jsonb_build_object(
           'id', f.id, 'file_id', f.id, 'reference', f.reference,
           'company_name', a.company_name,
           'industry_code', i.code, 'industry_name', i.name,
           'subindustry_code', s.code, 'subindustry_name', s.name,
           'regime', f.regime, 'scope', f.scope, 'status', f.status, 'revision', f.revision,
           'compliance_pct', (v_fig -> 'overall' ->> 'pct')::numeric, 'created_at', f.created_at)
    into v_file
    from hsf_file f
    join msp_client_account a on a.id = f.client_account_id
    join msp_industry i on i.id = f.industry_id
    left join msp_subindustry s on s.id = f.subindustry_id
   where f.id = p_file_id;

  select jsonb_agg(jsonb_build_object(
           'code', sec.code,
           'name', sec.name,
           'compliance_pct', (select (x ->> 'compliance_pct')::numeric
                                from jsonb_array_elements(v_fig -> 'sections') x where x ->> 'code' = sec.code),
           'items', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'item_id', fi.id,
                      'element_code', e.code,
                      'name', e.name,
                      'duty', e.duty,
                      'evidence_type', e.evidence_type,
                      'review_interval', e.review_interval,
                      'status', fi.status,
                      'reason', fi.reason,
                      'responsible_person', coalesce(fi.responsible_person, e.responsible_role, apt.name),
                      'due_date', fi.due_date,
                      'site_ref', fi.site_ref,
                      'citable', coalesce(to_jsonb(l.citable), '[]'::jsonb),
                      'awaiting', coalesce(to_jsonb(l.awaiting), '[]'::jsonb),
                      'uploads', coalesce((
                        select jsonb_agg(jsonb_build_object(
                                 'upload_id', u.id, 'original_name', u.original_name, 'status', u.status,
                                 'department_code', u.department_code, 'created_at', u.created_at)
                               order by u.created_at desc, u.id)
                          from hsf_upload u where u.file_item_id = fi.id), '[]'::jsonb))
                    order by e.code, fi.site_ref nulls first)
               from hsf_file_item fi
               join hsf_element e on e.id = fi.element_id
               left join hsf_appointment_type apt on apt.code = e.responsible_appointment
               left join hsf_public_element_library l on l.code = e.code
              where fi.file_id = p_file_id and e.section_code = sec.code), '[]'::jsonb))
         order by sec.ordinal)
    into v_sections
    from hsf_section sec;

  return jsonb_build_object('file', v_file, 'sections', v_sections, 'overall', v_fig -> 'overall');
end;
$$;
comment on function hsf_file_detail is 'Contract 051. The File, its fifteen sections with their items (basis: citable short names and awaiting candidates; uploads) and the overall figure. The owning client account or staff only.';

create or replace function hsf_set_item_status(p_auth_user uuid, p_item_id uuid, p_status text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item hsf_file_item;
  v_reason text := nullif(btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g')), '');
  v_fig jsonb;
begin
  select fi.* into v_item from hsf_file_item fi where fi.id = p_item_id for update;
  if v_item.id is null or not hsf_can_access_file(p_auth_user, v_item.file_id) then
    raise exception 'That File item was not found.';
  end if;
  if p_status is null or p_status not in ('not_applicable','outstanding') then
    raise exception 'The status must be not_applicable or outstanding.';
  end if;
  if p_status = 'not_applicable' then
    if v_reason is null or length(v_reason) < 10 then
      raise exception 'Give a reason of at least ten characters for marking the item not applicable.';
    end if;
    if length(v_reason) > 1000 then
      raise exception 'The reason must be at most 1000 characters.';
    end if;
  end if;
  if v_item.status in ('uploaded','linked_mco') then
    raise exception 'Evidence is already held for this item, so its status cannot be changed here.';
  end if;
  if p_status = 'outstanding' and v_item.status not in ('not_applicable','outstanding') then
    raise exception 'Only an item marked not applicable can be returned to outstanding.';
  end if;

  update hsf_file_item
     set status = p_status,
         reason = case when p_status = 'not_applicable' then v_reason else null end
   where id = v_item.id;

  v_fig := hsf_compute_compliance(v_item.file_id);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_item_status_set',
          jsonb_build_object('item_id', v_item.id, 'from', v_item.status, 'to', p_status,
                             'reason', case when p_status = 'not_applicable' then v_reason end),
          v_item.file_id);

  return jsonb_build_object('item_id', v_item.id, 'status', p_status,
                            'reason', case when p_status = 'not_applicable' then v_reason end,
                            'overall', v_fig -> 'overall');
end;
$$;
comment on function hsf_set_item_status is 'Contract 051. Marks an item not applicable with a written reason of at least ten characters, or returns it to outstanding. Not for an item that already holds evidence. The owning client account or staff. Recomputes the compliance figure. Audited.';

-- 6. Execute rights: service role only -------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'hsf_compute_compliance(uuid)',
    'hsf_generate_file(uuid, jsonb)',
    'hsf_my_files(uuid)',
    'hsf_file_detail(uuid, uuid)',
    'hsf_set_item_status(uuid, uuid, text, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;
