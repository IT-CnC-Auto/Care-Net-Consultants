-- Demo fixtures matching the design canvas. Every figure is mock data.
insert into tenant (id, slug, legal_name, territory, information_officer) values
 ('00000000-0000-0000-0000-000000000001', 'cnc-hq', 'Care Net Consultants (Pty) Ltd', 'National', '[CONFIRM Information Officer]');

insert into person (id, tenant_id, email, full_name, initials, role, manager_id, capacity_open_parents, is_service_account) values
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'barteldt@carenetconsultants.co.za', 'Barteldt Kruger', 'BK', 'franchise_director', null, 12, false),
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'annemarie@carenetconsultants.co.za', 'Annemarie Wiese', 'AW', 'sales_manager', '10000000-0000-0000-0000-000000000001', 12, false),
 ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'celeste@carenetconsultants.co.za', 'Celeste Bulpitt', 'CB', 'sales_consultant', '10000000-0000-0000-0000-000000000002', 12, false),
 ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'asandiswa@carenetconsultants.co.za', 'Asandiswa Ntsali', 'AN', 'sales_consultant', '10000000-0000-0000-0000-000000000002', 12, false),
 ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'asivhanga@carenetconsultants.co.za', 'Asivhanga More', 'AS', 'sales_consultant', '10000000-0000-0000-0000-000000000002', 12, false),
 ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001', 'asekhona@carenetconsultants.co.za', 'Asekhona Magwashu', 'AM', 'sales_consultant', '10000000-0000-0000-0000-000000000002', 12, false),
 ('10000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000001', 'grok-agent@carenetconsultants.co.za', 'Grok agent', 'GA', 'agent', '10000000-0000-0000-0000-000000000002', 999, true);

insert into client (id, tenant_id, name, industry, sites, employees_on_surveillance, mco_client_ref, account_owner_id, oversight_id, client_source, client_source_recorded_at, current_stage, contract_renewal) values
 ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Pt Operational Services (Pty) Ltd', 'Mining services', '{Secunda,Sasolburg}', 214, 'MCO-PTOPS', '10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'Referral', '2019-03-01', 'renewal', '2027-03-31'),
 ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Afrirent Auto (Pty) Ltd', 'Fleet', '{Johannesburg}', 60, 'MCO-AFRI', '10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'Cold outbound', '2021-06-01', 'renewal', null),
 ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Tolcon Group (Pty) Ltd.', 'Construction', '{Kempton Park}', 80, 'MCO-TOLC', '10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'Website organic', '2020-02-01', 'clinic_day', null),
 ('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'Nuvest Chemicals', 'Chemicals', '{Sasolburg}', 30, 'MCO-NUV', '10000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000002', 'Referral', '2023-09-01', 'schedule', null),
 ('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'CGI Industries', 'Manufacturing', '{Germiston}', 12, 'MCO-CGI', '10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'Event', '2022-11-01', 'certificates', null);

insert into client_contact (tenant_id, client_id, display_name, role, is_primary) values
 ('00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Thabo N.', 'HR manager', true),
 ('00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Riaan v.d. B.', 'SHEQ officer', false),
 ('00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Accounts payable', 'invoices and purchase orders', false);

insert into template (id, tenant_id, key, name, version, description) values
 ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'renewal_ladder', 'Renewal ladder', 3, '90, 60 and 30 days before expiry, then clinic days and certificates'),
 ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'discovery_to_close', 'Discovery to close', 2, null),
 ('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'proposal_checklist', 'Proposal production checklist', 1, null),
 ('30000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'onboarding_handover', 'Onboarding handover to clinic operations', 1, null),
 ('30000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'non_arrival_recovery', 'Non arrival recovery', 2, 'SLA 2 days');

insert into template_item (template_id, position, title, stage, offset_days, duration_days, default_role, depends_on_position, agent_key, requires_signature) values
 ('30000000-0000-0000-0000-000000000001', 1, 'Confirm employee list and sites with the HR contact', 'renewal', -30, 2, 'sales_consultant', null, 'booking', false),
 ('30000000-0000-0000-0000-000000000001', 2, 'Send booking proposal', 'schedule', -28, 1, 'sales_consultant', 1, 'booking', true),
 ('30000000-0000-0000-0000-000000000001', 3, 'Reserve mobile clinic slots', 'schedule', -24, 2, 'sales_consultant', 2, 'booking', false),
 ('30000000-0000-0000-0000-000000000001', 4, 'Collect outstanding ID copies', 'certificates', -27, 6, 'sales_consultant', null, 'documentation', false),
 ('30000000-0000-0000-0000-000000000001', 5, 'Raise pro forma invoice', 'invoice', -21, 2, 'sales_manager', 1, 'documentation', true),
 ('30000000-0000-0000-0000-000000000005', 1, 'Call the client contact about the non arrivals', 'clinic_day', 0, 1, 'sales_consultant', null, 'follow_up', false),
 ('30000000-0000-0000-0000-000000000005', 2, 'Draft the rebooking offer', 'clinic_day', 0, 1, 'sales_consultant', 1, 'follow_up', true),
 ('30000000-0000-0000-0000-000000000005', 3, 'Reserve rebooking slots', 'schedule', 1, 1, 'sales_consultant', 2, 'booking', false),
 ('30000000-0000-0000-0000-000000000005', 4, 'Confirm attendance in MCO', 'clinic_day', 2, 1, 'sales_consultant', 3, null, false);

insert into rule (tenant_id, ref, name, trigger, agent_key, action, guard, owner_id, threshold_medicals) values
 ('00000000-0000-0000-0000-000000000001', 'R-01', 'New MCO task of any type', 'mco_task_created', 'documentation', 'Create a portal parent task, link the MCO id, place it on the journey stage mapped from the task type', null, '10000000-0000-0000-0000-000000000002', null),
 ('00000000-0000-0000-0000-000000000001', 'R-02', 'Medicals Due, new', 'mco_type:Medicals Due', 'booking', 'Allocate to the account owner and draft renewal subtasks', 'Over 20 medicals [CONFIRM]: Sales Manager signs before allocation', '10000000-0000-0000-0000-000000000002', 20),
 ('00000000-0000-0000-0000-000000000001', 'R-03', 'Medicals Overdue, new', 'mco_type:Medicals Overdue', 'follow_up', 'Escalate to account owner and Sales Manager, draft the recovery call script, set priority High', 'Never contacts the client directly', '10000000-0000-0000-0000-000000000002', null),
 ('00000000-0000-0000-0000-000000000001', 'R-04', 'Non arrival logged', 'mco_type:Non Arrival', 'booking', 'Create the rebooking subtasks under the clinic day parent and notify the consultant the same day', null, '10000000-0000-0000-0000-000000000004', null),
 ('00000000-0000-0000-0000-000000000001', 'R-05', 'Medicals: ID Pending or Documents', 'mco_type:Medicals: ID Pending', 'documentation', 'Draft the document request, attach the MCO case list, close when MCO shows received', null, '10000000-0000-0000-0000-000000000003', null),
 ('00000000-0000-0000-0000-000000000001', 'R-06', 'Any subtask drafts an outbound email', 'subtask_drafts_email', 'follow_up', 'Hold in Awaiting approval until the assigned person or their Sales Manager signs', 'Hard stop, POPIA: no employee name or medical outcome in an email body', '10000000-0000-0000-0000-000000000002', null),
 ('00000000-0000-0000-0000-000000000001', 'R-07', 'Consultant load above capacity', 'load_above_capacity', 'allocation', 'Standard task to the consultant with the largest book gap, high profile client to a senior with room, Sales Manager confirms', null, '10000000-0000-0000-0000-000000000002', null),
 ('00000000-0000-0000-0000-000000000001', 'R-08', 'Medical expiry date known', 'expiry_known', 'booking', 'Generate the renewal ladder at 90, 60 and 30 days before expiry, tagged [CONFIRM] until the account owner accepts the calendar once', null, '10000000-0000-0000-0000-000000000002', null),
 ('00000000-0000-0000-0000-000000000001', 'R-09', 'Transcript, flagged email or Teams message', 'capture', 'capture', 'Extract draft tasks with their source reference and hold them in Inbox under Captured', 'Reads untrusted input: holds no secret rights, writes only to agent_report', '10000000-0000-0000-0000-000000000001', null);

insert into sla_policy (tenant_id, task_type, hours_to_resolve) values
 ('00000000-0000-0000-0000-000000000001', 'Non Arrival', 48),
 ('00000000-0000-0000-0000-000000000001', 'Medicals: ID Pending', 120),
 ('00000000-0000-0000-0000-000000000001', 'Medicals Overdue', 72);

insert into integration_sync (tenant_id, connector, status) values
 ('00000000-0000-0000-0000-000000000001', 'mco', 'ok'), ('00000000-0000-0000-0000-000000000001', 'graph_mail', 'paused'),
 ('00000000-0000-0000-0000-000000000001', 'graph_calendar', 'paused'), ('00000000-0000-0000-0000-000000000001', 'fireflies', 'paused'),
 ('00000000-0000-0000-0000-000000000001', 'teams_transcript', 'paused'), ('00000000-0000-0000-0000-000000000001', 'sharepoint', 'paused'),
 ('00000000-0000-0000-0000-000000000001', 'zoom', 'paused'), ('00000000-0000-0000-0000-000000000001', 'translator', 'paused'),
 ('00000000-0000-0000-0000-000000000001', 'grok', 'paused');

-- MCO rows exactly as in the MyClinicOnline screenshot (names replaced by counts where a person was named)
insert into mco_task (tenant_id, mco_id, task_type, status, created_at_mco, due_date, created_by_name, assigned_user_name, assigned_user_email, client_name, description, medical_count, window_from, window_to) values
 ('00000000-0000-0000-0000-000000000001', '48213', 'Medicals Due', 'New', '2026-09-01 09:30', '2026-09-16', 'Celeste Bulpitt', 'Celeste Bulpitt', 'celeste@carenetconsultants.co.za', 'Pt Operational Services (Pty) Ltd', '97x Medical(s) expiring for Pt Operational Services (Pty) Ltd in between 01/10/2026 and 31/10/2026', 97, '2026-10-01', '2026-10-31'),
 ('00000000-0000-0000-0000-000000000001', '48214', 'Medicals Due', 'New', '2026-09-01 09:30', '2026-09-16', 'Celeste Bulpitt', 'Celeste Bulpitt', 'celeste@carenetconsultants.co.za', 'Afrirent Auto (Pty) Ltd', '26x Medical(s) expiring for Afrirent Auto (Pty) Ltd in between 01/10/2026 and 31/10/2026', 26, '2026-10-01', '2026-10-31'),
 ('00000000-0000-0000-0000-000000000001', '48215', 'Medicals Due', 'New', '2026-09-01 09:30', '2026-09-16', 'Celeste Bulpitt', 'Celeste Bulpitt', 'celeste@carenetconsultants.co.za', 'Tolcon Group (Pty) Ltd.', '24x Medical(s) expiring for Tolcon Group (Pty) Ltd. in between 01/10/2026 and 31/10/2026', 24, '2026-10-01', '2026-10-31'),
 ('00000000-0000-0000-0000-000000000001', '48216', 'Medicals Due', 'New', '2026-09-01 09:30', '2026-09-16', 'Celeste Bulpitt', 'Celeste Bulpitt', 'celeste@carenetconsultants.co.za', 'Nuvest Chemicals', '4x Medical(s) expiring for Nuvest Chemicals in between 01/10/2026 and 31/10/2026', 4, '2026-10-01', '2026-10-31'),
 ('00000000-0000-0000-0000-000000000001', '48217', 'Medicals Due', 'New', '2026-09-01 06:01', '2026-09-16', 'Celeste Bulpitt', 'Celeste Bulpitt', 'celeste@carenetconsultants.co.za', 'CGI Industries', '1x Medical(s) expiring for CGI Industries in between 01/10/2026 and 31/10/2026', 1, '2026-10-01', '2026-10-31'),
 ('00000000-0000-0000-0000-000000000001', '48101', 'Non Arrival', 'New', '2026-08-28 17:00', '2026-09-01', 'Asandiswa Ntsali', 'Celeste Bulpitt', 'celeste@carenetconsultants.co.za', 'Tolcon Group (Pty) Ltd.', '3 employees did not arrive for the clinic day on 28/08/2026', 3, null, null),
 ('00000000-0000-0000-0000-000000000001', '48090', 'Medicals: ID Pending', 'New', '2026-08-26 10:00', '2026-09-02', 'Celeste Bulpitt', 'Celeste Bulpitt', 'celeste@carenetconsultants.co.za', 'CGI Industries', 'ID copy pending for 1 employee, case 4471', 1, null, null);
