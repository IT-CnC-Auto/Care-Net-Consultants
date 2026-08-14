-- CNC MSP FORGE | REG-CLS-04 v1.0.0 | R638 instrument and protocol deduplication 14/08/2026
-- Batch 7 introduced a second R638 instrument alongside the batch 1 'FCD Act R638, 2018' row,
-- and a second food handler protocol. One instrument, one protocol: the fuller batch 7 rows win.

do $$
declare
  v_old uuid; v_new uuid; v_old_protocol uuid; v_refs int;
begin
  select id into v_old from msp_legal_instrument where short_name = 'FCD Act R638, 2018';
  select id into v_new from msp_legal_instrument where short_name = 'Food Premises Hygiene Regulations, R638 of 2018';
  if v_old is null or v_new is null then
    raise notice 'R638 dedup: nothing to do';
    return;
  end if;

  select id into v_old_protocol
    from msp_test_protocol
   where legal_basis_id = v_old and test_name = 'Food handler fitness assessment';

  -- Guard: the old protocol must be unreferenced by any stored draft stage output.
  if v_old_protocol is not null then
    select count(*) into v_refs from msp_draft where stage_output::text like '%' || v_old_protocol || '%';
    if v_refs > 0 then
      raise exception 'R638 dedup: old protocol % is referenced by % draft rows', v_old_protocol, v_refs;
    end if;
    delete from msp_test_protocol where id = v_old_protocol;
  end if;

  -- Repoint industry maps that still cite the old instrument, skipping industries already on the new one.
  update msp_industry_instrument ii
     set instrument_id = v_new
   where ii.instrument_id = v_old
     and not exists (select 1 from msp_industry_instrument x
                      where x.industry_id = ii.industry_id and x.instrument_id = v_new);
  delete from msp_industry_instrument where instrument_id = v_old;

  -- Repoint any remaining protocol bases, then retire the duplicate instrument through the exclusion log.
  update msp_test_protocol set legal_basis_id = v_new where legal_basis_id = v_old;

  -- Not routed through msp_exclude_instrument: the exclusion register records gate
  -- failures (a, b, c) and this is a duplication, not a verification failure.
  update msp_legal_instrument
     set status = 'excluded',
         amendment_history = coalesce(amendment_history, '') || ' Retired 14/08/2026 as a duplicate of the Food Premises Hygiene Regulations, R638 of 2018 record; all references repointed. Not a verification failure.'
   where id = v_old;

  insert into msp_audit (actor, event_type, event_detail)
  values ('Claude Code build agent', 'kernel_hygiene',
          jsonb_build_object('action', 'instrument_dedup',
                             'retired_instrument', 'FCD Act R638, 2018',
                             'surviving_instrument', 'Food Premises Hygiene Regulations, R638 of 2018',
                             'reason', 'duplicate record, references repointed, duplicate protocol removed'));

  raise notice 'R638 dedup complete: % retired in favour of %', v_old, v_new;
end $$;

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the duplicate FCD Act R638, 2018 instrument row from batch 1 is retired in favour of the fuller batch 7 Food Premises Hygiene Regulations record; the MANU industry map and the food handler protocol are deduplicated so a pack never prescribes the same assessment twice.'
 where item_code = 'CR-12.1';
