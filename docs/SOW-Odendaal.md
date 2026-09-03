# Scope of work: Odendaal · Care Net sales tasks module, link and go live

Version 1.0 | 3 September 2026 | Prepared for Odendaal by Barteldt Kruger, Care Net Consultants
British English. Every figure marked [CONFIRM] is unverified until you check it against the live account.

## 1. Purpose

1.1 The sales tasks module is built. The code, schema, Edge Functions and portal are on GitHub. Your job is to link it to Care Net's live Supabase project, Microsoft 365 tenant, Fireflies, xAI and Azure, deploy the portal on Vercel, prove the access rules, and hand a working system to the Sales Manager.

1.2 You are not being asked to design or build features. Where you find a gap, log it in the confirmation register in section 9 and carry on. Do not change the parent and child oversight model, the human gate rule, or the POPIA scrub without speaking to Barteldt first.

## 2. Where everything is

| Item | Location |
|------|----------|
| Repository | https://github.com/barteldt/care_net_consultants_sales_dashboard_testing_environment |
| Branch to deploy | `claude/ai-tasks-management-ui-1whlpc` (merge to `main` after go live sign off) |
| Portal source | `portal/` (Next.js 15, App Router, Tailwind, Supabase Auth) |
| Database | `supabase/migrations/0001_foundation.sql`, `0002_task_engine.sql`, `0003_rules_and_agents.sql` |
| Demo fixtures | `supabase/seed.sql` (mock data, use on staging only) |
| Edge Functions | `supabase/functions/*` (13 functions, shared code in `_shared/`) |
| Environment variables | `portal/.env.example` lists every key for the portal and the functions |
| Design canvas (what the portal must look like) | https://claude.ai/code/artifact/76de52ee-9287-4de9-b031-0948b4213a96 |
| Design tokens and handoff notes | `design/README.md`, `design/tokens/` |
| Integration decisions and reasoning | `design/specs/INTEGRATIONS.md` |
| Live portal after deploy | `https://tasks.carenetconsultants.co.za` [CONFIRM domain], Vercel preview URLs per branch |

## 3. Deliverables

3.1 A Supabase project (production) with the three migrations applied, RLS proven by the tests in section 6, pg_cron schedules running, secrets in Vault, and the MCO sync landing rows in `mco_task`.
3.2 A staging Supabase project or branch with the seed data, used for every test before production.
3.3 Thirteen Edge Functions deployed and reachable, each with its secrets set.
3.4 An Entra app registration with least privilege Graph permissions and admin consent recorded.
3.5 Supabase Auth configured for Microsoft sign in, with the seven Care Net people able to sign in and land on the right desk.
3.6 The portal deployed on Vercel, custom domain, environment variables set, preview deployments per pull request.
3.7 Fireflies webhook, Azure Translator and xAI keys connected and showing "Live" on the Data and connections screen.
3.8 A short runbook (one page) for the Sales Manager: how to pause an agent, how to read the dead letter list, who to call.

## 4. Sequence of work

Work the phases in order. Each phase has a stop point. Send Barteldt a one line message at each stop.

### 4.1 Phase 0 · Foundation (day 1 to 2)

1. Create the production Supabase project in the region agreed with the Information Officer [CONFIRM region, af-south-1 if available]. Note the project ref, URL, anon key and service role key. The service role key never leaves Supabase secrets and Vercel server variables.
2. Install the Supabase CLI. `supabase link --project-ref <ref>`.
3. Apply migrations: `supabase db push`. Confirm the tables `tenant, person, client, task, approval, rule, agent_run, audit_log` exist.
4. Set the database settings used by pg_cron to call functions:
   ```sql
   alter database postgres set app.settings.functions_url = 'https://<ref>.functions.supabase.co';
   alter database postgres set app.settings.service_key = '<service role key>';
   ```
   Confirm `pg_cron` and `pg_net` show under Database → Extensions.
5. Create a staging project (or a Supabase branch) and run `supabase db push` then `psql -f supabase/seed.sql` there. Never seed production.
6. Insert the real tenant and people into production. Use `supabase/seed.sql` as the shape: one row in `tenant`, one row per person in `person` with the correct `manager_id` (the oversight tree) and `role`. Email must match the Microsoft 365 sign in address exactly, lower case.
Stop point: Barteldt confirms the people list and the tree.

### 4.2 Phase 1 · Task engine, portal, first connectors (day 3 to 8)

1. Entra app registration (Azure portal → Microsoft Entra ID → App registrations → New):
   - Name: Care Net Tasks Portal. Single tenant.
   - Redirect URI (web): `https://<ref>.supabase.co/auth/v1/callback`.
   - Certificates and secrets: one client secret, 12 months, note the expiry in the register.
   - API permissions, Application type: `Mail.Read`, `Calendars.Read`, `Sites.Selected`, `OnlineMeetingTranscript.Read.All` (phase 2). Delegated: `openid, email, profile, User.Read`.
   - Grant admin consent. Record the date and who consented.
   - Restrict `Mail.Read` to consented mailboxes only with an Exchange application access policy (`New-ApplicationAccessPolicy`). Do not leave it tenant wide.
2. Supabase Auth → Providers → Azure: client id, secret, tenant URL `https://login.microsoftonline.com/<tenant id>/v2.0`. Set Site URL to the portal domain and add `https://tasks.carenetconsultants.co.za/auth/callback` to redirect URLs.
3. Function secrets: `supabase secrets set` for every key in `portal/.env.example` under the Edge Functions heading. Leave Zoom and STT blank until phase 3.
4. Deploy functions: `supabase functions deploy` (all). Confirm each appears under Edge Functions and that `verify_jwt` matches `supabase/config.toml` (webhooks are public, portal calls require a JWT).
5. xAI: create an API key on the xAI console, note the model available and its price [CONFIRM `grok-4-fast` name and rate]. Set `XAI_API_KEY` and `GROK_MODEL`.
6. Azure AI Translator: create the resource on the free F0 tier in the same subscription as M365 [CONFIRM tier and region]. Set `AZURE_TRANSLATOR_KEY` and `AZURE_TRANSLATOR_REGION`.
7. Fireflies: Settings → Developer → API key. Webhook URL `https://<ref>.functions.supabase.co/capture-fireflies`. Set a shared secret and store it as `FIREFLIES_WEBHOOK_SECRET`.
8. MCO sync: confirm how MyClinicOnline rows already reach Supabase [CONFIRM: existing sync, Make scenario or Excel export]. Point that sync at the `mco_task` table using the columns in `0002_task_engine.sql`. The `mco_id` column must be MCO's own task id so re-syncs upsert rather than duplicate.
9. Vercel: import the repository, root directory `portal/`, framework Next.js. Environment variables: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_FUNCTIONS_URL`, `NEXT_PUBLIC_PORTAL_URL`, and `NEXT_PUBLIC_DEMO_DATA=true` on staging only. Add the custom domain and the DNS CNAME.
10. Graph mail subscriptions: for each consultant who opts in, call `GET https://<ref>.functions.supabase.co/graph-mail-flag?subscribe=<person uuid>` once. The 12 hourly renewal job is already scheduled.
11. Run the tests in section 6.
Stop point: Sales Manager signs in, sees the Team board, approves one agent allocation in Inbox, and the task moves to the consultant.

### 4.3 Phase 2 · Teams transcript, SharePoint, Teams exceptions (day 9 to 11)

1. Graph transcript subscription: `GET .../graph-transcript?subscribe=1` after admin consent for `OnlineMeetingTranscript.Read.All`. Confirm whether the API is metered on this tenant [CONFIRM] before enabling for everyone.
2. SharePoint: for each client library, grant the app `write` with `Sites.Selected` (Graph `POST /sites/{id}/permissions`). Record `sharepoint_site_id` and `sharepoint_drive_id` on the `client` row. Upload the three templates (proposal, attendance list, pro forma) to a templates library and set the item ids in secrets.
3. Teams: create an incoming webhook (Workflows) on the Sales channel and set `TEAMS_EXCEPTIONS_WEBHOOK_URL`.
Stop point: one meeting transcript from Teams lands in Inbox as Captured without Fireflies.

### 4.4 Phase 3 · Zoom and speech fallback (only if required)

1. Only if a client insists on Zoom [CONFIRM C21]. Zoom Marketplace → Webhook only app → event `recording.completed`, endpoint `.../zoom-webhook`, copy the secret token to `ZOOM_WEBHOOK_SECRET_TOKEN`.
2. Speech fallback: set `STT_PROVIDER_URL`, `STT_PROVIDER_KEY`, `STT_MODEL` for a Whisper class endpoint [CONFIRM provider and price, about USD 0.006 a minute].

## 5. Supabase structure you are linking

5.1 One tenant, one Task table. A subtask is a task with `parent_id`. A checklist item is a single tick under a task. Every other object (approval, captured item, rule run, agent run) points back to a task.

5.2 The oversight tree is `person.manager_id`. RLS uses `my_subtree()` so a person sees their own tasks plus everything owned by people below them. `franchise_director` sees all. `information_officer` sees audit and consent tables only. `agent` is a service account row so allocations and audit entries can name it.

5.3 Human gates are rows in `approval`. Nothing sends, allocates over threshold or closes from MCO until a row is approved through `approvals-act`, which checks the approver is the named signer or their manager.

5.4 Connectors write to `integration_sync` (status per connector) and to `dead_letter` on failure. The Data and connections screen reads both. Check dead letters daily during the first two weeks.

5.5 Schedules (pg_cron): `mco-sync-15m`, `sla-predict-hourly`, `mark-overdue-hourly`, `daily-digest-0700-sast` (05:00 UTC), `teams-exceptions-hourly`, `graph-subscriptions-renew`.

5.6 POPIA: `client_contact` holds names and roles only, `mco_task.description` is scrubbed of employee names before an agent sees it, transcripts are never stored, extracts expire after 90 days [CONFIRM C22], and `emailBodyIsSafe` blocks any outbound body naming a person with a health term. Do not add columns for email, phone or medical outcomes anywhere in this schema.

## 6. Acceptance tests (run on staging, then production)

| # | Test | Pass when |
|---|------|-----------|
| T1 | Sign in as a consultant | Lands on Desk, sees only own tasks, cannot open another consultant's task URL (404) |
| T2 | Sign in as Sales Manager | Sees all consultants' tasks on Team board, can toggle a rule's kill switch |
| T3 | Sign in as Information Officer | Sees audit log entries, gets no rows from `task` |
| T4 | Insert one `mco_task` row with 97 medicals, run `mco-sync` | Parent task created on Renewal, subtasks drafted, a `threshold` approval appears for the Sales Manager, nothing allocated yet |
| T5 | Approve the threshold in Inbox | Parent and subtasks assigned to the account owner, audit row written |
| T6 | Insert an `mco_task` row whose description names a person | Task title shows a count, not the name |
| T7 | Send a Fireflies webhook for a test meeting | Captured item and approval appear, `health_lines_dropped` counted, transcript not stored anywhere |
| T8 | Flag an email in a consented mailbox | One proposed task appears within a minute |
| T9 | Approve an outbound email whose draft contains an identity number | Blocked with reason, nothing sent |
| T10 | Stop the MCO sync for an hour | Data and connections shows the connector failed, Teams exceptions card posts |
| T11 | Excel report | CSV downloads, audit row `export.csv` written |
| T12 | Attempt a query with a consultant's JWT against Tenant B data (create a second tenant on staging) | Zero rows |

## 7. What you will need from Care Net

7.1 Global administrator for the Microsoft 365 tenant for one session (Entra app, admin consent, Exchange access policy).
7.2 Owner access on the Supabase organisation and the Vercel team.
7.3 The MCO sync owner or export contact.
7.4 The Fireflies account owner.
7.5 A company card for xAI and Azure (both under R200 a month at expected volume [CONFIRM]).
7.6 The final list of people, roles and who reports to whom.

## 8. Time and cost

8.1 Effort estimate: 11 working days for phases 0 to 2, 2 more days for phase 3 if Zoom is required. [CONFIRM rate and whether this is time and materials]
8.2 New running cost: about R555 a month plus VAT (Supabase Pro, Grok usage, Azure Translator on free tier, Graph at no charge). Fireflies, Make and Microsoft 365 are already paid. Every price is [CONFIRM] against the live accounts.
8.3 Out of scope: changes to MyClinicOnline, AutoHive CRM configuration, clinic operations, finance and HR modules, mobile app.

## 9. Confirmation register

| Ref | Item | Owner | Status |
|-----|------|-------|--------|
| C1 | Supabase and Azure region, cross border wording | Information Officer | open |
| C2 | Portal domain `tasks.carenetconsultants.co.za` | Barteldt | open |
| C3 | People, roles and oversight tree | Sales Manager | open |
| C4 | 20 medical threshold for Sales Manager sign off | Sales Manager | open |
| C5 | MCO sync mechanism into `mco_task` | MCO contact | open |
| C6 | xAI model name and price | Odendaal | open |
| C7 | Graph transcript API metering on this tenant | M365 administrator | open |
| C8 | Fireflies plan and seats | Barteldt | open |
| C9 | Transcript extract retention, default 90 days | Information Officer | open |
| C10 | Zoom required by any client | Sales Manager | open |
| C11 | Attribution pill in the footer per licence tier | Barteldt | open |
| C12 | Odendaal's rate and engagement basis | Barteldt | open |

## 10. Definition of done

10.1 All twelve acceptance tests pass on production with real people and real MCO rows.
10.2 The Sales Manager has approved at least one agent allocation and one outbound email through the portal.
10.3 Dead letters are empty for five consecutive working days.
10.4 The runbook in 3.8 is in the Sales SharePoint library.
10.5 The branch is merged to `main` and the Vercel production deployment points at `main`.
