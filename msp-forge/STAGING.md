# Staging deployment

A Vercel project that serves the whole build from this repository so it can be
opened, clicked through and moved, without touching the live Care Net website.

| | |
| --- | --- |
| Vercel project | `cnc-msp-forge-staging` |
| Team | AutoHive Wesite Developers |
| Repository | `Barteldt/Care-Net-Consultants` |
| Root directory | `msp-forge/vercel` |
| Branch deployed | `claude/build-run-mitkxf` |

This project has no custom domain attached, so it can never answer for
carenetconsultants.co.za. Moving it later is a domain change on the project, not
a rebuild.

## What works on staging with no further configuration

These read the framework in the browser through the two public views, using the
publishable key that is already public in the page source.

- `/medical-surveillance-plans`, the service page, with the live statistics band
- `/industry?code=XXX`, the full journey for any of the 17 industries
- `/method` and `/pilot`, the explanation and the walkthrough
- `/samples/CNC-MSP-SAMPLE-Construction.pdf`, the watermarked sample plan
- Sign in on `/account`, `/review` and `/settings`, through Supabase Auth

## What needs two environment variables before it answers

Every transactional path runs through a server endpoint holding the service key.
Set these in the staging project settings and redeploy, and all of them turn on
at once.

| Variable | Value |
| --- | --- |
| `SUPABASE_URL` | `https://pboebfnujzffgwctsplw.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | the service role key, from the Supabase project API settings |
| `ADMIN_ACTION_SECRET` | any long random string, for payment confirmation |
| `DOCUSEAL_WEBHOOK_SECRET` | the shared secret also set on the DocuSeal webhook |

Quotations, company sign on, company lookup, assessment links, assessment
submission, payment confirmation and the signature webhook all depend on the
first two. Nothing else is required and there are no code changes.

The assistant needs one more, and it lives in Supabase rather than Vercel:
`ANTHROPIC_API_KEY` in the Supabase project's function secrets. Until it is set,
the assistant answers that it is not configured and records the refusal.

## Moving it to the real site later

The pages reference fonts by absolute path, `/fonts/`, so wherever they are
published those three files must sit at the site root. The canonical, og:url,
hreflang and breadcrumb items on the service page point at
`www.carenetconsultants.co.za/medical-surveillance-plans`; if the final slug
differs, those four places change together.
