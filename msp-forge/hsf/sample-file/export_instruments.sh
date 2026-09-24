#!/usr/bin/env bash
# Exports the kernel instruments that File elements draw on, with their kernel
# status and any currency hold, for the sample File renderer. Run after a full
# replay (test/sql/replay.sh). Usage: hsf/sample-file/export_instruments.sh [database]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
psql -h /tmp -p 55432 -U postgres -d "${1:-cnc_test}" -At -v ON_ERROR_STOP=1 -c "
select json_build_object(
 'instruments',(select json_agg(json_build_object('short_name',li.short_name,'status',li.status,'scope',li.scope,'verified_on',li.verified_on,
    'held',(select h.reason from msp_instrument_currency_hold h where h.instrument_id=li.id)) order by li.short_name)
    from msp_legal_instrument li where exists (select 1 from hsf_element_instrument ei where ei.instrument_id=li.id)),
 'by_appointment',(select json_object_agg(a.name, li.short_name) from hsf_appointment_type a join msp_legal_instrument li on li.id=a.instrument_id),
 'by_element',(select json_object_agg(code,names) from (select e.code, json_agg(distinct li.short_name) names
    from hsf_element e join hsf_element_instrument ei on ei.element_id=e.id join msp_legal_instrument li on li.id=ei.instrument_id group by e.code) x))" \
 | python3 -c 'import json,sys; print(json.dumps(json.loads(sys.stdin.read()), indent=1, sort_keys=True))' > "$HERE/instruments.json"
echo "wrote $HERE/instruments.json"
