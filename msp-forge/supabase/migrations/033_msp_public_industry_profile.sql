-- CNC MSP FORGE | PUB-01 v1.0.0 | Public industry profile view 14/08/2026
-- Marketing surface for the website industry pages. This view is deliberately
-- readable by anon: it carries only content Care Net publishes on its own site.
--
-- What it exposes: industry and subindustry names, the short names and
-- applicability notes of VERIFIED instruments, hazard names, protocol names, and
-- job role titles with counts.
-- What it never exposes: client or engagement data, intake responses, drafts,
-- OMP reviews, the confirmation register, pending or excluded instruments, and
-- the exposure values and clinical reference ranges inside the protocols.
--
-- The view runs with the owner's rights so the anon role never touches the
-- protected kernel tables directly. Any advisor notice about a definer view on
-- this object is expected and accepted: publication is the purpose.

create or replace view msp_public_industry_profile as
select
  i.code,
  i.name,
  i.regulatory_regime as regime,
  (select count(*) from msp_subindustry s where s.industry_id = i.id and s.selectable) as subindustry_count,
  (select count(*) from msp_job_role r
     join msp_subindustry s on s.id = r.subindustry_id
    where s.industry_id = i.id) as role_count,
  (select coalesce(json_agg(json_build_object('name', s.name, 'roles',
            (select coalesce(json_agg(r.title order by r.title), '[]'::json)
               from msp_job_role r where r.subindustry_id = s.id)) order by s.name), '[]'::json)
     from msp_subindustry s where s.industry_id = i.id and s.selectable) as subindustries,
  (select coalesce(json_agg(json_build_object('name', li.short_name, 'note', ii.applicability_note)
            order by li.short_name), '[]'::json)
     from msp_industry_instrument ii
     join msp_legal_instrument li on li.id = ii.instrument_id
    where ii.industry_id = i.id and li.status = 'verified') as instruments,
  (select coalesce(json_agg(distinct h.name), '[]'::json)
     from msp_job_hazard jh
     join msp_job_role r on r.id = jh.job_role_id
     join msp_subindustry s on s.id = r.subindustry_id
     join msp_hazard h on h.id = jh.hazard_id
    where s.industry_id = i.id) as hazards,
  (select coalesce(json_agg(distinct tp.test_name), '[]'::json)
     from msp_job_hazard jh
     join msp_job_role r on r.id = jh.job_role_id
     join msp_subindustry s on s.id = r.subindustry_id
     join msp_test_protocol tp on tp.hazard_id = jh.hazard_id
    where s.industry_id = i.id) as protocols
from msp_industry i;

comment on view msp_public_industry_profile is
  'Public marketing surface for the website industry pages. Aggregate, non clinical, no client data. Readable by anon on purpose.';

grant select on msp_public_industry_profile to anon, authenticated;

-- Public framework statistics for the website. Same principle: aggregate counts
-- and the released version only, nothing clinical, nothing about any client.

create or replace view msp_public_framework_stats as
select
  (select semver from msp_kernel_version order by released_on desc, semver desc limit 1) as version,
  (select count(*) from msp_legal_instrument where status = 'verified') as instruments,
  (select count(*) from msp_industry) as industries,
  (select count(*) from msp_subindustry where selectable) as subindustries,
  (select count(*) from msp_job_role) as roles,
  (select count(*) from msp_test_protocol) as protocols;

comment on view msp_public_framework_stats is
  'Public marketing statistics for the website. Aggregate only. Readable by anon on purpose.';

grant select on msp_public_framework_stats to anon, authenticated;
