-- CNC MSP FORGE | TAX-BAT-09 v1.0.0 | Phase 6 batch 9: Telecommunications and tower work
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('General Safety Regulations, 1986',
 'General Safety Regulations, 1986, GNR 1031, Government Gazette 10252, 30 May 1986, made under the Machinery and Occupational Safety Act 6 of 1983 and kept in force under the Occupational Health and Safety Act 85 of 1993. The Regulations govern first aid provision, personal protective equipment, work in elevated positions, ladders, and general workplace safety duties. They prescribe no standing medical battery: fitness for the work they govern rests on EEA section 7 inherent requirements.',
 'regulation', 'GNR 1031, GG 10252, 30 May 1986', '1986-05-30',
 'Published 30 May 1986 under the Machinery and Occupational Safety Act 6 of 1983; carried into force under section 44 of the Occupational Health and Safety Act 85 of 1993. In force August 2026 with amendments to the first aid and PPE provisions recorded in the consolidated texts.',
 'Full regulation texts, national law library source file 1986-r1031 and the Acts Online consolidated version',
 'ILO NATLEX record for GNR 1031 confirming publication GG 10252, 30 May 1986, and the SAFLII historical regulation record',
 'Currency check 13/08/2026: in force under the OHS Act with no repeal recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Telecommunications and tower work industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('TEL', 'Telecommunications and tower work', 'SIC major division 7, Transport, storage and communication', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('TEL', 'TEL-TOWER', 'Tower construction and rigging',        'Batch 9 role map seeded; gate check below'),
  ('TEL', 'TEL-FIELD', 'Field network services',                'Batch 9 role map seeded; gate check below'),
  ('TEL', 'TEL-DC',    'Data centres and network operations',   'Batch 9 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('TEL-TOWER', 'Tower Rigger and Climber', 'Mast and tower climbing for construction and maintenance, working near live antennas within controlled radio frequency exclusion zones', 'Sustained climbing with tool and equipment load, rescue readiness', 'No vertigo, self rescue competence, exclusion zone discipline', 'Working at heights and rescue certification'),
  ('TEL-TOWER', 'Antenna and RF Technician', 'Antenna installation, alignment, and radio frequency testing at height within controlled exclusion zones', 'Tower climbing with test equipment', 'Alignment precision at height, exclusion zone discipline', 'Working at heights certification'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'Foundation, plinth, and compound civils at tower sites', 'Heavy site labour, concrete and excavation work', 'Instruction following, site discipline', 'None beyond induction'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'Site power, rectifier, and generator installation and service', 'Component lifting, fuel handling, site driving between installations', 'Electrical discipline, fault diagnosis, no condition with sudden incapacity potential', 'Electrical competency; driving licence'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'Crew supervision across tower sites', 'Site access climbing, extensive route driving', 'Rescue plan command, crew coordination', 'Working at heights certification; driving licence'),
  ('TEL-FIELD', 'Fibre Splicer and Jointer', 'Fibre splicing in manholes, chambers, and joint boxes', 'Chamber access including confined entry, fine splicing work', 'Fine motor precision, gas test discipline in chambers', 'Confined space entry competency where applicable'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'Trenching, duct laying, and reinstatement', 'Sustained excavation labour in heat and dust', 'Traffic and services awareness', 'None beyond induction'),
  ('TEL-FIELD', 'Aerial Line Installer', 'Aerial fibre and cable installation on poles', 'Pole climbing and ladder work, roadside working', 'No vertigo, traffic vigilance', 'Working at heights certification; driving licence'),
  ('TEL-FIELD', 'Customer Premises Installer', 'Home and business installations including roof access', 'Ladder and roof access, equipment carriage, route driving', 'Customer interaction, roof edge discipline', 'Driving licence'),
  ('TEL-FIELD', 'Network Field Technician', 'Street cabinet and exchange maintenance with standby callouts', 'Route driving, cabinet work at roadside', 'Fault diagnosis, standby alertness', 'Driving licence'),
  ('TEL-DC',    'Data Centre Operations Technician', 'Shift operation of data centre infrastructure', 'Plant hall rounds across continuous shifts', 'Alarm vigilance, change control discipline', 'None beyond induction'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'Cooling and mechanical plant maintenance', 'Plant room work, component handling', 'Mechanical fault diagnosis', 'Trade certification'),
  ('TEL-DC',    'UPS and Battery Technician', 'UPS, rectifier, and battery string maintenance', 'Battery handling, live DC plant work', 'Electrical discipline, no condition with sudden incapacity potential', 'Electrical competency'),
  ('TEL-DC',    'Network Operations Centre Analyst', 'Continuous network monitoring and incident dispatch', 'Sedentary night duty', 'Sustained overnight vigilance, incident triage', 'None beyond induction'),
  ('TEL-DC',    'Structured Cabling and Racking Technician', 'Rack installation and structured cabling', 'Repetitive overhead and under floor cabling work', 'Cable management precision', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('TEL-TOWER', 'Tower Rigger and Climber', 'E', 'High', 'Mast and tower work at extreme height with rescue readiness'),
  ('TEL-TOWER', 'Tower Rigger and Climber', 'I', 'High', 'Sustained climbing under tool and equipment load'),
  ('TEL-TOWER', 'Tower Rigger and Climber', 'H', 'Moderate', 'Exposed outdoor tower work in heat'),
  ('TEL-TOWER', 'Antenna and RF Technician', 'E', 'High', 'Antenna work at height'),
  ('TEL-TOWER', 'Antenna and RF Technician', 'M', 'Moderate', 'Antenna feeder and site electrical work'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'I', 'High', 'Heavy foundation and compound labour'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'B', 'Moderate', 'Excavation and concrete dust'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'H', 'Moderate', 'Outdoor civils in heat'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'M', 'High', 'Site power and rectifier electrical work'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'C', 'Moderate', 'Fuel and battery electrolyte handling'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'J', 'Moderate', 'Route driving between sites'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'E', 'Moderate', 'Site access climbing for supervision'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'J', 'Moderate', 'Extensive route driving'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'K', 'Moderate', 'Outage and callout windows'),
  ('TEL-FIELD', 'Fibre Splicer and Jointer', 'F', 'Moderate', 'Manhole and chamber confined entry'),
  ('TEL-FIELD', 'Fibre Splicer and Jointer', 'I', 'Moderate', 'Sustained kneeling splicing work'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'I', 'High', 'Sustained excavation labour'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'B', 'Moderate', 'Trenching dust'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'H', 'Moderate', 'Outdoor trenching in heat'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'A', 'Moderate', 'Compaction and cutting plant noise'),
  ('TEL-FIELD', 'Aerial Line Installer', 'E', 'High', 'Pole and ladder work'),
  ('TEL-FIELD', 'Aerial Line Installer', 'M', 'Moderate', 'Work near powered services'),
  ('TEL-FIELD', 'Aerial Line Installer', 'J', 'Moderate', 'Roadside route driving'),
  ('TEL-FIELD', 'Customer Premises Installer', 'E', 'Moderate', 'Ladder and roof access'),
  ('TEL-FIELD', 'Customer Premises Installer', 'J', 'Moderate', 'Daily route driving'),
  ('TEL-FIELD', 'Customer Premises Installer', 'I', 'Moderate', 'Equipment carriage and installation work'),
  ('TEL-FIELD', 'Network Field Technician', 'J', 'Moderate', 'Route driving with standby callouts'),
  ('TEL-FIELD', 'Network Field Technician', 'M', 'Moderate', 'Cabinet and exchange electrical work'),
  ('TEL-FIELD', 'Network Field Technician', 'K', 'Moderate', 'Standby and callout duty'),
  ('TEL-DC',    'Data Centre Operations Technician', 'K', 'High', 'Continuous shift operation'),
  ('TEL-DC',    'Data Centre Operations Technician', 'A', 'Moderate', 'Plant hall noise'),
  ('TEL-DC',    'Data Centre Operations Technician', 'M', 'Moderate', 'Power infrastructure rounds'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'A', 'Moderate', 'Chiller and plant room noise'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'I', 'Moderate', 'Component and filter handling'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'M', 'Moderate', 'Plant electrical maintenance'),
  ('TEL-DC',    'UPS and Battery Technician', 'C', 'Moderate', 'Battery electrolyte and lithium system handling'),
  ('TEL-DC',    'UPS and Battery Technician', 'M', 'High', 'Live DC plant work'),
  ('TEL-DC',    'Network Operations Centre Analyst', 'K', 'High', 'Standing overnight monitoring duty'),
  ('TEL-DC',    'Structured Cabling and Racking Technician', 'I', 'Moderate', 'Overhead and under floor cabling work'),
  ('TEL-DC',    'Structured Cabling and Racking Technician', 'K', 'Moderate', 'Change window night work')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('TEL', 'OHS Act', 'Framework Act for telecommunications workplaces'),
  ('TEL', 'General Safety Regulations, 1986', 'First aid, PPE, elevated positions, and ladder duties for tower and field crews'),
  ('TEL', 'Construction Regulations, 2014', 'Tower construction phases and work at height fitness certification'),
  ('TEL', 'Electrical Machinery and Installation Regulations', 'Site power, rectifier, and data centre electrical work'),
  ('TEL', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for plant halls and construction plant'),
  ('TEL', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('TEL', 'HCA Regulations, 2021', 'Fuels, battery electrolyte, and lithium system context'),
  ('TEL', 'Ergonomics Regulations, 2019', 'Climbing load, trenching, and cabling work surveillance'),
  ('TEL', 'Environmental Regulations for Workplaces, 1987', 'Outdoor heat and chamber atmospheres'),
  ('TEL', 'Driven Machinery Regulations', 'Crane and lifting operations in tower construction'),
  ('TEL', 'NRTA PrDP medical', 'Route driving categories where applicable'),
  ('TEL', 'BCEA night work Code', 'Continuous data centre shifts and standby callouts'),
  ('TEL', 'COIDA', 'Compensation route for telecommunications injuries and diseases'),
  ('TEL', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('TEL', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('TEL', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('TEL', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['TEL-TOWER','TEL-FIELD','TEL-DC']) loop
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
   set description = description || ' Update 13/08/2026 batch 9: the General Safety Regulations, 1986 (GNR 1031, GG 10252, 30 May 1986) are now triple verified, closing a second leg of this item; the General Administrative and General Machinery Regulations remain open.'
 where item_code = 'CR-13.9';

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 9: radio frequency electromagnetic field exposure carries no South African statutory occupational exposure limit; tower and antenna roles carry the exclusion zone discipline in the role narrative per international guidance, and hazard L with its dose monitoring protocol remains reserved for ionising sources under SAHPRA licensing. Should an RF instrument be promulgated, the tower role maps tighten accordingly.'
 where item_code = 'CR-12.1';
