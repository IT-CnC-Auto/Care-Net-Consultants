# Care Net Cognitive Kernel API and the Grok connection pack

Document reference: CNC-HSF-KRN-API-V1.0-2026 | Version 1.2 | 23/09/2026 | Classification: INTERNAL
Prepared for: Odendaal, to link a Grok bot to the Care Net Cognitive Kernel
Binding sources: hsf/BUILD-CONTRACT.md sections 3 (migration 050), 4 (vercel/api/kernel.js), 8, 9 (Amendment 1, which wins where it differs) and 10.10 (Amendment 2: the latest Grok model); SPEC.md Part B
Version 1.1 reconciles sections 2 to 5 and 10 with migration 050 and `vercel/api/kernel.js` as they now stand in the repository. Version 1.2 records the Director's decision that the bot always runs on the latest Grok model (sections 1.3, 8.2.2, 8.3.7, 9 and 10).

## 1. What this pack is

1.1 The Care Net Cognitive Kernel is the verified framework Care Net Consultants (Pty) Ltd builds Medical Surveillance Plans and Health and Safety Files from. The kernel API lets an approved server read that framework, and nothing else, so that a Grok bot can answer questions from verified data instead of from its own memory.

1.2 The pack has five parts:

| Part | File | Use |
| --- | --- | --- |
| 1 | `vercel/api/kernel.js` | The API itself (built under the contract; not part of this pack's files) |
| 2 | `vercel/kernel-api/openapi.yaml` | OpenAPI 3.1 description of `GET /api/kernel` |
| 3 | `grok/kernel-tools.json` | The six function tools, in the OpenAI compatible format the xAI API accepts |
| 4 | `grok/system-prompt.md` | The guardrails the bot runs under |
| 5 | `grok/bridge-example.mjs` | A dependency free Node example that joins Grok, the tools and the API |

1.3 Nothing in this pack names a Grok model. The Director's decision is that the bot always runs on the latest Grok model, so the bridge chooses it itself:
1.3.1 With `XAI_MODEL` unset or set to `auto` (the default), the bridge reads xAI's OpenAI compatible model list, `GET https://api.x.ai/v1/models` with the xAI key, on the first question and then at most once a day. It keeps the ids that start with `grok`, drops ids containing `image`, `imagine`, `vision`, `embed`, `mini`, `fast` or `code`, and takes the one with the greatest `created` date. It logs the id it chose.
1.3.2 If the list cannot be read, the bridge keeps its last good choice. With no good choice yet it tries again after 15 minutes, and the question fails with a plain reason rather than guessing a model.
1.3.3 Any other value of `XAI_MODEL` is used as it stands. Odendaal should confirm against xAI's own documentation whether xAI publishes an official alias that always points at its latest model; if it does, set `XAI_MODEL` to that alias and prefer it over the bridge's own choice, since xAI then decides what "latest" means.
1.3.4 A new model can answer differently from the last one. The checks in section 9 (numbers 5 and 6) are repeated whenever the log shows a new model id.

1.4 Status on 23/09/2026:
1.4.1 In the repository: the API (`vercel/api/kernel.js`) with its unit tests (`test/api/kernel.test.js`), and migration `050_kernel_api.sql` (currency holds, the citable views, the key table, the call log, key issue and revoke, the authorisation function and the read functions). 050 replays cleanly into a local database with `test/sql/replay.sh`, and `test/sql/hsf_flow_checks.sql` exercises it there.
1.4.2 The fields in section 2 and in `openapi.yaml` were checked one by one against the real output of the read functions on that local replay, and a run of `kernel.js` against the same database returned bodies that pass the OpenAPI schemas.
1.4.3 Applied to the live Supabase project on 24/09/2026 on the Director's instruction: migrations 042 and 047 to 055, each fetched by the database from the repository at commit 7cc7393, checked against its MD5 fingerprint before it ran, run as one transaction, and recorded in supabase_migrations.schema_migrations. The live counts match the local replay (256 File elements, 36 citable instruments, the Asbestos hold). No key has been issued yet: Odendaal issues it by route 2 in section 4.2 and puts it straight into the bot host's secret store. The /api/kernel endpoint on the preview needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY set for the Preview environment in Vercel (today they are set for Production only).

## 2. What the API returns

2.1 One endpoint, read only, JSON only: `GET /api/kernel?r=<resource>` with the header `Authorization: Bearer cnck_<64 hex characters>`.

| r | Other parameters | What comes back in `data` | Database function |
| --- | --- | --- | --- |
| `industries` | none | Every industry in the kernel | `kernel_api_industries()` |
| `industry` | `code` (required) | One industry: its selectable subindustries with role titles, roles, hazards, protocols with a basis from citable instruments only, and its citable instruments | `kernel_api_industry(p_code)` |
| `instruments` | `industry` (optional) | Citable instruments, all or those mapped to one industry | `kernel_api_instruments(p_industry)` |
| `protocols` | `industry` (optional) | Medical surveillance protocols, all or those the industry's roles call for, with a basis from citable instruments only | `kernel_api_protocols(p_industry)` |
| `elements` | `industry` (optional) | Health and Safety File elements, all or the universal elements plus the industry's overlay, with File citations only (section 2.3) and every other named instrument under `awaiting` | `kernel_api_elements(p_industry)` |
| `search` | `q` (required, 2 to 100 characters) | Up to 50 matches over citable instrument names and citations, protocol names, role titles and element names | `kernel_api_search(p_q)` |

2.2 The handler returns the read function's reply unchanged. Every read function wraps its payload with `kernel_api_envelope`, so every 200 body is exactly `{"kernel_release", "as_at", "notice", "data"}`: `kernel_release` is the highest `msp_kernel_version.semver` (1.0.0 on the live kernel until HSF-7 closes; a local replay that includes migration 042 reports 1.1.0), `as_at` is the database date of the call (ISO form; show it to readers as DD/MM/YYYY) and `notice` is the text of section 6. The fields inside `data`, all of them always present:

| r | Each item of `data` (or `data` itself for `industry`) |
| --- | --- |
| `industries` | `code`, `name`, `regime` (OHSA, MHSA or DUAL; in the kernel data MINING reads MHSA and every other industry OHSA) |
| `industry` | `code`, `name`, `regime`, `subindustries` (each `code`, `name`, `roles`: role titles), `roles` (titles), `hazards` (names), `protocols` (as `protocols` below), `instruments` (as `instruments` below) |
| `instruments` | `short_name` (cite exactly this), `full_citation`, `instrument_type`, `gazette_reference` (may be null), `effective_date` (may be null), `verified_on`, `review_due`, `scope` (medical, safety or both), `industries` (each `code`, `name`) |
| `protocols` | `name`, `test_type`, `hazard`, `periodic_interval_months`, `basis` (a list of at most one short name; empty when the kernel holds no citable basis for the protocol, which does not mean that no law applies) |
| `elements` | `section_code` (A to O), `section_name`, `code`, `name`, `duty`, `universal`, `citable` (short names), `awaiting` (names) |
| `search` | `kind` (instrument, protocol, role or element), `name`, `code` (the element code, the industry code of a role, null for an instrument or a protocol) |

The full schemas are in `vercel/kernel-api/openapi.yaml`, which lists every field as required and no others; a field added in a later release is added there first.

2.3 Two meanings of citable.
2.3.1 The register meaning, used by `instruments`, `industry`, protocol bases and `search`: an instrument in the view `kernel_citable_instrument`, which is status verified (gate a primary text, gate b independent corroboration, gate c currency on the day; a superseded row is never verified) with no row in `msp_instrument_currency_hold`. A hold only ever tightens. Migration 050 seeds holds, wherever the row still reads verified, for the NIHL Regulations, 2003 and the Environmental Regulations for Workplaces, 1987 (repealed from 06/09/2026; the live kernel still marks them verified, HSF-7) and for the Asbestos Abatement Regulations, 2020 (the amendment notice number conflicts, GN R.2092 against GN R.11435, register HSF-9). On a local replay, where migration 042 has already superseded the first two, the Asbestos hold is the one that applies. The public register, industry profile and framework statistics views leave held instruments out as well (contract 9.4).
2.3.2 The File meaning, used by `elements` (contract 9.3): `hsf_element_citable` lists an instrument for an element only when it is citable in the register meaning, its `scope` is safety or both, and the element's link to it carries a provision pinned past "awaiting verification". Every other pending or verified instrument named for the element, a held one included, shows by name under `awaiting` and is never a basis. The library seed (048) writes every link with the provision "awaiting verification", so until the Phase 2 re verification pins the provisions, every element's `citable` list is empty (on the local replay, all 256 elements). That is the truthful state, and the bot says "awaiting verification".

2.4 Status codes:

| Code | Meaning | What the bot should do |
| --- | --- | --- |
| 200 | The resource | Use it |
| 400 | Unknown resource, missing or malformed parameter | Fix the call; the bridge checks arguments first |
| 401 | Missing, malformed, unknown, inactive or revoked key (with `WWW-Authenticate: Bearer realm="cnc-kernel"`) | Stop; tell the person the kernel is unavailable; Odendaal checks the key |
| 403 | Key without the `kernel.read` scope (only possible if a key row was changed by hand: `msp_api_client_issue` issues `kernel.read` keys only) | As 401 |
| 404 | No industry with that code, for `industry` ("No industry has that code.") or as the `industry` filter of `instruments`, `protocols` or `elements` ("Nothing was found.") | Call `kernel_industries` for valid codes |
| 405 | Method other than GET or OPTIONS | Use GET |
| 429 | Hourly limit reached (section 5) | Tell the person to try later |
| 500 | Read failed | Tell the person the kernel is unavailable |
| 503 | Server not configured, or `msp_api_authorise` unreachable | As 500 |

2.5 The handler checks in this order: a key of the right form (401), a known `r` (400), parameters that pass their patterns (400), a configured server (503); only then does `msp_api_authorise` check the key and log the call, and only then is data read. A request refused before the database is therefore not logged. Error bodies are always `{"error": "<plain message>", "code": "<code>"}`, never a stack trace, database text or secret. Every response carries `Cache-Control: no-store`. CORS is open (`Access-Control-Allow-Origin: *`, `Authorization` allowed) because keys are used server to server with no cookies; that is not an invitation to call the API from a browser page.

## 3. What the API never returns

3.1 No client, engagement, intake, upload, consent, person, certificate, audit or sign off data of any kind. The read functions do not touch those tables.

3.2 No instrument that is pending, excluded, superseded or held, and no Section 5 candidate, as a basis or in the instrument lists. Candidates and held instruments appear only by name under `awaiting` on File elements, so the bot can say they are awaiting verification.

3.3 No confirmation register items, no kernel exclusions, no internal notes, no parameters, no prices.

3.4 No key material: the API never echoes the key, and the database stores only the SHA 256 hash of it.

3.5 The call log (`msp_api_call_log`, append only) holds the client (null for an unknown key), the resource, the authorisation status (200, 401, 403 or 429; the handler refuses an unknown resource before it gets there) and the time. It holds no request text, no search words and no IP address.

## 4. Getting a key

4.1 Who issues. Only a forge_admin (or the service role) can run `msp_api_client_issue`. Odendaal asks the Director or a forge_admin for a key; nobody else can create one.

4.2 How it is issued. `msp_api_client_issue` runs for a signed in forge_admin or in the service role context and refuses everyone else ("Issuing a kernel API key requires the forge_admin role."); migration 050 grants it to signed in users and checks the role inside, and anonymous callers cannot run it at all. The checks behind both routes were exercised on the local replay (a forge_admin session, the service role context, another staff role and an anonymous caller); neither route has been run against the live project.

Route 1 (recommended). From a trusted terminal, signed in as a forge_admin, the call goes through the Supabase REST interface with that person's own session token (never the service role key on a laptop):

```sh
curl -sS -X POST "https://pboebfnujzffgwctsplw.supabase.co/rest/v1/rpc/msp_api_client_issue" \
  -H "apikey: sb_publishable_E6ebjt_HJy5RN6MzM6fsdg_I1VbB1aj" \
  -H "Authorization: Bearer <forge_admin access token>" \
  -H "Content-Type: application/json" \
  -d '{"p_name":"Grok kernel bot","p_owner":"Odendaal","p_scopes":["kernel.read"]}'
```

The publishable key above is public by design (hsf/BUILD-CONTRACT.md section 1); the access token is the forge_admin's own and expires.

Route 2. In the Supabase SQL editor a plain `select msp_api_client_issue(...)` is refused, because the editor carries no sign in. A person who already has owner access to the database can run it in the service role context inside one transaction:

```sql
begin;
set local request.jwt.claims = '{"role":"service_role"}';
select msp_api_client_issue(
  p_name   => 'Grok kernel bot',
  p_owner  => 'Odendaal',
  p_scopes => '{kernel.read}'
);
commit;
```

The audit row then names the actor `service_role` rather than a person, so Route 1 is preferred. A button on the settings page for forge_admin is recommended and not built (section 10).

4.3 The answer is `{"client_id": "<uuid>", "api_key": "cnck_<64 hex>"}`. The key is shown once. Care Net keeps only its SHA 256 hash and cannot show it again; a lost key is revoked and a new one issued.

4.4 Where the key goes. Straight into the secret store of the host that runs the Grok bot, as `CNC_KERNEL_API_KEY`. Never into chat (including Grok itself), email, WhatsApp, a ticket, a document, a screenshot, source code, a `.env` file in a repository or a browser page. The bridge refuses to start without it and never logs it.

4.5 Revoking. If a key may have been seen by anyone, or the bot is retired, a forge_admin runs `msp_api_client_revoke('<client_id>')` by either route in 4.2; it answers `{"client_id", "active": false, "revoked_at"}` and the key stops working at once (401). Issue a new key and replace the secret.

4.6 One key per bot and per environment (for example one for testing, one for production), so that one can be revoked without stopping the other, and the call log shows which is which.

## 5. Rate limits

5.1 Each key has an hourly limit held on its row (`msp_api_client.hourly_limit`, 600 by default). Before every read `msp_api_authorise` counts the key's authorised calls (status 200) in the last hour, with the key's row locked so that parallel calls count exactly; at the limit the API answers 429 and reads nothing. Refused calls are logged but do not count.

5.2 The window rolls: calls drop out an hour after they were made. No `Retry-After` header is sent. A bot should not retry in a loop on 429; the bridge passes the refusal to Grok, which tells the person to try later.

5.3 One question can take several calls (the bridge allows up to 8 tool calls per model turn and 6 turns). Plan the limit for the busiest hour. Changing a key's limit is, for now, a service role update to `msp_api_client.hourly_limit`; there is no function for it yet (section 10).

5.4 xAI applies its own limits and charges per token to the xAI account behind `XAI_API_KEY`. Those are set and paid in the xAI console, not by Care Net.

## 6. The notice every answer must carry

6.1 Every response of the API carries, and every answer built from it must show its reader, this notice word for word:

> Framework reference data from the Care Net Cognitive Kernel. Not legal advice and not a clinical opinion. Only instruments that have passed three verification checks and are in force are included.

6.2 The bridge appends it to every answer, including refusals, and removes any copy the model wrote so it appears once. If you build your own bridge, do the same in code; do not rely on the model to remember it.

6.3 Alongside the notice, answers should keep Care Net's boundaries (all in `grok/system-prompt.md`): Care Net screens fitness for work and does not diagnose; the employer pays for occupational health services; no clinical opinions and no legal advice; no personal information; escalation to a sales executive on WhatsApp at 27 60 070 2723.

## 7. What the xAI API supports (search engine extracts, 23/09/2026; not read directly)

7.1 Method. Searches were run on 23/09/2026. The xAI documentation site (docs.x.ai) could not be opened directly from the build environment because its network policy blocks the host, so the findings below come from search engine extracts of those pages, cross checked where possible. Treat each as needing a direct read by Odendaal before go live.

7.2 Findings.

| Number | Finding | Source (searched 23/09/2026) | Confidence |
| --- | --- | --- | --- |
| 1 | The xAI API supports function calling: you define your own tools with a name, a description and parameters as JSON schema; the model asks for a call; your code runs it and returns the result. Built in tools (web search, X search and others) run on xAI's servers and are a separate kind. | https://docs.x.ai/docs/guides/function-calling ; https://docs.x.ai/developers/tools/overview | High (xAI documentation, via search extracts) |
| 2 | The API is OpenAI compatible at `https://api.x.ai/v1`, with `/v1/chat/completions` and `/v1/responses`. Tool results go back with a `tool_call_id` that points at the model's call. | https://docs.x.ai/developers/rest-api-reference/inference/chat-completions ; https://docs.x.ai/developers/tools/tool-usage-details | High for the endpoints; medium for field level detail |
| 3 | xAI describes chat completions as a legacy endpoint: new features come to the Responses API first, and xAI recommends the Responses API. Chat completions still works and is what the bridge uses, because it is stateless and matches the OpenAI tools format of `kernel-tools.json` exactly. | https://docs.x.ai/developers/model-capabilities/legacy/chat-completions ; https://docs.x.ai/developers/model-capabilities/text/comparison | High |
| 4 | `tool_choice` accepts `auto` and `required`, and the model may ask for several tool calls in one turn (parallel calling is on by default). | https://theneuralbase.com/xai-grok/learn/intermediate/tool-choice-options/ ; https://theneuralbase.com/xai-grok/learn/intermediate/parallel-tool-calls/ | Medium (third party course pages, not xAI) |
| 5 | Remote MCP tools are supported: an entry `{"type": "mcp", "server_url": ..., "server_label": ...}` in the tools array lets xAI's servers call an MCP server directly. Streamable HTTP and SSE transports are accepted, STDIO is not. Supported through the xAI SDK and the OpenAI compatible Responses API (and xAI's voice agent API). The search results did not list chat completions among them. | https://docs.x.ai/developers/tools/remote-mcp ; https://docs.x.ai/docs/guides/tools/remote-mcp-tools | High that remote MCP exists; medium on the exact endpoint list |
| 6 | For remote MCP, `allowed_tools` limits which server tools the model may use and `authorization` supplies a token that xAI sends to the MCP server; the key and URL go with every request. The OpenAI Responses fields `require_approval` and `connector_id` are reported as not supported. | https://ai-x.chat/docs/remote-mcp-tools/ | Medium (third party page summarising xAI) |
| 7 | By default xAI stores API requests and responses for 30 days for abuse monitoring and does not train on API data without permission; enterprise accounts can switch on zero data retention, which disables some stateful features. | https://docs.x.ai/developers/faq/security | Medium (search extract of xAI's security FAQ); relevant to section 8 and to HSF-PORTAL-ARCHITECTURE.md section 5 |

7.3 Uncertain and to be checked by Odendaal: the model list (`GET /v1/models`, assumed OpenAI style `{data: [{id, created}]}`) and whether xAI offers an official latest alias (section 1.3.3); the exact response fields of the current chat completions API for the model chosen (some reasoning models return extra fields, which the bridge ignores); whether chat completions accepts remote MCP (assume not); whether `strict` schemas are honoured (the tools do not rely on it; the bridge and the API both validate arguments); and the current rate limits and prices of the xAI account.

## 8. How to connect a Grok bot

8.1 Recommended route: function calling through a bridge (built). The bot host keeps both keys. Grok sees only tool definitions and tool results; it never sees the Care Net key, and the kernel never sees the question text.

```
Person ──question──▶ Bot host (bridge) ──messages + tools──▶ xAI chat completions
                          │  ◀──tool_calls──────────────────────────┘
                          │──GET /api/kernel?r=… (Bearer cnck_…)──▶ Care Net kernel API
                          │  ◀──JSON: kernel_release, as_at, notice, data
                          │──tool results──▶ xAI ──final text──▶ bridge adds the notice ──▶ Person
```

8.2 Steps.
8.2.1 Get a key (section 4) and store it in the bot host's secret store as `CNC_KERNEL_API_KEY`.
8.2.2 Set `XAI_API_KEY` (from the xAI console, owned by whoever pays for xAI) in the same secret store. Leave `XAI_MODEL` unset (or `auto`) so the bridge runs on the latest Grok model (section 1.3), or set it to xAI's official latest alias once Odendaal has confirmed one exists; the setup script (8.6) looks for that alias and writes the choice. Never type the key into chat or code.
8.2.3 Set `CNC_KERNEL_API_BASE` to the origin that serves `/api/kernel` (the Forge host; pending, section 10). `https` only.
8.2.4 Copy `grok/bridge-example.mjs`, `grok/model-pick.mjs`, `grok/setup.mjs`, `grok/kernel-tools.json`, `grok/system-prompt.md` and `grok/.gitignore` to the bot host together, into one folder (the bridge imports `model-pick.mjs` and reads the prompt and the tools from its own folder). Node 20 or later for the setup script, 20.6 or later to load the `.env` with `--env-file`; no packages.
8.2.5 Smoke test the API first, from the bot host, with the key taken from the environment (the key never appears on the command line history if you use the variable):

```sh
curl -sS -H "Authorization: Bearer $CNC_KERNEL_API_KEY" "$CNC_KERNEL_API_BASE/api/kernel?r=industries"
```

8.2.6 Run the setup script (8.6) and fix whatever it reports until it ends with "All checks passed.".
8.2.7 Then the bridge: `node --env-file=grok/.env grok/bridge-example.mjs "Which instruments does the kernel hold for construction?"` (or plain `node grok/bridge-example.mjs "..."` when every variable sits in the host's secret store). The answer ends with the notice.
8.2.8 Put the bot's own front door (website chat, internal tool, messaging channel) in front of the bridge with its own sign in or abuse control: every question costs xAI tokens and kernel calls. Where the bot is offered is a Director decision (section 10).

8.3 What the bridge does for safety, in code rather than in the prompt.
8.3.1 Refuses a question that carries an identity number, an email address or a telephone number before anything is sent to xAI, and refuses such text as a search term.
8.3.2 Offers Grok only the six kernel tools, and never switches on Grok's built in web or X search, so the kernel is the only source.
8.3.3 Checks every tool argument against the same patterns as the API before calling it.
8.3.4 Caps the question (2 000 characters), the model turns (6), the tool calls honoured per turn (8) and each tool result (60 000 characters). The unfiltered element list is longer than that cap, so the bridge cuts it and tells Grok to filter by industry; `kernel-tools.json` asks for the filter too.
8.3.5 Appends the notice once, word for word, and removes em and en dashes from the answer.
8.3.6 Logs nothing but errors and the model id it chooses, with keys redacted; never logs a question, an argument or an answer.
8.3.7 Chooses the latest Grok model from xAI's model list at most once a day and keeps the last good choice when the list cannot be read (section 1.3); `test/mco/grok-model.test.mjs` covers the choice with a mocked list.

8.4 Alternative route: remote MCP (not built). xAI can call an MCP server itself (section 7.2, findings 5 and 6). Care Net's API is a REST endpoint, not an MCP server, so this route needs a small MCP server that wraps `/api/kernel` with the same six tools. Two consequences decide against it for now: the Care Net key would travel to xAI in the `authorization` field of every request, and xAI would call Care Net directly, so the bot host could no longer screen questions and tool arguments for personal information in code. It also needs the Responses API. Revisit only if Odendaal's platform cannot run a bridge, and then with a separate, tightly limited key.

8.5 Not recommended: adding the kernel to a personal Grok account through the consumer connectors screen. The key would sit in a personal account, outside Care Net's control.

8.6 The setup script, `grok/setup.mjs` (contract 11.6). Odendaal runs it on the bot host from the folder above `grok`, first with `--check`, then without:

```sh
node grok/setup.mjs --check   # checks everything, writes nothing
node grok/setup.mjs           # checks everything, then writes XAI_MODEL=<chosen id> into grok/.env
node grok/setup.mjs --auto    # checks everything, then writes XAI_MODEL=auto (the bridge chooses once a day)
```

8.6.1 Where the settings come from. `XAI_API_KEY`, `CNC_KERNEL_API_KEY` and `CNC_KERNEL_API_BASE` (and the optional `XAI_API_BASE`) are read from the environment, or else from `grok/.env` beside the script. The environment wins, as it does with `node --env-file`. If the keys sit in a `.env`, it must be that one file on the bot host, readable by the bot's user only (`chmod 600`; the script creates a new one that way and warns about a looser one). `grok/.gitignore` keeps `.env` out of the repository; a `.env` never goes into a repository, a ticket or a chat (section 4.4).
8.6.2 What it checks, each step numbered on screen: (1) the Node version; (2) that the three settings are present, that the kernel key has the `cnck_` form and that both bases use https; (3) the kernel API, `GET <CNC_KERNEL_API_BASE>/api/kernel?r=industries`, reporting the exact status and, on success, the number of industries and the kernel release; (4) xAI's model list, `GET https://api.x.ai/v1/language-models`, falling back to `GET https://api.x.ai/v1/models` when the first gives no usable choice; (5) the `.env`.
8.6.3 How it chooses the model. If the list carries aliases, it takes an official alias that ends in `latest` for the flagship Grok family (the alias and the model it points at start with `grok` and contain none of the excluded words of section 1.3.1; among several, the alias of the newest model). If no such alias is listed, it uses the bridge's own newest rule (section 1.3.1). Both rules sit in `grok/model-pick.mjs`, which the bridge and the script share. With a fixed id written, the bridge uses that id as it stands and no longer reads the list daily; run the script again (or use `--auto`) to move to a newer model.
8.6.4 To confirm on the first real run. The script was built and tested with mocked replies only, because xAI could not be reached from the build environment. The `aliases` field, the name of the list (`models` or `data`) and the `/v1/language-models` endpoint itself are assumptions. The script prints what it found: the endpoint that answered, its status, how many models it listed, whether an aliases field was present, the Grok chat models left after the filter, the aliases listed and the id chosen with the reason. Odendaal compares that with xAI's own documentation and records the result under section 10 item 8.
8.6.5 What it writes. Only `XAI_MODEL=<id>` (or `XAI_MODEL=auto`) in `grok/.env`, replacing an existing `XAI_MODEL` line and keeping every other line as it was; a missing `.env` is created with that one line. Nothing is written with `--check`, and nothing is written at all unless the checks in steps 1 to 4 passed. No other file is ever written.
8.6.6 What it never shows. Neither key is printed or logged, not even in part: replies are reported by status only, no reply body is echoed, and every line passes a redaction of both keys before it is shown. The tests in `test/mco/grok-setup.test.mjs` capture the output of every case and fail if a key appears.
8.6.7 Exit codes, for a host that runs it from a script:

| Code | Meaning |
| --- | --- |
| 0 | Every check passed (and the `.env` was written, unless `--check`) |
| 1 | A setting is missing or malformed, the `.env` could not be read, or an option is wrong |
| 2 | Node is older than 20 |
| 3 | The kernel API check failed (the status is shown; 401 is a refused key, 403 a key without kernel.read, 404 a wrong base) |
| 4 | The xAI check failed: the key was refused (401 or 403), xAI could not be reached, or no Grok chat model could be chosen |
| 5 | The `.env` could not be written |

When both network checks fail, the kernel's code (3) is returned; both are still reported.

## 9. Security checklist for go live

| Number | Check | Owner |
| --- | --- | --- |
| 1 | Key issued by a forge_admin, one per bot and environment, stored only in the bot host's secret store | Forge admin, Odendaal |
| 2 | Latest model: `node grok/setup.mjs` ends with "All checks passed." on the bot host; `XAI_MODEL` is `auto`, or the official latest alias the script found, or the newest id it chose; the alias field and the model list's shape it printed have been compared with xAI's own documentation (section 8.6.4); no model name in any file in the repository | Odendaal |
| 3 | No web, X or other built in xAI tools enabled for this bot | Odendaal |
| 4 | The bot's front door has its own sign in or abuse limit | Odendaal |
| 5 | The notice appears at the end of every answer (test with three questions and one refusal) | Odendaal |
| 6 | A question with an identity number is refused without an xAI call (check the xAI usage log shows no request) | Odendaal |
| 7 | xAI recorded as an operator for the question text; its retention setting reviewed (HSF-PORTAL-ARCHITECTURE.md section 5) | Director, Information Officer |
| 8 | System prompt changes reviewed by the Director before they go live | Director |
| 9 | Revocation tested: revoke a test key and see 401 (the setup script's step 3 shows it) | Forge admin |
| 10 | Keys only in the bot host's secret store or in `grok/.env` on that host, readable by the bot's user only; `grok/.gitignore` present; `git status` on the host shows no `.env` | Odendaal |

## 10. Open items

| Number | Item | Owner | Status |
| --- | --- | --- | --- |
| 1 | Migration `050_kernel_api.sql`: written, in the repository and replayed with `test/sql/replay.sh` (corrected in place for Amendment 1); review and application to the live project wait for the Director's approval; until then no key can be issued | Build, Director | Written and replayed locally; not applied |
| 2 | Field names inside `data` confirmed against 050; `openapi.yaml` reconciled field by field with the function output and with the reply of `kernel.js` on a local replay (section 1.4.2). `data` is the payload key, as the functions and the API test fixtures use it | Build | Done 23/09/2026 |
| 3 | Production host for the Forge API (`CNC_KERNEL_API_BASE`): the Vercel project now, MyClinicOnline hosting later | Director | Pending (HSF-3 for MCO) |
| 4 | Route for issuing keys: the grants in 050 are confirmed (section 4.2: forge_admin through REST, or the service role); a settings page button for forge_admin is not built | Build | Grants confirmed; button open |
| 5 | A function to change a key's hourly limit without a service role update | Build | Open |
| 6 | Where the bot is offered (website, internal, messaging) and who may use it | Director | Open |
| 7 | xAI as an operator: agreement, retention setting (default 30 days per xAI's FAQ, zero data retention for enterprise accounts), cross border note in the privacy policy | Director, Information Officer, attorney | Open |
| 8 | Direct read of the xAI documentation pages in section 7 before go live, since they could not be opened from the build environment, including the model list and any official latest alias (section 1.3) | Odendaal | Open |
| 9 | Kernel currency: the live kernel is on release 1.0.0 (HSF-7). The holds in 050 keep the repealed NIHL Regulations, 2003 and Environmental Regulations for Workplaces, 1987 out of the API, but the kernel release reported will stay 1.0.0 until 042 or its successor is applied | Director, OMP | Open, blocking Phase 2 |
| 10 | Asbestos Abatement Regulations, 2020: the amendment notice is GN R.2092 in one record and GN R.11435 in the other (HSF-9). Held from citation by 050 until verified against the Gazette and corrected | Build, forge_verifier | Open |
| 11 | Phase 2 re verification of the safety instruments and their File provisions (SPEC B8): until then no File element has a citable basis (section 2.3.2) | Build, forge_verifier | Open; waits for HSF-7 (SPEC B8.2) |
