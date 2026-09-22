# Cognitive Kernel backup manifest

Regenerated 15/08/2026. Framework version 1.0.0 plus the productisation, shop journey, public marketing views, runtime parameter store and assistant connection migrations.

Kernel counts at backup: 31 verified instruments (1 retired duplicate, 5 pending and uncitable), 17 industries, 56 of 56 selectable subindustries, 316 roles, 851 hazard links, 30 protocols, 2 shop packages.

## Migrations included

- 001_msp_kernel_schema.sql (6253 bytes)
- 002_msp_kernel_rls.sql (6339 bytes)
- 003_msp_kernel_verification.sql (4608 bytes)
- 004_msp_seed_construction.sql (36093 bytes)
- 005_msp_intake_schema.sql (9253 bytes)
- 006_msp_ingest_intake.sql (7544 bytes)
- 007_msp_draft_review.sql (4912 bytes)
- 008_msp_omp_workflow.sql (10142 bytes)
- 009_msp_commercial_clinical.sql (13883 bytes)
- 010_msp_batch_manufacturing.sql (24810 bytes)
- 011_msp_batch_mining.sql (20451 bytes)
- 012_msp_batch_transport.sql (17109 bytes)
- 013_msp_batch_agri_health.sql (24046 bytes)
- 014_msp_batch_util_sec_clean.sql (24540 bytes)
- 015_msp_batch_retail.sql (14731 bytes)
- 016_msp_batch_hospitality.sql (14215 bytes)
- 017_msp_batch_waste.sql (14537 bytes)
- 018_msp_batch_telecoms.sql (15114 bytes)
- 019_msp_batch_petrochem.sql (15110 bytes)
- 020_msp_batch_government.sql (15566 bytes)
- 021_msp_batch_education.sql (11673 bytes)
- 022_msp_batch_office.sql (9869 bytes)
- 023_msp_batch_held_constr_port_air.sql (15008 bytes)
- 024_msp_batch_held_mining_hosp.sql (16099 bytes)
- 025_msp_batch_held_manufacturing.sql (14161 bytes)
- 026_msp_register_closures.sql (7038 bytes)
- 027_msp_constr_instrument_backfill.sql (1659 bytes)
- 028_msp_dmr_industry_sweep.sql (1892 bytes)
- 029_msp_r638_dedup.sql (3284 bytes)
- 030_msp_cognitive_kernel_product.sql (13412 bytes)
- 031_msp_shop_journey.sql (8549 bytes)
- 032_msp_quote_status_fix.sql (451 bytes)
- 033_msp_public_industry_profile.sql (3620 bytes)
- 034_msp_env_parameters_ai.sql (20410 bytes)
- 035_msp_agent_schedule.sql (7490 bytes)
- 036_msp_ai_identity_limits.sql (5321 bytes)
- 037_msp_env_ai_grant_lockdown.sql (3862 bytes)
- 038_msp_audit_schedule_dedup.sql (2246 bytes)
- 039_msp_client_signon.sql (2912 bytes)
- 040_msp_self_service_access.sql (5534 bytes)
- 041_msp_gap_safe_reference.sql (1425 bytes)
- 042_msp_legislation_currency_2026_09.sql (40893 bytes)
- 043_msp_client_contact_number.sql (4161 bytes)
- 044_msp_intake_draft.sql (6521 bytes)
- 045_msp_review_fee_bands.sql (9024 bytes)
- 046_msp_public_instrument_register.sql (1511 bytes)

## Not SQL, and therefore not in the rebuild script

- supabase/functions/msp-assistant/index.ts, the assistant connection. Deploy it separately.
- vercel/settings.html, the settings page that reads and writes the parameter store.
- WIRING.html, the system reference: every page, endpoint, table, function, parameter and scheduled job, read from the live project.
- Two secrets that are never in this repository and never in the database: ANTHROPIC_API_KEY in Supabase secrets, and the service role key in the Vercel project.

## Rebuild procedure

1. Create an empty Supabase project.
2. Replay cognitive_kernel_rebuild.sql (or the migrations in order).
3. Configure roles via JWT app_metadata.msp_roles: forge_agent, forge_verifier, forge_omp, forge_admin.
4. Prove the rebuild: run agent/run_pipeline.js with agent/kernel_snapshot_constr.json and test/normalised_synthetic.json; require 9 of 9 validation checks, then render and require 16 of 16 geometry assertions.
5. Deploy the assistant connection: supabase/functions/msp-assistant/index.ts, and set ANTHROPIC_API_KEY in the project's function secrets. Without that key the connection answers that it is not configured and records the refusal.
6. Confirm the schedule: msp_agent_schedule_status() should show job msp_monthly_audit on the day and hour held in the agent parameters.
7. Follow SOP-KERNEL-AGENT.md for the monthly maintenance agent, the parameter store and version control.
