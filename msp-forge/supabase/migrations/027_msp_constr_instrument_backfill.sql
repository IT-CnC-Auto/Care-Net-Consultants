-- CNC MSP FORGE | REG-CLS-02 v1.0.0 | Construction industry instrument backfill 14/08/2026
-- Instruments verified in later batches that apply to Construction but were never joined to it.

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('CONSTR', 'Driven Machinery Regulations', 'Crane, hoist, and lifting machine operator medical certificates of fitness per regulation 18'),
  ('CONSTR', 'General Safety Regulations, 1986', 'First aid, PPE, elevated positions, and ladder duties on construction sites'),
  ('CONSTR', 'General Administrative Regulations, 2003', 'Incident reporting and health and safety representative duties'),
  ('CONSTR', 'Environmental Regulations for Workplaces, 1987', 'Outdoor and hot work thermal environments; fitness certification for hot work per regulation 5(4)')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where not exists (
  select 1 from msp_industry_instrument x
   where x.industry_id = i.id and x.instrument_id = li.id
);

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the Construction industry instrument map is backfilled with the Driven Machinery Regulations, General Safety Regulations, 1986, General Administrative Regulations, 2003, and Environmental Regulations for Workplaces, 1987, all verified in later batches and applicable to construction work. Future instrument verifications must sweep existing industry maps as part of the batch pattern.'
 where item_code = 'CR-12.1';
