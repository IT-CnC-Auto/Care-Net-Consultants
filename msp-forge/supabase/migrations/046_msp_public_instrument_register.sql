-- CNC MSP FORGE | KRN-PUB-02 v1.0.0 | Public legislation register 20/09/2026
-- Applied to the live project on 20/09/2026 (recorded there as
-- 040_msp_public_instrument_register). The website's Build your Plan page shows
-- the industries covered and every legal instrument the engine drafts from, with
-- its full citation, so a visitor can see what the Plan is built on before they
-- build one. This view is that register: verified instruments only, with the
-- industries each one applies to, readable by the anonymous key like the other
-- msp_public_* views. Nothing pending, nothing internal, nothing about clients.

create or replace view msp_public_instrument_register as
select li.short_name,
       li.full_citation,
       li.instrument_type,
       li.gazette_reference,
       li.effective_date,
       li.amendment_history,
       li.verified_on,
       li.review_due,
       (select coalesce(json_agg(json_build_object('code', i.code, 'name', i.name) order by i.name), '[]'::json)
          from msp_industry_instrument ii
          join msp_industry i on i.id = ii.industry_id
         where ii.instrument_id = li.id) as industries
  from msp_legal_instrument li
 where li.status = 'verified'
 order by li.short_name;

comment on view msp_public_instrument_register is
  'The legislation register as published on the website: verified instruments with full citation and the industries each applies to. Anonymous read.';

grant select on msp_public_instrument_register to anon, authenticated;
