# CNC MSP FORGE | Functional audit of the live site | 15/08/2026

> Addendum, later the same day: the runtime parameter store and the assistant connection were added after this audit was written. See the section "The parameter store and the assistant" at the end, which records what was built, what was tested, and the one secret still outstanding.

An honest account of what on the website is actually connected to the engine, what is not, and exactly why. Written because a site without a brain means nothing.

## The headline

Before this audit, every dynamic feature on the site was dead. Not broken code: unconfigured. Each one runs through a server function that needs `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in the Vercel project, and those variables have never been set. The pages rendered, the numbers were hard coded, and nothing reached the framework.

Half of that is now fixed and needs nothing from anybody. The rest cannot be fixed from this side, because it needs a secret only Care Net holds.

## What is connected now, with no configuration required

These read the live framework in the browser through two new public views, using the publishable key that is already public in the client pages. No server function, no secret, no deployment variable.

| Surface | What it reads | Status |
| --- | --- | --- |
| `/industry.html?code=XXX` | The whole page: instruments with applicability notes, subindustries and their job roles, hazards, protocols, for all 17 industries | Live |
| `/pilot.html` statistics band | Framework version and counts | Live |
| `/medical-surveillance-plans.html` KPI band | Industries, instruments, roles, protocols | Live |
| `/account.html`, `/review.html` sign in | Supabase Auth magic link | Live |

The two views are `msp_public_industry_profile` and `msp_public_framework_stats`, added in migration 033. They are deliberately readable by the anonymous role and carry only what Care Net publishes anyway: names, gazette applicability notes, role titles, hazard names, protocol names and counts.

## What is still dead, and the single reason why

Every one of these needs the service role key in the Vercel project. The code is written, tested against the database, and correct. It simply cannot authenticate.

| Surface | Function | Blocked on |
| --- | --- | --- |
| Quotation on the landing page and shop | `/api/quote` | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| Client sign on and company registration | `/api/signon` | same |
| Company status lookup after sign in | `/api/company-lookup` | same |
| Assessment link validation | `/api/access-check` | same |
| Assessment submission | `/api/intake` | same |
| Payment confirmation | `/api/payment-confirm` | same, plus `ADMIN_ACTION_SECRET` |
| Signature webhook | `/api/docuseal-webhook` | same, plus `DOCUSEAL_WEBHOOK_SECRET` |

Setting those four variables in the Vercel project settings and redeploying turns all of it on at once. Nothing else is required and no code changes.

## Security check performed during this audit

The public views were tested by assuming the anonymous role directly in the database and counting rows.

| Table or view | Rows visible to an anonymous visitor | Correct |
| --- | --- | --- |
| `msp_public_industry_profile` | 17 | Yes, this is the marketing surface |
| `msp_public_framework_stats` | 1 | Yes |
| `msp_legal_instrument` | 0 | Yes |
| `msp_intake` | 0 | Yes |
| `msp_engagement` | 0 | Yes |
| `msp_client_account` | 0 | Yes |
| `msp_draft` | 0 | Yes |
| `msp_audit` | 0 | Yes |

Row level security holds. The publishable key on the public pages reaches the two marketing views and nothing else.

## What exists but has never been exercised by a real user

These are complete and proven against synthetic data, but no live client has passed through them.

- The pipeline and document factory. Proven end to end: 9 of 9 validation checks and 16 of 16 geometry assertions on the pilot pack, most recently after the taxonomy scale out.
- The OMP review interface at `/review.html`. Complete, but no practitioner has signed in, because no Supabase Auth user carries the `forge_omp` role yet. Until that exists, no pack can be released, by design.
- The OMP industry review queue. All 17 industries sit at `pending`. None approved.
- Client accounts: zero. Engagements: one, the synthetic pilot.

## Honest limitations of this audit

- The deployed site could not be fetched from the build environment. Its egress proxy blocks both `vercel.app` and `supabase.co`, so every check here was made against the database and the source, not against the running pages. Browser behaviour is inferred from the same key and view that the existing sign in pages already use successfully.
- Lighthouse has not been run. The pages are built to the protocol but the score is unverified.

## The shortest path to a fully live site

1. Set the four environment variables in the Vercel project, then redeploy. Everything transactional turns on.
2. Create a Supabase Auth user for the designated practitioner with `forge_omp` in `app_metadata.msp_roles`. The clinical gate then opens and the pilot pack can be signed.
3. Confirm the rate card and the practitioner review fee, then set `msp_pricing.status` and `msp_package.fee_status` to `confirmed`. Quotes stop being marked indicative.

## The parameter store and the assistant

Added after the audit above, in migrations 034 to 037 and one edge function.

### What was built

| Piece | Where | What it does |
| --- | --- | --- |
| Parameter store | `msp_env_parameter`, 29 rows in 5 groups | Every setting that can be retuned without a deployment: model, effort, thinking mode, output ceiling, spend ceiling, hourly limits, price table, audit day and hour, clinical floors, commercial thresholds, integration references |
| Change history | `msp_env_parameter_history` | Append only. Old value, new value, who, when, why. A trigger refuses updates and deletes |
| Assistant connection | Supabase edge function `msp-assistant` | Four actions. Reads its whole configuration from the parameter store on every call and carries no defaults of its own |
| Call ledger | `msp_ai_call_log` | Every call including the refusals, with model, effort, instruction version, tokens, priced cost, latency and outcome |
| Budget gate | `msp_ai_preflight` | Role, master switch and monthly ceiling checked before anything is spent |
| Live schedule | `pg_cron` job `msp_monthly_audit` | Runs the framework audit on the day and hour held in the parameters. Changing either parameter moves the job in the same action |
| Settings page | `/settings.html` | Reads and writes the store, shows the change history, the real cron schedule, this month's spend against the ceiling, and a panel to ask the assistant a live question |

### What was tested, and the result

Fifteen checks, all run against the live database.

| Check | Result |
| --- | --- |
| Parameter change with no identity at all | Refused |
| Parameter change signed in with no forge role | Refused |
| Enum parameter set to a value outside its list | Refused |
| Integer parameter set above its ceiling | Refused |
| Integer parameter set to a word | Refused |
| Parameter key that does not exist | Refused |
| Valid change by forge_admin | Applied |
| History row written for that change | Written |
| Attempt to edit a history row | Refused, append only holds |
| Changing the audit day moves the cron job | Moved from day 1 to day 7 in the same call |
| Preflight as forge_agent returns the running configuration | Allowed, model claude-opus-5, effort high, spend 0 |
| Grounding read for Construction | 17 verified instruments, 31 roles, no client data |
| Anonymous visitor reading the parameter table | 0 rows |
| Every parameter reader function reachable by the anonymous role | 0, after the grant lockdown in migration 037 |
| Edge function source parses | Clean |

The grant lockdown is worth naming plainly, because it was a real defect and not a theoretical one. Postgres grants execute on a new function to PUBLIC by default. Migrations 034 to 036 therefore left the small parameter readers callable by the anonymous web role, which would have exposed the running configuration to anyone. The database advisor flagged it, migration 037 revoked it, and the revocation was then verified function by function rather than assumed.

### Honest limitations

- The deployed edge function could not be called from the build environment. Its egress proxy blocks `supabase.co`, so the function was proved by deployment status, by the source parsing cleanly, and by every database function it calls being exercised directly. The first live call will be the first end to end proof, and the usage tab on the settings page will show it.
- `ANTHROPIC_API_KEY` is not set. Until Care Net sets it in the Supabase project's function secrets, the assistant answers that it is not configured and records the refusal in the ledger. No key was invented and none is in the repository or the database.
- The token prices in `ai.price_table_json` are the published list rates. They are used to price the ledger, they are an estimate, and they are a parameter precisely so they can be corrected without a deployment.
