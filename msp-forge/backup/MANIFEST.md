# Cognitive Kernel backup manifest

Generated 14/08/2026. Kernel version 1.0.0 plus the productisation and shop journey migrations.

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

## Rebuild procedure

1. Create an empty Supabase project.
2. Replay cognitive_kernel_rebuild.sql (or the migrations in order).
3. Configure roles via JWT app_metadata.msp_roles: forge_agent, forge_verifier, forge_omp, forge_admin.
4. Prove the rebuild: run agent/run_pipeline.js with agent/kernel_snapshot_constr.json and test/normalised_synthetic.json; require 9 of 9 validation checks, then render and require 16 of 16 geometry assertions.
5. Follow SOP-KERNEL-AGENT.md for the monthly maintenance agent and version control.
