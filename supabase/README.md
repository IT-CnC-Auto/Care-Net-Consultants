# Supabase - Care Net Internal Portal

This directory is the migration source of truth for the **Care Net - Internal Portal**
Supabase project (`sefgzjjppzaesfkpznpe`, eu-west-2), which backs the internal portal
(finance snapshot, sales pipeline read model, MA-CN-003 sales assistant, executive
snapshot).

## Where these migrations came from

The 11 files in `migrations/` are an exact copy of the project's applied migration
history, extracted from `supabase_migrations.schema_migrations` on 18/08/2026.
Because the versions and names match what production has already applied, connecting
the Supabase GitHub integration to this repository results in a **no-op first sync**:
nothing is re-applied, and repo and database start in agreement.

Do not edit or rename the existing migration files. They are history, not templates.

## Workflow for schema changes

1. Add a new file `migrations/<YYYYMMDDHHMMSS>_<short_name>.sql` (UTC timestamp).
2. Open a pull request into `main`. Schema changes ride the same review path as code.
3. On merge to `main`, the Supabase GitHub integration applies any migration not yet
   in the remote history. `main` is production for this database: a merged migration
   is a live schema change on the portal.

## Rules

- Schema only. Never commit data, secrets, keys, or connection strings here.
- POPIA: this database holds personal information under RLS. Any migration touching
  `user_profiles`, storage policies, or RLS must preserve the existing protections.
  Patient clinical data never enters this project (it lives on MyClinicOnline only).
- Tables owned by sync bridges (`sales_pipeline_opportunity`, `finance_snapshot`,
  `executive_snapshot`, `sales_assistant_brief`) are written by edge functions via
  the service role. Migrations may alter their shape, never their data.
