-- CNC MSP FORGE | KRN-API-01 v1.0.0 | Cognitive Kernel read API for approved clients 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 3 (050) and section 7. The database side
-- of GET /api/kernel (vercel/api/kernel.js), which the Grok bot and other
-- approved servers call with a cnck_ key.
--
-- What this migration does:
--   1. msp_instrument_currency_hold: a hold removes an instrument from citation
--      even while its kernel row still reads verified. A hold only ever tightens.
--      Seeded for the NIHL Regulations, 2003 and the Environmental Regulations
--      for Workplaces, 1987 wherever those rows are still verified (HSF-7).
--   2. kernel_citable_instrument: the one definition of "citable" (verified
--      through the three gates, not superseded, not held). Public read.
--   3. hsf_public_element_library (SPEC B4.8): the element library with citable
--      bases only and the candidates still awaiting verification. Public read.
--   4. msp_api_client and msp_api_call_log: keys are stored as a SHA 256 hash
--      only; the log holds the client, the resource, the status and the time,
--      never a request body, a search term or an IP address.
--   5. Key issue and revoke (service role or forge_admin), authorisation with an
--      hourly limit (service role), and the kernel_api_* read functions (service
--      role). The read functions touch kernel and library tables only, never
--      client, engagement, upload, consent or audit data.

-- 1. Currency holds -------------------------------------------------------------------

create table msp_instrument_currency_hold (
  instrument_id uuid primary key references msp_legal_instrument(id),
  reason text not null,
  held_by text not null,
  held_on date not null default current_date
);
comment on table msp_instrument_currency_hold is 'KRN-API-01. Instruments withheld from citation although their kernel row may still read verified, for example after a repeal the live kernel has not yet recorded. A hold only ever tightens: it removes an instrument from kernel_citable_instrument and from every API and File basis.';

alter table msp_instrument_currency_hold enable row level security;
revoke all on msp_instrument_currency_hold from public, anon, authenticated;
grant select on msp_instrument_currency_hold to authenticated;
grant all on msp_instrument_currency_hold to service_role;
create policy msp_instrument_currency_hold_read on msp_instrument_currency_hold
  for select to authenticated using (msp_any_forge_role() or hsf_is_staff());

with seeded as (
  insert into msp_instrument_currency_hold (instrument_id, reason, held_by)
  select li.id, v.reason, 'migration_050'
    from (values
      ('NIHL Regulations, 2003',
       'Repealed with effect from 06/09/2026 by the Noise Exposure Regulations, 2024, as recorded in the CNC OHS Industry Kernel (23/09/2026) and in migration 042. Held from citation until the kernel row is superseded (HSF-7).'),
      ('Environmental Regulations for Workplaces, 1987',
       'Repealed with effect from 06/09/2026 by the Physical Agents Regulations, 2024, as recorded in the CNC OHS Industry Kernel (23/09/2026) and in migration 042. Held from citation until the kernel row is superseded (HSF-7).')
    ) as v(short_name, reason)
    join msp_legal_instrument li on li.short_name = v.short_name
   where li.status = 'verified'
  on conflict (instrument_id) do nothing
  returning instrument_id
)
insert into msp_audit (actor, event_type, event_detail)
select 'migration_050', 'kernel_currency_hold',
       jsonb_build_object('instruments', jsonb_agg(li.short_name order by li.short_name),
                          'reason', 'Repealed with effect from 06/09/2026 (HSF-7)')
  from seeded s join msp_legal_instrument li on li.id = s.instrument_id
having count(*) > 0;

-- 2. Citable instruments -------------------------------------------------------------------

create or replace function kernel_instrument_citable(p_instrument_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from msp_legal_instrument li
                  where li.id = p_instrument_id
                    and li.status = 'verified'
                    and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id));
$$;
comment on function kernel_instrument_citable is 'The single definition of citable: status verified (gates a, b and c passed; a superseded row is never verified) and no currency hold.';

create or replace view kernel_citable_instrument as
select li.short_name,
       li.full_citation,
       li.instrument_type,
       li.gazette_reference,
       li.effective_date,
       li.verified_on,
       li.review_due,
       li.scope,
       (select coalesce(json_agg(json_build_object('code', i.code, 'name', i.name) order by i.code), '[]'::json)
          from msp_industry_instrument ii
          join msp_industry i on i.id = ii.industry_id
         where ii.instrument_id = li.id) as industries
  from msp_legal_instrument li
 where li.status = 'verified'
   and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id)
 order by li.short_name;
comment on view kernel_citable_instrument is 'KRN-API-01. Instruments a page, a File or the kernel API may name as a basis: verified three ways, in force, not superseded, not held. Public read on purpose; it carries only what Care Net publishes.';
grant select on kernel_citable_instrument to anon, authenticated;

-- 3. Public element library (SPEC B4.8) ------------------------------------------------------

create or replace view hsf_public_element_library as
select e.section_code,
       s.name as section_name,
       e.code,
       e.name,
       e.duty,
       e.universal,
       (select coalesce(json_agg(distinct li.short_name order by li.short_name), '[]'::json)
          from hsf_element_instrument ei
          join msp_legal_instrument li on li.id = ei.instrument_id
         where ei.element_id = e.id
           and li.status = 'verified'
           and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id)) as citable,
       (select coalesce(json_agg(distinct li.short_name order by li.short_name), '[]'::json)
          from hsf_element_instrument ei
          join msp_legal_instrument li on li.id = ei.instrument_id
         where ei.element_id = e.id
           and li.status in ('pending','verified')
           and not (li.status = 'verified'
                    and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id))) as awaiting
  from hsf_element e
  join hsf_section s on s.code = e.section_code
 where e.status = 'active'
 order by s.ordinal, e.code;
comment on view hsf_public_element_library is 'SPEC B4.8. The Health and Safety File element library: section, name, duty, the short names of citable instruments only, and the candidates named for the element that are still awaiting verification (never to be cited as a basis). No client data. Public read on purpose.';
grant select on hsf_public_element_library to anon, authenticated;

-- 4. API clients and the call log -------------------------------------------------------------

create table msp_api_client (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 120),
  owner text not null check (length(btrim(owner)) between 1 and 120),
  key_prefix text not null,
  key_hash text unique not null check (key_hash ~ '^[0-9a-f]{64}$'),
  scopes text[] not null default '{kernel.read}',
  active boolean not null default true,
  hourly_limit int not null default 600 check (hourly_limit between 1 and 100000),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
comment on table msp_api_client is 'KRN-API-01. Approved servers that may read the kernel API. Only the SHA 256 hash of a key is kept; the key itself is shown once at issue and never stored. key_prefix is the first characters of the key so staff can tell keys apart.';

create table msp_api_call_log (
  id bigint generated always as identity primary key,
  client_id uuid references msp_api_client(id),
  resource text,
  status int not null,
  created_at timestamptz not null default now()
);
comment on table msp_api_call_log is 'KRN-API-01. Append only log of every authorisation: the client (null for an unknown key), the resource, the status and the time. No request bodies, no search words, no IP addresses.';
create index msp_api_call_log_client_idx on msp_api_call_log(client_id, created_at desc);

create or replace function msp_api_call_log_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'msp_api_call_log is append only';
end;
$$;
create trigger msp_api_call_log_append_only
  before update or delete on msp_api_call_log
  for each row execute function msp_api_call_log_guard();
revoke execute on function msp_api_call_log_guard() from public, anon, authenticated;

alter table msp_api_client enable row level security;
alter table msp_api_call_log enable row level security;
revoke all on msp_api_client from public, anon, authenticated;
revoke all on msp_api_call_log from public, anon, authenticated;
grant all on msp_api_client to service_role;
grant all on msp_api_call_log to service_role;

-- 5. Issue, revoke, authorise -------------------------------------------------------------------

create or replace function msp_api_client_issue(p_name text, p_owner text, p_scopes text[] default '{kernel.read}')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_id uuid;
  v_scopes text[];
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.role(), 'unknown');
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'Issuing a kernel API key requires the forge_admin role.';
  end if;
  if length(btrim(coalesce(p_name, ''))) not between 1 and 120 or length(btrim(coalesce(p_owner, ''))) not between 1 and 120 then
    raise exception 'A key needs a name and an owner of 1 to 120 characters.';
  end if;
  select array_agg(distinct s order by s) into v_scopes from unnest(coalesce(p_scopes, '{kernel.read}'::text[])) s;
  if v_scopes is null or not (v_scopes <@ array['kernel.read']) then
    raise exception 'Unknown scope. The only scope is kernel.read.';
  end if;

  v_key := 'cnck_' || encode(extensions.gen_random_bytes(32), 'hex');
  insert into msp_api_client (name, owner, key_prefix, key_hash, scopes)
  values (btrim(p_name), btrim(p_owner), left(v_key, 12), encode(extensions.digest(v_key, 'sha256'), 'hex'), v_scopes)
  returning id into v_id;

  insert into msp_audit (actor, event_type, event_detail)
  values (v_actor, 'api_client_issued',
          jsonb_build_object('client_id', v_id, 'name', btrim(p_name), 'owner', btrim(p_owner), 'scopes', to_jsonb(v_scopes)));

  -- The only time the key exists outside the caller: it is returned once and never stored.
  return jsonb_build_object('client_id', v_id, 'api_key', v_key);
end;
$$;
comment on function msp_api_client_issue is 'KRN-API-01. Issues a kernel API key: cnck_ followed by 32 random bytes in hex, returned once. Only its SHA 256 hash is stored. Service role or forge_admin. Audited without the key.';

create or replace function msp_api_client_revoke(p_client_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.role(), 'unknown');
  v_row msp_api_client;
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'Revoking a kernel API key requires the forge_admin role.';
  end if;
  update msp_api_client
     set active = false, revoked_at = coalesce(revoked_at, now())
   where id = p_client_id
  returning * into v_row;
  if v_row.id is null then
    raise exception 'That API client was not found.';
  end if;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_actor, 'api_client_revoked', jsonb_build_object('client_id', v_row.id, 'name', v_row.name));
  return jsonb_build_object('client_id', v_row.id, 'active', v_row.active, 'revoked_at', v_row.revoked_at);
end;
$$;
comment on function msp_api_client_revoke is 'KRN-API-01. Stops a key at once. Service role or forge_admin. Audited.';

create or replace function msp_api_authorise(p_key_hash text, p_resource text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text := lower(btrim(coalesce(p_key_hash, '')));
  v_resource text := left(coalesce(p_resource, ''), 40);
  v_client msp_api_client;
  v_calls int;
  v_reason text;
  v_status int;
begin
  if v_resource not in ('industries','industry','instruments','protocols','elements','search') then
    v_reason := 'unknown resource';
    v_status := 400;
    v_resource := null;
  end if;
  if v_reason is null and v_hash ~ '^[0-9a-f]{64}$' then
    -- The row lock serialises concurrent calls on one key, so the hourly count is exact.
    select c.* into v_client from msp_api_client c where c.key_hash = v_hash for update;
  end if;
  if v_reason is null and v_client.id is null then
    v_reason := 'unknown key';
    v_status := 401;
  elsif v_reason is null and (not v_client.active or v_client.revoked_at is not null) then
    v_reason := 'key revoked or inactive';
    v_status := 401;
  elsif v_reason is null and not ('kernel.read' = any(v_client.scopes)) then
    v_reason := 'scope kernel.read missing';
    v_status := 403;
  elsif v_reason is null then
    select count(*) into v_calls
      from msp_api_call_log l
     where l.client_id = v_client.id and l.status = 200 and l.created_at > now() - interval '1 hour';
    if v_calls >= v_client.hourly_limit then
      v_reason := 'hourly rate limit reached';
      v_status := 429;
    else
      v_status := 200;
    end if;
  end if;

  insert into msp_api_call_log (client_id, resource, status) values (v_client.id, v_resource, v_status);

  return jsonb_build_object('ok', v_status = 200,
                            'client_id', case when v_status in (200, 403, 429) then v_client.id end,
                            'scopes', case when v_status = 200 then to_jsonb(v_client.scopes) else '[]'::jsonb end,
                            'reason', v_reason);
end;
$$;
comment on function msp_api_authorise is 'KRN-API-01. Checks a key hash for a resource: known, active, not revoked, scope kernel.read, and fewer authorised calls in the last hour than the key''s hourly_limit. Logs the call (client, resource, status, time only). Service role only.';

-- 6. Read functions ---------------------------------------------------------------------------

create or replace function kernel_api_envelope(p_data jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when p_data is null then null else jsonb_build_object(
    'kernel_release', (select v.semver from msp_kernel_version v
                        order by string_to_array(regexp_replace(v.semver, '[^0-9.]', '', 'g'), '.')::int[] desc nulls last,
                                 v.released_on desc
                        limit 1),
    'as_at', current_date,
    'notice', 'Framework reference data from the Care Net Cognitive Kernel. Not legal advice and not a clinical opinion. Only instruments that have passed three verification checks and are in force are included.',
    'data', p_data) end;
$$;
comment on function kernel_api_envelope is 'Wraps every kernel API payload with kernel_release, as_at and the notice. A null payload stays null (the API answers 404).';

create or replace function kernel_api_protocol_json(p_protocol_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
           'name', tp.test_name,
           'test_type', tp.test_type,
           'hazard', h.name,
           'periodic_interval_months', tp.periodic_interval_months,
           'basis', case when tp.legal_basis_id is not null and kernel_instrument_citable(tp.legal_basis_id)
                         then jsonb_build_array(li.short_name) else '[]'::jsonb end)
    from msp_test_protocol tp
    join msp_hazard h on h.id = tp.hazard_id
    left join msp_legal_instrument li on li.id = tp.legal_basis_id
   where tp.id = p_protocol_id;
$$;
comment on function kernel_api_protocol_json is 'One protocol as the API shows it: name, type, hazard, interval and a basis of citable instruments only. Exposure values and clinical reference ranges are not included.';

create or replace function kernel_api_industry_id(p_code text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select i.id from msp_industry i where i.code = upper(btrim(coalesce(p_code, '')));
$$;

create or replace function kernel_api_industries()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select kernel_api_envelope(coalesce(
    (select jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'regime', i.regulatory_regime) order by i.code)
       from msp_industry i), '[]'::jsonb));
$$;
comment on function kernel_api_industries is 'KRN-API-01. Every industry in the kernel: code, name, regime.';

create or replace function kernel_api_instruments(p_industry text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_industry uuid;
begin
  if nullif(btrim(coalesce(p_industry, '')), '') is not null then
    v_industry := kernel_api_industry_id(p_industry);
    if v_industry is null then
      return null;
    end if;
  end if;
  return kernel_api_envelope(coalesce(
    (select jsonb_agg(to_jsonb(k) order by k.short_name)
       from kernel_citable_instrument k
      where v_industry is null
         or exists (select 1 from json_array_elements(k.industries) x
                     where x ->> 'code' = (select code from msp_industry where id = v_industry))),
    '[]'::jsonb));
end;
$$;
comment on function kernel_api_instruments is 'KRN-API-01. Citable instruments, all or those mapped to one industry. Null for an unknown industry.';

create or replace function kernel_api_protocols(p_industry text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_industry uuid;
begin
  if nullif(btrim(coalesce(p_industry, '')), '') is not null then
    v_industry := kernel_api_industry_id(p_industry);
    if v_industry is null then
      return null;
    end if;
  end if;
  return kernel_api_envelope(coalesce(
    (select jsonb_agg(kernel_api_protocol_json(tp.id) order by tp.test_name, h.name, tp.id)
       from msp_test_protocol tp
       join msp_hazard h on h.id = tp.hazard_id
      where v_industry is null
         or exists (select 1 from msp_job_hazard jh
                      join msp_job_role r on r.id = jh.job_role_id
                      join msp_subindustry s on s.id = r.subindustry_id
                     where jh.hazard_id = tp.hazard_id and s.industry_id = v_industry and s.selectable)),
    '[]'::jsonb));
end;
$$;
comment on function kernel_api_protocols is 'KRN-API-01. Medical surveillance protocols, all or those an industry''s roles call for, with citable bases only. Null for an unknown industry.';

create or replace function kernel_api_elements(p_industry text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_industry uuid;
begin
  if nullif(btrim(coalesce(p_industry, '')), '') is not null then
    v_industry := kernel_api_industry_id(p_industry);
    if v_industry is null then
      return null;
    end if;
  end if;
  return kernel_api_envelope(coalesce(
    (select jsonb_agg(to_jsonb(l) order by s.ordinal, l.code)
       from hsf_public_element_library l
       join hsf_section s on s.code = l.section_code
       join hsf_element e on e.code = l.code
      where v_industry is null
         or e.universal
         or exists (select 1 from hsf_element_industry x where x.element_id = e.id and x.industry_id = v_industry)),
    '[]'::jsonb));
end;
$$;
comment on function kernel_api_elements is 'KRN-API-01. Health and Safety File elements with citable bases only and awaiting candidates named: all, or the universal elements plus the overlay of one industry. Null for an unknown industry.';

create or replace function kernel_api_industry(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ind msp_industry;
begin
  select i.* into v_ind from msp_industry i where i.id = kernel_api_industry_id(p_code);
  if v_ind.id is null then
    return null;
  end if;
  return kernel_api_envelope(jsonb_build_object(
    'code', v_ind.code,
    'name', v_ind.name,
    'regime', v_ind.regulatory_regime,
    'subindustries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', s.code, 'name', s.name,
               'roles', coalesce((select jsonb_agg(r.title order by r.title) from msp_job_role r where r.subindustry_id = s.id), '[]'::jsonb))
             order by s.name)
        from msp_subindustry s where s.industry_id = v_ind.id and s.selectable), '[]'::jsonb),
    'roles', coalesce((
      select jsonb_agg(distinct r.title order by r.title)
        from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id
       where s.industry_id = v_ind.id and s.selectable), '[]'::jsonb),
    'hazards', coalesce((
      select jsonb_agg(distinct h.name order by h.name)
        from msp_job_hazard jh
        join msp_job_role r on r.id = jh.job_role_id
        join msp_subindustry s on s.id = r.subindustry_id
        join msp_hazard h on h.id = jh.hazard_id
       where s.industry_id = v_ind.id and s.selectable), '[]'::jsonb),
    'protocols', coalesce((kernel_api_protocols(v_ind.code) -> 'data'), '[]'::jsonb),
    'instruments', coalesce((kernel_api_instruments(v_ind.code) -> 'data'), '[]'::jsonb)));
end;
$$;
comment on function kernel_api_industry is 'KRN-API-01. One industry: its selectable subindustries with role titles, roles, hazards, protocols with citable bases only, and its citable instruments. Null for an unknown code.';

create or replace function kernel_api_search(p_q text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q text := btrim(regexp_replace(coalesce(p_q, ''), '\s+', ' ', 'g'));
  v_pat text;
begin
  if length(v_q) < 2 or length(v_q) > 100 then
    return kernel_api_envelope('[]'::jsonb);
  end if;
  v_pat := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return kernel_api_envelope(coalesce((
    select jsonb_agg(jsonb_build_object('kind', m.kind, 'name', m.name, 'code', m.code) order by m.rank, m.name, m.code)
      from (
        select * from (
          select 1 as rank, 'instrument'::text as kind, k.short_name as name, null::text as code
            from kernel_citable_instrument k
           where k.short_name ilike v_pat or k.full_citation ilike v_pat
          union
          select 2, 'protocol', tp.test_name, null
            from msp_test_protocol tp where tp.test_name ilike v_pat
          union
          select 3, 'role', r.title, i.code
            from msp_job_role r
            join msp_subindustry s on s.id = r.subindustry_id and s.selectable
            join msp_industry i on i.id = s.industry_id
           where r.title ilike v_pat
          union
          select 4, 'element', l.name, l.code
            from hsf_public_element_library l where l.name ilike v_pat
        ) u
        order by rank, name, code
        limit 50
      ) m), '[]'::jsonb));
end;
$$;
comment on function kernel_api_search is 'KRN-API-01. Case insensitive match over citable instrument, protocol, role and element names; at most 50 results. The search text is not logged.';

-- 7. Execute rights ----------------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'kernel_instrument_citable(uuid)',
    'msp_api_authorise(text, text)',
    'kernel_api_envelope(jsonb)',
    'kernel_api_protocol_json(uuid)',
    'kernel_api_industry_id(text)',
    'kernel_api_industries()',
    'kernel_api_industry(text)',
    'kernel_api_instruments(text)',
    'kernel_api_protocols(text)',
    'kernel_api_elements(text)',
    'kernel_api_search(text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- Issue and revoke: the service role, or a signed in forge_admin (checked in the body).
revoke execute on function msp_api_client_issue(text, text, text[]) from public, anon;
revoke execute on function msp_api_client_revoke(uuid) from public, anon;
grant execute on function msp_api_client_issue(text, text, text[]) to authenticated, service_role;
grant execute on function msp_api_client_revoke(uuid) to authenticated, service_role;
