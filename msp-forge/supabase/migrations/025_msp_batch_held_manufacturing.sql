-- CNC MSP FORGE | TAX-BAT-16 v1.0.0 | Phase 6 batch 16: held subindustry completion, Manufacturing lines
-- No new instrument: roles seed against the verified corpus. Documentary basis 13/08/2026, subject to OMP ratification.

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('MANU-CHEM', 'Chemical Process Operator', 'Batch and continuous chemical process operation', 'Plant rounds with chemical handling', 'Process vigilance, permit discipline', 'Plant operation competency'),
  ('MANU-CHEM', 'Batch Blender and Mixer', 'Weighing, charging, and blending of chemical batches', 'Bag and drum charging, mixer operation', 'Formulation precision, exposure control discipline', 'None beyond induction'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'Raw material and finished goods handling', 'Sustained drum and pallet handling, forklift operation', 'Segregation discipline, spill response', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('MANU-CHEM', 'Plant Laboratory Analyst', 'In process and quality testing', 'Bench work with sample handling', 'Analytical precision, fume control discipline', 'None beyond induction'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'Effluent treatment and neutralisation', 'Dosing work with sump and tank access', 'Dosing precision, gas test discipline', 'Confined space entry competency where applicable'),
  ('MANU-AUTO', 'Assembly Line Operator', 'Vehicle and component assembly at takt', 'Sustained repetitive assembly at rate', 'Sequence accuracy under rate pressure', 'None beyond induction'),
  ('MANU-AUTO', 'Spray Booth Painter', 'Primer and topcoat spraying in booths', 'Spray work in supplied air or filtered PPE', 'Coating quality discipline, respirator discipline', 'None beyond induction'),
  ('MANU-AUTO', 'Body Shop Welder', 'Spot and MIG welding of body components', 'Sustained welding in fixtures', 'Weld quality discipline, fume control discipline', 'Welding competency'),
  ('MANU-AUTO', 'Press Shop Operator', 'Stamping press operation and die changes', 'Press feeding and die handling', 'Guarding discipline, press vigilance', 'None beyond induction'),
  ('MANU-AUTO', 'Quality Inspector (automotive)', 'In process and final inspection', 'Sustained standing inspection work', 'Defect recognition consistency', 'None beyond induction'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'Spinning frame and loom operation', 'Machine patrolling in noise and fibre dust', 'Thread break vigilance', 'None beyond induction'),
  ('MANU-TEX', 'Dye House Operator', 'Dyeing and chemical finishing processes', 'Wet work with dye and auxiliary chemicals in heat', 'Recipe precision, chemical discipline', 'None beyond induction'),
  ('MANU-TEX', 'Cutting and Sewing Machinist', 'Cutting and machine sewing at rate', 'Sustained repetitive machine work', 'Seam accuracy under rate pressure', 'None beyond induction'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'Pressing, steaming, and final finishing', 'Steam pressing in heat', 'Finish quality discipline', 'None beyond induction'),
  ('MANU-TEX', 'Textile Warehouse Assistant', 'Roll and bale handling', 'Sustained roll and bale handling', 'Stock rotation accuracy', 'None beyond induction'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'Mould setting and process optimisation', 'Mould handling, work at hot barrels', 'Process fault diagnosis, guarding discipline', 'None beyond induction'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'Extrusion line operation', 'Line patrolling and die work', 'Line condition vigilance', 'None beyond induction'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'Regrind and granulation operations', 'Feeding and bagging granulate', 'Feed control discipline', 'None beyond induction'),
  ('MANU-PLASTIC', 'Assembly and Finishing Operator (plastics)', 'Trimming, assembly, and packing', 'Sustained repetitive finishing at rate', 'Finish accuracy under rate pressure', 'None beyond induction'),
  ('MANU-PLASTIC', 'Material Handler (plastics)', 'Polymer and masterbatch logistics', 'Bag and octabin handling, forklift operation', 'Material identification accuracy', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('MANU-WOOD', 'Machine Woodworker', 'Saw, planer, and moulder operation', 'Timber feeding in dust and noise', 'Guarding and kickback discipline', 'None beyond induction'),
  ('MANU-WOOD', 'CNC Router Operator', 'CNC routing and nesting operations', 'Panel loading, machine supervision', 'Programme verification discipline', 'None beyond induction'),
  ('MANU-WOOD', 'Furniture Assembler', 'Component assembly and fitting', 'Sustained assembly handling', 'Fit quality discipline', 'None beyond induction'),
  ('MANU-WOOD', 'Wood Spray Finisher', 'Staining, sealing, and lacquer spraying', 'Booth spray work', 'Coating discipline, respirator discipline', 'None beyond induction'),
  ('MANU-WOOD', 'Timber Yard Worker', 'Timber receiving, stacking, and despatch', 'Heavy timber handling, forklift operation', 'Stack stability judgement', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('MANU-CHEM', 'Chemical Process Operator', 'C', 'High', 'Process chemical exposure with HCA biological monitoring where indicated'),
  ('MANU-CHEM', 'Chemical Process Operator', 'A', 'Moderate', 'Process plant noise'),
  ('MANU-CHEM', 'Chemical Process Operator', 'K', 'Moderate', 'Continuous process shifts'),
  ('MANU-CHEM', 'Batch Blender and Mixer', 'C', 'High', 'Charging and blending exposure peaks'),
  ('MANU-CHEM', 'Batch Blender and Mixer', 'I', 'Moderate', 'Bag and drum charging'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'C', 'Moderate', 'Drummed chemical handling'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'I', 'High', 'Sustained drum and pallet handling'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'J', 'Moderate', 'Forklift operation under the Driven Machinery Regulations, 2015'),
  ('MANU-CHEM', 'Plant Laboratory Analyst', 'C', 'Moderate', 'Solvent and reagent handling'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'C', 'Moderate', 'Neutralisation chemical handling'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'D', 'Moderate', 'Effluent biological exposure'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'F', 'Moderate', 'Sump and tank access'),
  ('MANU-AUTO', 'Assembly Line Operator', 'I', 'High', 'Sustained repetitive assembly at takt'),
  ('MANU-AUTO', 'Assembly Line Operator', 'A', 'Moderate', 'Assembly hall noise'),
  ('MANU-AUTO', 'Assembly Line Operator', 'K', 'Moderate', 'Production shift patterns'),
  ('MANU-AUTO', 'Spray Booth Painter', 'C', 'High', 'Isocyanate containing coating exposure with sensitiser surveillance'),
  ('MANU-AUTO', 'Spray Booth Painter', 'B', 'Moderate', 'Sanding and overspray particulate'),
  ('MANU-AUTO', 'Spray Booth Painter', 'A', 'Moderate', 'Booth and tool noise'),
  ('MANU-AUTO', 'Body Shop Welder', 'C', 'Moderate', 'Welding fume exposure'),
  ('MANU-AUTO', 'Body Shop Welder', 'A', 'Moderate', 'Body shop noise'),
  ('MANU-AUTO', 'Body Shop Welder', 'B', 'Moderate', 'Welding particulate'),
  ('MANU-AUTO', 'Body Shop Welder', 'M', 'Moderate', 'Welding electrical systems'),
  ('MANU-AUTO', 'Press Shop Operator', 'A', 'High', 'Stamping press noise'),
  ('MANU-AUTO', 'Press Shop Operator', 'I', 'Moderate', 'Press feeding and die handling'),
  ('MANU-AUTO', 'Press Shop Operator', 'G', 'Moderate', 'Press vibration exposure'),
  ('MANU-AUTO', 'Quality Inspector (automotive)', 'I', 'Moderate', 'Sustained standing inspection'),
  ('MANU-AUTO', 'Quality Inspector (automotive)', 'A', 'Moderate', 'Production hall noise'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'A', 'High', 'Loom and frame noise'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'B', 'Moderate', 'Cotton and fibre dust with byssinosis context'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'I', 'Moderate', 'Machine patrolling and piecing'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'K', 'Moderate', 'Continuous mill shifts'),
  ('MANU-TEX', 'Dye House Operator', 'C', 'High', 'Dye and auxiliary chemical exposure'),
  ('MANU-TEX', 'Dye House Operator', 'H', 'Moderate', 'Dye house heat and steam'),
  ('MANU-TEX', 'Dye House Operator', 'I', 'Moderate', 'Wet fabric handling'),
  ('MANU-TEX', 'Cutting and Sewing Machinist', 'I', 'High', 'Sustained repetitive machine sewing'),
  ('MANU-TEX', 'Cutting and Sewing Machinist', 'A', 'Moderate', 'Machine floor noise'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'H', 'Moderate', 'Steam pressing heat'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'I', 'Moderate', 'Sustained pressing work'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'C', 'Moderate', 'Finishing chemical exposure'),
  ('MANU-TEX', 'Textile Warehouse Assistant', 'I', 'Moderate', 'Roll and bale handling'),
  ('MANU-TEX', 'Textile Warehouse Assistant', 'B', 'Moderate', 'Fibre dust in storage'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'H', 'Moderate', 'Hot barrel and mould work'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'C', 'Moderate', 'Polymer fume at purging'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'A', 'Moderate', 'Moulding hall noise'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'I', 'Moderate', 'Mould handling'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'A', 'Moderate', 'Extrusion line noise'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'C', 'Moderate', 'Polymer fume at the die'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'K', 'Moderate', 'Continuous line shifts'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'A', 'Moderate', 'Granulator noise'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'B', 'Moderate', 'Regrind dust'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'I', 'Moderate', 'Feeding and bagging work'),
  ('MANU-PLASTIC', 'Assembly and Finishing Operator (plastics)', 'I', 'High', 'Sustained repetitive finishing at rate'),
  ('MANU-PLASTIC', 'Assembly and Finishing Operator (plastics)', 'K', 'Moderate', 'Production shift patterns'),
  ('MANU-PLASTIC', 'Material Handler (plastics)', 'I', 'Moderate', 'Bag and octabin handling'),
  ('MANU-PLASTIC', 'Material Handler (plastics)', 'J', 'Moderate', 'Forklift operation under the Driven Machinery Regulations, 2015'),
  ('MANU-WOOD', 'Machine Woodworker', 'B', 'High', 'Hardwood and softwood dust with sensitiser context'),
  ('MANU-WOOD', 'Machine Woodworker', 'A', 'High', 'Saw and moulder noise'),
  ('MANU-WOOD', 'Machine Woodworker', 'I', 'Moderate', 'Timber feeding work'),
  ('MANU-WOOD', 'CNC Router Operator', 'B', 'Moderate', 'Routing dust'),
  ('MANU-WOOD', 'CNC Router Operator', 'A', 'Moderate', 'Router noise'),
  ('MANU-WOOD', 'Furniture Assembler', 'I', 'High', 'Sustained assembly handling'),
  ('MANU-WOOD', 'Furniture Assembler', 'A', 'Moderate', 'Workshop noise'),
  ('MANU-WOOD', 'Wood Spray Finisher', 'C', 'High', 'Lacquer and solvent spray exposure'),
  ('MANU-WOOD', 'Wood Spray Finisher', 'B', 'Moderate', 'Sanding dust'),
  ('MANU-WOOD', 'Timber Yard Worker', 'I', 'High', 'Heavy timber handling'),
  ('MANU-WOOD', 'Timber Yard Worker', 'B', 'Moderate', 'Yard timber dust'),
  ('MANU-WOOD', 'Timber Yard Worker', 'J', 'Moderate', 'Forklift operation under the Driven Machinery Regulations, 2015')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['MANU-CHEM','MANU-AUTO','MANU-TEX','MANU-PLASTIC','MANU-WOOD']) loop
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
    update msp_subindustry
       set selectable = true,
           notes = 'Batch 16 role map seeded; gate passed'
     where code = v_code;
    raise notice 'batch gate: % enabled (% roles)', v_code, v_roles;
  end loop;
end $$;

-- Register updates

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 16: isocyanate spray painting and wood dust carry respiratory sensitiser surveillance under the HCA framework with spirometry emphasis; cotton dust carries the byssinosis context. Substance specific OEL confirmations for isocyanates, wood dust, and cotton dust remain open under the OEL item and values are applied from the HCA annexure at examination.'
 where item_code = 'CR-12.1';
