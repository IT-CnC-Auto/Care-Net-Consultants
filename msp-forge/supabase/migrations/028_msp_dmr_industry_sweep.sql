-- CNC MSP FORGE | REG-CLS-03 v1.0.0 | Driven Machinery Regulations industry map sweep 14/08/2026
-- Industries whose role maps cite lifting machine operation but predate the DMR verification.

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('MANU',   'Forklift and lifting machine operator medical certificates of fitness per regulation 18'),
  ('MINING', 'Surface lifting machine operator medical certificates of fitness per regulation 18, alongside the MHSA regime underground'),
  ('TRANS',  'Forklift, reach truck, crane, and terminal lifting machine operator medical certificates of fitness per regulation 18')
) as m(icode, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = 'Driven Machinery Regulations' and li.status = 'verified'
where not exists (
  select 1 from msp_industry_instrument x
   where x.industry_id = i.id and x.instrument_id = li.id
);

do $$
declare v_missing int;
begin
  select count(*) into v_missing
    from (
      select distinct i.id
        from msp_job_role r
        join msp_subindustry s on s.id = r.subindustry_id
        join msp_industry i on i.id = s.industry_id
       where r.statutory_competency_requirement ilike '%Driven Machinery%'
          or exists (select 1 from msp_job_hazard jh where jh.job_role_id = r.id and jh.rationale ilike '%Driven Machinery%')
    ) ri
   where not exists (
      select 1 from msp_industry_instrument ii
       join msp_legal_instrument li on li.id = ii.instrument_id and li.short_name = 'Driven Machinery Regulations'
      where ii.industry_id = ri.id);
  if v_missing > 0 then
    raise exception 'DMR sweep gate: % industries still cite lifting machine work without the instrument mapping', v_missing;
  end if;
  raise notice 'DMR sweep gate: all citing industries mapped';
end $$;
