# Care Net Cognitive Kernel API and the Grok connection pack

Document reference: CNC-HSF-KRN-API-V1.0-2026 | Version 1.0 | 23/09/2026 | Classification: INTERNAL
Prepared for: Odendaal, to link a Grok bot to the Care Net Cognitive Kernel
Binding sources: hsf/BUILD-CONTRACT.md sections 3 (migration 050), 4 (vercel/api/kernel.js) and 8; SPEC.md Part B

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

1.3 Nothing in this pack names a Grok model. The bridge reads the model from the environment variable `XAI_MODEL`, which Odendaal sets in the bot host.

1.4 Status: the API code and its tests are in the repository. The database side (migration `050_kernel_api.sql`: the key table, the authorisation function and the read functions) is specified in the contract but was not in the repository when this document was written, and nothing has been applied to the live Supabase project or deployed. Until 050 is applied and the API deployed, no key can be issued and the bot cannot run against live data (section 10).

## 2. What the API returns

2.1 One endpoint, read only, JSON only: `GET /api/kernel?r=<resource>` with the header `Authorization: Bearer cnck_<64 hex characters>`.

| r | Other parameters | What comes back in `data` | Database function |
| --- | --- | --- | --- |
| `industries` | none | Every industry in the kernel | `kernel_api_industries()` |
| `industry` | `code` (required) | One industry: subindustries, roles, hazards, protocols with bases from citable instruments only, and its citable instruments | `kernel_api_industry(p_code)` |
| `instruments` | `industry` (optional) | Citable instruments, all or for one industry | `kernel_api_instruments(p_industry)` |
| `protocols` | `industry` (optional) | Medical surveillance protocols, with bases from citable instruments only | `kernel_api_protocols(p_industry)` |
| `elements` | `industry` (optional) | Health and Safety File elements, with only citable bases and any candidates marked as awaiting | `kernel_api_elements(p_industry)` |
| `search` | `q` (required, 2 to 100 characters) | Up to 50 matches across instrument, protocol, role and element names | `kernel_api_search(p_q)` |

2.2 Every successful response carries three envelope fields: `kernel_release` (the latest kernel release, for example 1.0.0), `as_at` (the date of the call) and `notice` (section 6). The field lists inside `data` are in `vercel/kernel-api/openapi.yaml`; where migration 050 as merged names a field differently, 050 wins and the OpenAPI file is corrected.

2.3 A citable instrument is one that is in the view `kernel_citable_instrument`: status verified (gate a primary text, gate b independent corroboration, gate c currency on the day), not superseded and not held by `msp_instrument_currency_hold`. The contract seeds holds for the NIHL Regulations, 2003 and the Environmental Regulations for Workplaces, 1987, repealed from 06/09/2026, so the API never offers them even while the live kernel still marks them verified (HSF-7).

2.4 Status codes:

| Code | Meaning | What the bot should do |
| --- | --- | --- |
| 200 | The resource | Use it |
| 400 | Unknown resource, missing or malformed parameter | Fix the call; the bridge checks arguments first |
| 401 | Missing, malformed, unknown, inactive or revoked key (with `WWW-Authenticate: Bearer`) | Stop; tell the person the kernel is unavailable; Odendaal checks the key |
| 403 | Key without the `kernel.read` scope | As 401 |
| 404 | No industry with that code | Call `kernel_industries` for valid codes |
| 405 | Method other than GET or OPTIONS | Use GET |
| 429 | Hourly limit reached (section 5) | Tell the person to try later |
| 500 | Read failed | Tell the person the kernel is unavailable |
| 503 | Server not configured, or key store unreachable | As 500 |

2.5 Error bodies are always `{"error": "<plain message>", "code": "<code>"}`, never a stack trace, database text or secret. Every response carries `Cache-Control: no-store`. CORS is open (`Access-Control-Allow-Origin: *`, `Authorization` allowed) because keys are used server to server with no cookies; that is not an invitation to call the API from a browser page.

## 3. What the API never returns

3.1 No client, engagement, intake, upload, consent, person, certificate, audit or sign off data of any kind. The read functions do not touch those tables.

3.2 No instrument that is pending, excluded, superseded or held, and no Section 5 candidate as a basis. Candidates appear only by name under `awaiting` on File elements, so the bot can say they are awaiting verification.

3.3 No confirmation register items, no kernel exclusions, no internal notes, no parameters, no prices.

3.4 No key material: the API never echoes the key, and the database stores only the SHA 256 hash of it.

3.5 The call log (`msp_api_call_log`) holds the client, the resource, the status and the time. It holds no request text, no search words and no IP address.

## 4. Getting a key

4.1 Who issues. Only a forge_admin (or the service role) can run `msp_api_client_issue`. Odendaal asks the Director or a forge_admin for a key; nobody else can create one.

4.2 How it is issued. The forge_admin runs the function once, naming the bot and its owner:

```sql
select msp_api_client_issue(
  p_name   => 'Grok kernel bot',
  p_owner  => 'Odendaal',
  p_scopes => '{kernel.read}'
);
```

From a trusted terminal, signed in as a forge_admin, the same call goes through the Supabase REST interface with that person's own session token (never the service role key on a laptop):

```sh
curl -sS -X POST "https://pboebfnujzffgwctsplw.supabase.co/rest/v1/rpc/msp_api_client_issue" \
  -H "apikey: sb_publishable_E6ebjt_HJy5RN6MzM6fsdg_I1VbB1aj" \
  -H "Authorization: Bearer <forge_admin access token>" \
  -H "Content-Type: application/json" \
  -d '{"p_name":"Grok kernel bot","p_owner":"Odendaal","p_scopes":["kernel.read"]}'
```

The publishable key above is public by design (hsf/BUILD-CONTRACT.md section 1); the access token is the forge_admin's own and expires. Which of these two routes works depends on the grants migration 050 sets; a button on the settings page is recommended (section 10).

4.3 The answer is `{"client_id": "<uuid>", "api_key": "cnck_<64 hex>"}`. The key is shown once. Care Net keeps only its SHA 256 hash and cannot show it again; a lost key is revoked and a new one issued.

4.4 Where the key goes. Straight into the secret store of the host that runs the Grok bot, as `CNC_KERNEL_API_KEY`. Never into chat (including Grok itself), email, WhatsApp, a ticket, a document, a screenshot, source code, a `.env` file in a repository or a browser page. The bridge refuses to start without it and never logs it.

4.5 Revoking. If a key may have been seen by anyone, or the bot is retired, a forge_admin runs `select msp_api_client_revoke('<client_id>');` and the key stops working at once (401). Issue a new key and replace the secret.

4.6 One key per bot and per environment (for example one for testing, one for production), so that one can be revoked without stopping the other, and the call log shows which is which.

## 5. Rate limits

5.1 Each key has an hourly limit held on its row (`msp_api_client.hourly_limit`, 600 by default). `msp_api_authorise` counts the key's calls in the last hour before every read; at the limit the API answers 429 and reads nothing.

5.2 The window rolls: calls drop out an hour after they were made. No `Retry-After` header is sent. A bot should not retry in a loop on 429; the bridge passes the refusal to Grok, which tells the person to try later.

5.3 One question can take several calls (the bridge allows up to 8 tool calls per model turn and 6 turns). Plan the limit for the busiest hour. Changing a key's limit is, for now, a service role update to `msp_api_client.hourly_limit`; there is no function for it yet (section 10).

5.4 xAI applies its own limits and charges per token to the xAI account behind `XAI_API_KEY`. Those are set and paid in the xAI console, not by Care Net.

## 6. The notice every answer must carry

6.1 Every response of the API carries, and every answer built from it must show its reader, this notice word for word:

> Framework reference data from the Care Net Cognitive Kernel. Not legal advice and not a clinical opinion. Only instruments that have passed three verification checks and are in force are included.

6.2 The bridge appends it to every answer, including refusals, and removes any copy the model wrote so it appears once. If you build your own bridge, do the same in code; do not rely on the model to remember it.

6.3 Alongside the notice, answers should keep Care Net's boundaries (all in `grok/system-prompt.md`): Care Net screens fitness for work and does not diagnose; the employer pays for occupational health services; no clinical opinions and no legal advice; no personal information; escalation to a sales executive on WhatsApp at 27 60 070 2723.

## 7. What the xAI API supports today (web search, 23/09/2026)

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

7.3 Uncertain and to be checked by Odendaal: the exact response fields of the current chat completions API for the model chosen (some reasoning models return extra fields, which the bridge ignores); whether chat completions accepts remote MCP (assume not); whether `strict` schemas are honoured (the tools do not rely on it; the bridge and the API both validate arguments); and the current rate limits and prices of the xAI account.

## 8. How to connect a Grok bot

8.1 Recommended route: function calling through a bridge (built). The bot host keeps both keys. Grok sees only tool definitions and tool results; it never sees the Care Net key, and the kernel never sees the question text.

```
Person ──question──▶ Bot host (bridge) ──messages + tools──▶ xAI chat completions
                          │  ◀──tool_calls──────────────────────────┘
                          │──GET /api/kernel?r=… (Bearer cnck_…)──▶ Care Net kernel API
                          │  ◀──JSON with kernel_release, as_at, notice
                          │──tool results──▶ xAI ──final text──▶ bridge adds the notice ──▶ Person
```

8.2 Steps.
8.2.1 Get a key (section 4) and store it in the bot host's secret store as `CNC_KERNEL_API_KEY`.
8.2.2 Set `XAI_API_KEY` (from the xAI console, owned by whoever pays for xAI) and `XAI_MODEL` (the model Odendaal chooses) in the same secret store. Never type either into chat or code.
8.2.3 Set `CNC_KERNEL_API_BASE` to the origin that serves `/api/kernel` (the Forge host; pending, section 10). `https` only.
8.2.4 Copy `grok/bridge-example.mjs`, `grok/kernel-tools.json` and `grok/system-prompt.md` to the bot host together (the bridge reads the other two from its own folder). Node 18 or later; no packages.
8.2.5 Smoke test the API first, from the bot host, with the key taken from the environment (the key never appears on the command line history if you use the variable):

```sh
curl -sS -H "Authorization: Bearer $CNC_KERNEL_API_KEY" "$CNC_KERNEL_API_BASE/api/kernel?r=industries"
```

8.2.6 Then the bridge: `node bridge-example.mjs "Which instruments does the kernel hold for construction?"`. The answer ends with the notice.
8.2.7 Put the bot's own front door (website chat, internal tool, messaging channel) in front of the bridge with its own sign in or abuse control: every question costs xAI tokens and kernel calls. Where the bot is offered is a Director decision (section 10).

8.3 What the bridge does for safety, in code rather than in the prompt.
8.3.1 Refuses a question that carries an identity number, an email address or a telephone number before anything is sent to xAI, and refuses such text as a search term.
8.3.2 Offers Grok only the six kernel tools, and never switches on Grok's built in web or X search, so the kernel is the only source.
8.3.3 Checks every tool argument against the same patterns as the API before calling it.
8.3.4 Caps turns, tool calls per turn and result size.
8.3.5 Appends the notice once, word for word, and removes em and en dashes from the answer.
8.3.6 Logs nothing but errors, with keys redacted; never logs a question, an argument or an answer.

8.4 Alternative route: remote MCP (not built). xAI can call an MCP server itself (section 7.2, findings 5 and 6). Care Net's API is a REST endpoint, not an MCP server, so this route needs a small MCP server that wraps `/api/kernel` with the same six tools. Two consequences decide against it for now: the Care Net key would travel to xAI in the `authorization` field of every request, and xAI would call Care Net directly, so the bot host could no longer screen questions and tool arguments for personal information in code. It also needs the Responses API. Revisit only if Odendaal's platform cannot run a bridge, and then with a separate, tightly limited key.

8.5 Not recommended: adding the kernel to a personal Grok account through the consumer connectors screen. The key would sit in a personal account, outside Care Net's control.

## 9. Security checklist for go live

| Number | Check | Owner |
| --- | --- | --- |
| 1 | Key issued by a forge_admin, one per bot and environment, stored only in the bot host's secret store | Forge admin, Odendaal |
| 2 | `XAI_MODEL` set in the environment; no model name in any file | Odendaal |
| 3 | No web, X or other built in xAI tools enabled for this bot | Odendaal |
| 4 | The bot's front door has its own sign in or abuse limit | Odendaal |
| 5 | The notice appears at the end of every answer (test with three questions and one refusal) | Odendaal |
| 6 | A question with an identity number is refused without an xAI call (check the xAI usage log shows no request) | Odendaal |
| 7 | xAI recorded as an operator for the question text; its retention setting reviewed (HSF-PORTAL-ARCHITECTURE.md section 5) | Director, Information Officer |
| 8 | System prompt changes reviewed by the Director before they go live | Director |
| 9 | Revocation tested: revoke a test key and see 401 | Forge admin |

## 10. Open items

| Number | Item | Owner | Status |
| --- | --- | --- | --- |
| 1 | Migration `050_kernel_api.sql` written, reviewed, replayed with test/sql/replay.sh and applied; until then no key can be issued | Build, Director | Pending (not in the repository on 23/09/2026) |
| 2 | Field names inside `data` confirmed against 050 as merged; `openapi.yaml` corrected if they differ. The OpenAPI file uses `data` as the payload key, as the API test fixtures do | Build | Pending |
| 3 | Production host for the Forge API (`CNC_KERNEL_API_BASE`): the Vercel project now, MyClinicOnline hosting later | Director | Pending (HSF-3 for MCO) |
| 4 | Route for issuing keys: settings page button for forge_admin, or the REST call in 4.2; confirm the grants in 050 | Build | Pending |
| 5 | A function to change a key's hourly limit without a service role update | Build | Open |
| 6 | Where the bot is offered (website, internal, messaging) and who may use it | Director | Open |
| 7 | xAI as an operator: agreement, retention setting (default 30 days per xAI's FAQ, zero data retention for enterprise accounts), cross border note in the privacy policy | Director, Information Officer, attorney | Open |
| 8 | Direct read of the xAI documentation pages in section 7 before go live, since they could not be opened from the build environment | Odendaal | Open |
| 9 | Kernel currency: the live kernel is on release 1.0.0 (HSF-7). The holds in 050 keep repealed instruments out of the API, but the kernel release reported will stay 1.0.0 until 042 or its successor is applied | Director, OMP | Open, blocking Phase 2 |
