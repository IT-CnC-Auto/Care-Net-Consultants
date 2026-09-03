# Care Net Consultants · Sales tasks module

AI tasks management for Care Net Consultants. MyClinicOnline (MCO) tasks land in Supabase, Grok agents read them,
create one parent task per client, draft subtasks along the client journey and propose who does the work.
AI drafts, a named human signs. Managers oversee through role rights enforced by Row Level Security.

| Folder | What it is |
|--------|------------|
| `portal/` | Next.js 15 App Router portal on Vercel. Tailwind with CNC tokens. Supabase Auth with Microsoft Entra. |
| `supabase/migrations/` | Postgres schema, RLS, views, pg_cron schedules. Phase 0 foundation, phase 1 task engine, rules and agents. |
| `supabase/seed.sql` | Demo fixtures matching the design canvas. Mock data only. |
| `supabase/functions/` | Deno Edge Functions: MCO sync, Grok extraction, Fireflies and Teams capture, Graph mail and calendar, translator, digest, approvals, SharePoint, Teams exceptions, Zoom, speech to text fallback. |
| `design/` | Claude Design artboards, tokens, integration spec. |
| `docs/` | Scope of work and runbooks. |

Phases: 0 Foundation · 1 Task engine, portal and phase 1 connectors · 2 Teams transcript, SharePoint, Teams exceptions · 3 Zoom and speech fallback.
Start with `docs/SOW-Odendaal.md`.
