# Care Net Cognitive Kernel | Agent SOP | v1.1.0 | 15/08/2026

Standard operating procedure for maintaining the Care Net Cognitive Kernel as a living, versioned product, and for building and linking the smart agents that keep it correct. The Cognitive Kernel is a Care Net Consultants product. It lives in the Supabase project (all objects prefixed msp_), and the migrations directory in this repository is its canonical, replayable source.

## 1. What the Cognitive Kernel is

The kernel is the sole legal truth of the engine: triple verified legal instruments, hazards with verified exposure values, test protocols with dual justification (hazard basis plus EEA section 7), the industry and role taxonomy, kernel rules (compensation routing, the noise transition, exceedance tightening, the employer as payer), and the confirmation register that tracks every open assumption. Nothing reaches a client deliverable unless the kernel can cite it as verified, and no pack releases without a registered OMP's approval, enforced in the database.

## 2. Version control

- Every content release is a row in `msp_kernel_version` (semver, change summary, live counts snapshot, OMP ratification fields). Version 1.0.0 covers migrations 001 to 029.
- Releases are cut with `msp_kernel_release(semver, summary)`, callable only with the `forge_admin` role. Content changes bump minor; corrections bump patch; a change to a kernel rule or protocol structure bumps major.
- A release is not citable as ratified until an OMP sets `omp_ratified` with name and date. The engine keeps operating on the prior ratified posture meanwhile.
- The git history of `supabase/migrations/` is the parallel source control: database state and repository state must always agree, and the backup procedure below proves it can be rebuilt from either.

## 3. The monthly maintenance agent

Two legs, both landing in `msp_kernel_agent_run`.

### Leg 1: correctness audit (automated, in the database)

`msp_kernel_monthly_audit()` runs the standing checks: kernel counts, the verification watchdog (`msp_verification_due`, instruments whose review date is within 60 days), unprotocolled hazards outside the narrative codes, and the dash punctuation scan across every text column. It writes the report and outcome (`clean` or `findings`) to `msp_kernel_agent_run` and the audit trail.

This is scheduled and running. `pg_cron` job `msp_monthly_audit` calls it on the day and hour held in the parameters `agent.monthly_audit_day` and `agent.monthly_audit_hour_utc`, currently the first of the month at 02:00 UTC. The schedule is not written into a cron string by hand: changing either parameter calls `msp_agent_reschedule()` in the same action and moves the job. `msp_agent_schedule_status()` reports what is actually scheduled, and the settings page shows it, so the claim and the reality can always be compared.

### Leg 2: learning update (agent driven)

A Claude agent session (Claude Code, or a scheduled cloud session) runs monthly with access to this repository and the Supabase project, and works the findings:

1. Call `msp_kernel_monthly_audit()` and read the latest `msp_kernel_agent_run` row.
2. For every instrument on the watchdog: re verify currency against primary sources (gazette records, SAFLII, the department publications). Apply the triple verification discipline: gate a primary text, gate b independent corroboration, gate c currency check. Update `amendment_history` and `review_due` through the verification workflow functions; never edit a verified row casually.
3. Sweep for new law: promulgations, amendments, repeal notices in the period. New instruments enter as `pending` and pass the three gates before citation. Known standing watches: the NIHL to Noise Exposure Regulations transition on 06/09/2026, the draft General Machinery Regulation 2025 replacement, the COIDA amendment commencement schedule, and the ODMWA and NHI interaction.
4. Any change that tightens surveillance applies immediately; nothing ever loosens without OMP sign off (the exceedance rule).
5. Every applied change is a migration file in `supabase/migrations/` and an `apply_migration` call, never an ad hoc edit, so repository and database stay identical.
6. Close the run: insert a `learning_update` row into `msp_kernel_agent_run` with the report, cut a version with `msp_kernel_release` if content changed, and queue the release for OMP ratification.
7. Anything the agent cannot verify goes onto the confirmation register as an open item, not into the kernel.

### Wiring the agent to Supabase

- Server side agents use the service role key (held as an environment secret, never in the repository) or a dedicated `forge_verifier` JWT. The RPC surface is the contract: verification workflow functions, `msp_kernel_monthly_audit`, `msp_kernel_release`, and the OMP functions. Row level security holds for every path that is not service role.
- Scheduling options, in order of preference: a scheduled Claude cloud session (monthly Routine) that opens this repository and follows this SOP; a `pg_cron` job for the audit leg alone; or a manual monthly run of this SOP by a consultant with Claude Code.
- The agent writes nothing to client engagement data. Its writable surface is the kernel, the register, the agent run log, and the version register.

## 4. OMP industry review, demos, and tests

`msp_omp_industry_review` holds one row per industry (17 seeded, all `pending`). The review procedure per industry:

1. Generate a demo pack: run the pipeline against a synthetic intake for a representative subindustry (the committed Construction snapshot and synthetic intake in `agent/` and `test/` show the pattern; the pipeline validation must pass 9 of 9 and geometry 16 of 16).
2. The OMP reviews the demo pack in the review interface: framework instruments, role maps, exposure ratings, prescribed batteries, intervals, and the OMP notes the pipeline raises.
3. Record the outcome with `msp_omp_review_industry(code, status, name, hpcsa_number, notes)`: `demo_run` after the demo, then `approved` or `changes_requested` (both require the OMP name and HPCSA number). Changes route back through the batch pattern as migrations.
4. Kernel recommendations deploy per industry only once its review row is `approved`. The designated OMP is Dr C. P. Green-Thompson (HPCSA MP 0195952).

## 5. Clients on Supabase Auth and the free qualification rule

- Every client contact links to a Supabase Auth user through `msp_client_account.auth_user_id`; a client sees their own account row, packs, and revisions under their own login, and consultants manage accounts under `forge_admin`.
- Quotes capture `annual_medicals_estimate`. At 100 or more occupational medicals per year with Care Net, the quote prices at zero with status `free_qualifying`; a consultant verifies the declared volume before the waiver is confirmed (register item CR-13.15). Below the threshold, the rate card applies as before.
- The client journey is transparent by design: the landing page explains the flow (sign on or quotation, secure single use assessment link, HTML assessment form, engine draft against the verified kernel, OMP review and signature, delivery with revision numbers). The HTML forms are self contained and embeddable in any landing page or digital journey, and every document carries the dual brand band: CNC banner plus the client's prepared logo on every page.

## 6. The runtime parameter store

Everything that can sensibly be retuned without a deployment lives in `msp_env_parameter` and is changed on the settings page at `/settings.html`. Twenty nine parameters in five groups: the assistant, the monthly agent, clinical floors, commercial terms, and integrations.

- Read is open to any forge role through row level security on the table. Write is `forge_admin` only, and only through `msp_env_set`, which validates the type, the enum membership and the numeric range before it writes. A bad value is refused at the database, not caught in the browser.
- Every change appends to `msp_env_parameter_history` with the old value, the new value, who changed it, when, and why. That table is append only: a trigger refuses updates and deletes. A tuning change is a change to how the plans come out, so it is evidence.
- Secrets are never stored here. A parameter whose name reads like a credential may only carry a reference such as `supabase_secret:ANTHROPIC_API_KEY`, and a check constraint enforces that at the table.
- The clinical group needs care. `clinical.periodic_floor_months`, `clinical.record_retention_years`, `clinical.noise_action_level_db` and `clinical.omp_release_required` are regulatory minima carried in the framework, not preferences. Raising one needs a legal basis and a practitioner decision. The database gate on release is independent of the parameter, so switching `clinical.omp_release_required` off would not in fact release anything: the trigger still refuses.
- Anonymous visitors see nothing. The parameter table returns zero rows to the anonymous role and every reader function is revoked from it.

## 7. The assistant connection

The assistant is a Supabase edge function, `msp-assistant`, deployed to the same project. It carries no settings of its own: model, reasoning effort, thinking mode, output ceiling, monthly spend ceiling, hourly rate limits, the enabled action list and the token price table are all read from the parameter store on every single call.

Four actions: `industry_brief` and `triage_other` for staff, `explain_plan` for a signed in client company, and `monthly_watch` for the agent leg above.

What holds it inside the framework:

1. It answers only from framework rows handed to it in the same request. Those rows come from `msp_ai_context_industry` and `msp_ai_context_instruments`, both of which return verified instruments only and no client data at all.
2. It may not cite a law, a threshold or an interval that is not in those rows, and it may not express an opinion on any individual worker's fitness. Uncertainty routes to the practitioner.
3. Every answer carries the same notice: an explanation of the framework, not a clinical opinion and not a signed plan.
4. The instruction set is versioned by `ai.prompt_version`. Bump it whenever the guardrails change, so the ledger can say which rules were in force for any past answer.

What holds the cost:

- `msp_ai_preflight` runs before any spend: role check, master switch (`ai.enabled`), and the monthly ceiling. Over the ceiling the assistant refuses and says so.
- Every call lands in `msp_ai_call_log` with the model, effort, instruction version, tokens, priced cost, latency and outcome, including the refusals. `msp_ai_usage_summary()` feeds the usage tab on the settings page.
- Rate limits are per caller per hour, from `ai.client_hourly_limit` and `ai.staff_hourly_limit`.

Two secrets make it work and neither is in this repository or in the database: `ANTHROPIC_API_KEY` in Supabase secrets, and the service role key in the Vercel project.

## 8. Backup and rebuild

- Canonical backup: `supabase/migrations/001` through the latest, in order. Replaying them into an empty Supabase project rebuilds the entire kernel, workflows, policies, and seed content.
- Convenience backup: `backup/cognitive_kernel_rebuild.sql` is the concatenation of every migration in order, regenerated at each release alongside `backup/MANIFEST.md` (which records the version, migration list, and kernel counts at backup time).
- Runtime data (intakes, drafts, reviews, audit) is client data under POPIA and is not part of the kernel backup; it is covered by the Supabase project's own backups and the retention framework (40 year house floor for medical surveillance records).
- After any rebuild, prove it: run the pipeline regression (`agent/run_pipeline.js` with the committed snapshot and synthetic intake) and require 9 of 9 validation checks and 16 of 16 geometry assertions.

## 9. Standing disciplines

British English; no dash punctuation in prose (statute names keep their official hyphens); ZAR comma format; Arial; the CNC palette; OREP and WASP terminology; locked liability, POPIA, and sign off blocks verbatim; deliverables never carry CONFIRM or ASSUMPTION tags; Care Net screens and does not diagnose; the employer is always the payer; the WARDEN ring fence holds.
