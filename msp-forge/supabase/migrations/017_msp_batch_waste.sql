-- CNC MSP FORGE | TAX-BAT-08 v1.0.0 | Phase 6 batch 8: Waste management
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('NEM Waste Act',
 'National Environmental Management: Waste Act 59 of 2008, Government Gazette 32000, in operation 1 July 2009. The Act governs waste management licensing, the duty of care for waste holders, and healthcare risk waste control. It prescribes no standing occupational medical battery: waste worker surveillance rests on the OHSA instrument set and the lawful testing basis is EEA section 7, with this Act anchoring the sector duty of care context.',
 'act', 'Act 59 of 2008, GG 32000; in operation 1 July 2009', '2009-07-01',
 'Amended by Act 14 of 2013, Act 25 of 2014, Act 26 of 2014 (GG 37714, with effect from 2 June 2014), and Act 2 of 2022; consolidated text current to 30 June 2023 on the national law library. In force August 2026.',
 'Consolidated Act texts, SAFLII nemwa2008394 and the official gov.za Act publication',
 'National law library consolidated version at 30 June 2023 and the UNEP legislation record confirming commencement 1 July 2009, GG 32000',
 'Currency check 13/08/2026: in force with the 2013, 2014, and 2022 amendment chain recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Waste management industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('WASTE', 'Waste management', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('WASTE', 'WASTE-COLL', 'Collection and street cleansing',      'Batch 8 role map seeded; gate check below'),
  ('WASTE', 'WASTE-SITE', 'Landfill and transfer stations',       'Batch 8 role map seeded; gate check below'),
  ('WASTE', 'WASTE-REC',  'Recycling and materials recovery',     'Batch 8 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('WASTE-COLL', 'Refuse Truck Driver', 'Compaction vehicle operation on collection rounds', 'Prolonged urban driving with frequent stops', 'Crew and pedestrian vigilance, reaction time, no uncontrolled hypoglycaemic risk', 'PrDP for the applicable vehicle class'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'Bin and bag loading on collection rounds', 'Sustained heavy lifting at pace, running boards work', 'Traffic vigilance, crew coordination', 'None beyond induction'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'Street cleansing and litter collection', 'Sustained walking and sweeping, sharps risk handling', 'Traffic vigilance, sharps discipline', 'None beyond induction'),
  ('WASTE-COLL', 'Skip and Roll On Truck Driver', 'Skip placement and exchange operations', 'Hook and chain work, load securing', 'Load stability judgement, site manoeuvring', 'PrDP for the applicable vehicle class'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'Clearing uncontrolled dumping sites', 'Heavy mixed waste handling of unknown composition', 'Hazard recognition in uncharacterised waste', 'None beyond induction'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'Compactor, dozer, and landfill plant operation', 'Sustained plant operation on waste body surfaces', 'Machine stability judgement, site traffic vigilance, no condition with sudden incapacity potential', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('WASTE-SITE', 'Weighbridge Operator', 'Vehicle weighing and load documentation', 'Sedentary control room duty', 'Documentation accuracy, vehicle queue management', 'None beyond induction'),
  ('WASTE-SITE', 'Landfill General Worker', 'Cover material work, litter fencing, and site labour', 'Heavy outdoor labour on the waste body', 'Site traffic vigilance, instruction following', 'None beyond induction'),
  ('WASTE-SITE', 'Transfer Station Operator', 'Waste transfer, pushing, and loading operations', 'Plant and floor work in the transfer hall', 'Traffic and plant separation vigilance', 'None beyond induction'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'Leachate pumping and landfill gas system maintenance', 'Sump and manifold access including confined entry', 'Gas test discipline, escape procedure', 'Confined space entry competency'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'Manual sorting on the recovery line', 'Sustained repetitive picking with sharps risk', 'Material recognition at rate, sharps discipline', 'None beyond induction'),
  ('WASTE-REC',  'Baler and Compactor Operator', 'Baling and compacting recovered materials', 'Bale handling, machine feeding', 'Machine guarding discipline', 'None beyond induction'),
  ('WASTE-REC',  'E Waste Dismantling Technician', 'Manual dismantling of electronic waste', 'Repetitive dismantling with lead and cadmium bearing components', 'Component recognition, hygiene discipline', 'None beyond induction'),
  ('WASTE-REC',  'Buy Back Centre Assistant', 'Receiving, weighing, and sorting recyclables', 'Sustained handling of mixed recyclables', 'Grading accuracy, sharps discipline', 'None beyond induction'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'Collection and processing of healthcare risk waste', 'Container handling in full PPE', 'Segregation and containment discipline', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('WASTE-COLL', 'Refuse Truck Driver', 'J', 'High', 'Professional collection round driving with PrDP requirement'),
  ('WASTE-COLL', 'Refuse Truck Driver', 'K', 'Moderate', 'Early morning collection shifts'),
  ('WASTE-COLL', 'Refuse Truck Driver', 'D', 'Moderate', 'Waste stream biological contact'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'I', 'High', 'Sustained heavy loading at pace'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'D', 'High', 'Direct waste handling with sharps risk'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'K', 'Moderate', 'Early morning collection shifts'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'H', 'Moderate', 'Outdoor rounds in heat'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'I', 'Moderate', 'Sustained sweeping and walking'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'D', 'Moderate', 'Litter and sharps handling'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('WASTE-COLL', 'Skip and Roll On Truck Driver', 'J', 'High', 'Skip vehicle operation with PrDP requirement'),
  ('WASTE-COLL', 'Skip and Roll On Truck Driver', 'I', 'Moderate', 'Hook, chain, and load securing work'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'D', 'High', 'Uncharacterised waste biological exposure'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'I', 'High', 'Heavy mixed waste clearance'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'C', 'Moderate', 'Unknown chemical containers in dumped waste'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'J', 'High', 'Landfill plant operation under the Driven Machinery Regulations, 2015'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'B', 'Moderate', 'Cover material and site dust'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'A', 'Moderate', 'Plant cab noise'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'D', 'Moderate', 'Waste body biological context'),
  ('WASTE-SITE', 'Weighbridge Operator', 'K', 'Moderate', 'Extended site operating hours'),
  ('WASTE-SITE', 'Weighbridge Operator', 'A', 'Low', 'Vehicle queue noise'),
  ('WASTE-SITE', 'Landfill General Worker', 'D', 'High', 'Waste body biological exposure'),
  ('WASTE-SITE', 'Landfill General Worker', 'B', 'Moderate', 'Site and cover material dust'),
  ('WASTE-SITE', 'Landfill General Worker', 'I', 'High', 'Heavy site labour'),
  ('WASTE-SITE', 'Landfill General Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('WASTE-SITE', 'Transfer Station Operator', 'D', 'Moderate', 'Transfer hall waste contact'),
  ('WASTE-SITE', 'Transfer Station Operator', 'A', 'Moderate', 'Transfer hall plant noise'),
  ('WASTE-SITE', 'Transfer Station Operator', 'I', 'Moderate', 'Pushing and loading work'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'C', 'Moderate', 'Landfill gas and leachate chemical exposure'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'D', 'Moderate', 'Leachate biological exposure'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'F', 'Moderate', 'Sump and chamber confined entry'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'D', 'High', 'Mixed waste sorting with sharps risk'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'I', 'High', 'Sustained repetitive picking at rate'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'A', 'Moderate', 'Recovery hall plant noise'),
  ('WASTE-REC',  'Baler and Compactor Operator', 'A', 'Moderate', 'Baler plant noise'),
  ('WASTE-REC',  'Baler and Compactor Operator', 'I', 'Moderate', 'Bale handling'),
  ('WASTE-REC',  'E Waste Dismantling Technician', 'C', 'High', 'Lead and cadmium bearing component dismantling'),
  ('WASTE-REC',  'E Waste Dismantling Technician', 'I', 'Moderate', 'Repetitive dismantling work'),
  ('WASTE-REC',  'Buy Back Centre Assistant', 'I', 'Moderate', 'Mixed recyclables handling'),
  ('WASTE-REC',  'Buy Back Centre Assistant', 'D', 'Moderate', 'Contaminated recyclables contact'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'D', 'High', 'Healthcare risk waste with sharps and infectious exposure'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'C', 'Moderate', 'Disinfection chemical handling'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'I', 'Moderate', 'Container handling in full PPE')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('WASTE', 'OHS Act', 'Framework Act for waste management workplaces'),
  ('WASTE', 'NEM Waste Act', 'Sector duty of care, licensing, and healthcare risk waste control context'),
  ('WASTE', 'HBA Regulations, 2022', 'Waste stream, leachate, and healthcare risk waste biological exposure'),
  ('WASTE', 'HCA Regulations, 2021', 'Landfill gas, e waste heavy metals, and disinfection chemicals'),
  ('WASTE', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for plant and recovery halls'),
  ('WASTE', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('WASTE', 'Ergonomics Regulations, 2019', 'Collection loading and sorting line surveillance'),
  ('WASTE', 'Environmental Regulations for Workplaces, 1987', 'Outdoor heat and confined space atmospheres'),
  ('WASTE', 'Driven Machinery Regulations', 'Landfill plant and lifting machine operator medical certificates of fitness'),
  ('WASTE', 'NRTA PrDP medical', 'Collection and skip vehicle driving categories'),
  ('WASTE', 'BCEA night work Code', 'Early morning collection shifts'),
  ('WASTE', 'COIDA', 'Compensation route for waste sector injuries and diseases'),
  ('WASTE', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('WASTE', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('WASTE', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('WASTE', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['WASTE-COLL','WASTE-SITE','WASTE-REC']) loop
    select count(*) into v_roles
      from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id where s.code = v_code;
    select count(*) into v_unmapped
      from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id
     where s.code = v_code
       and not exists (select 1 from msp_job_hazard jh where jh.job_role_id = r.id);
    select count(distinct h.code) into v_unprotocolled
      from msp_job_hazard jh
      join msp_job_role r on r.id = jh.job_role_id
      join msp_subindustry s on s.id = r.subindustry_id
      join msp_hazard h on h.id = jh.hazard_id
     where s.code = v_code
       and not exists (select 1 from msp_test_protocol tp where tp.hazard_id = h.id)
       and h.code not in ('O','N');
    if v_roles < 5 then raise exception 'batch gate: % has only % roles', v_code, v_roles; end if;
    if v_unmapped > 0 then raise exception 'batch gate: % has % unmapped roles', v_code, v_unmapped; end if;
    if v_unprotocolled > 0 then raise exception 'batch gate: % has % unprotocolled hazards', v_code, v_unprotocolled; end if;
    update msp_subindustry set selectable = true where code = v_code;
    raise notice 'batch gate: % enabled (% roles)', v_code, v_roles;
  end loop;
end $$;

-- Register updates

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 8: healthcare risk waste handling is carried under the HBA framework with hepatitis B immunity verification; the SANS 10248 healthcare risk waste standard remains open under the SANS editions item. E waste dismantling feeds the lead biological monitoring protocol where exposure assessment confirms lead bearing work.'
 where item_code = 'CR-12.1';
