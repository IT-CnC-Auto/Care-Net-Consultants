-- Remove the permissive anon/public write policy left over from the Make.com writer.
drop policy if exists "Anon can upsert finance snapshot" on public.finance_snapshot;

-- Revoke table-level write grants from anon/authenticated (defence in depth).
-- The snapshot is written ONLY by the sync-finance-from-nexus edge function via the
-- service role, which bypasses RLS and keeps its grants. Dashboard read (anon SELECT)
-- stays intact via the "Portal can read finance snapshot" policy + SELECT grant.
revoke insert, update, delete, truncate on public.finance_snapshot from anon, authenticated;
