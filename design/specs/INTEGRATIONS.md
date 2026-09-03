# Care Net tasks module: integration layer

Version 0.1 | British English | ZAR | Every price and API limit below is marked [CONFIRM] until checked against the live account or the vendor's current price page.

## 1. Principle

1.1 Buy transcripts, do not build them. Teams, Zoom and Fireflies all produce a transcript already. The agent layer only extracts tasks from text it is handed. That is where the value is and where the cost is lowest.

1.2 No new API server. Every connector is a Make scenario or a Supabase Edge Function with a named owner, a retry policy and a dead letter table. Make and Supabase are already in the estate and already paid for.

1.3 Store references, not copies. Supabase holds the task, the source reference (meeting id, message id, SharePoint item id) and a short extract. Documents stay in SharePoint. Recordings stay in Teams, Zoom or Fireflies. This keeps POPIA exposure and storage cost small.

1.4 AI drafts, a named human signs. Nothing the integration layer produces reaches a client without a person approving it in the portal.

## 2. Recommended stack

| Layer | Choice | Why | Cost [CONFIRM] |
|-------|--------|-----|----------------|
| Identity, mail, calendar, Teams, SharePoint | Microsoft Graph with one Entra app registration | One API for all of Microsoft 365. Entra SSO for the portal. Flagged Outlook email to task. Calendar gaps for auto scheduling. Teams channel notifications. SharePoint document links on tasks. | No API charge. Included in the existing M365 licences. |
| Meetings, phase 1 | Fireflies (already in the estate) | Joins Teams and Zoom meetings today, produces transcript and summary, has webhooks and an API. Zero build to start. | Existing subscription, about USD 19 per recording user per month on Business [CONFIRM]. |
| Meetings, phase 2 | Teams native transcript through Graph | Transcript is produced by Teams at no extra charge. Lets Care Net drop Fireflies seats later if it wants. | Included in M365. Graph transcript API metering [CONFIRM]. |
| Zoom | Only where a client insists | Zoom cloud recording produces an audio transcript on Pro and above. Fireflies covers it in phase 1 without extra work. | Zoom Pro about USD 13 to 16 per host per month [CONFIRM]. Not recommended as the default. |
| Language | Azure AI Translator | Covers Afrikaans, isiZulu, isiXhosa, Sesotho, Setswana and the other official languages. Free tier 2 million characters a month, then about USD 10 per million characters. Same tenant as M365. | Free at Care Net's expected volume [CONFIRM]. |
| Extraction and classification | Grok through the xAI API, small model first | Reads MCO task rows and transcripts, proposes tasks, allocation and drafts. Token cost is tiny at this volume. | Estimated under USD 5 a month at 1 to 2 million tokens [CONFIRM current xAI pricing]. |
| Automation bridge | Make | 13 live scenarios already. Webhooks in and out. | Existing plan. Operations per month [CONFIRM headroom]. |
| Data and functions | Supabase | Postgres with RLS, Edge Functions, Storage, pgvector for agent memory. | Pro plan about USD 25 a month [CONFIRM]. |

2.1 Worked cost example, monthly, at ZAR 18.50 to the dollar [CONFIRM rate].
Supabase Pro USD 25 = R462.50. Grok usage USD 5 = R92.50. Azure Translator USD 0 on the free tier. Graph USD 0. Make and Fireflies already paid. New spend roughly R555 a month plus VAT. Everything else is existing licences.

## 3. What "translator" should mean

3.1 Speech to text. Do not build it and do not ask Grok to do it. Grok has no speech input on its API [CONFIRM]. Use the transcript Teams, Zoom or Fireflies already made. If a recording arrives without a transcript, send it to Azure Speech or a Whisper class service at roughly USD 0.006 a minute [CONFIRM]. A 45 minute call is under R6.

3.2 Language translation. Consultants and clients speak more than English. Run the extract through Azure AI Translator so the task, the summary and the client message can be read in the reader's language. Keep the original language and the translation side by side in Supabase with a language tag. Grok can translate short summaries on the fly, but bulk and document translation goes to Azure because it is cheaper and predictable.

3.3 Task language. Every captured task is stored in English as the working language with the original extract attached. Client facing drafts are produced in the client's recorded language.

## 4. Flows

4.1 Meeting to task. Meeting ends. Fireflies (or Graph) fires a webhook to Make. Make calls a Supabase Edge Function with the transcript reference. The function stores the reference, sends the text to Grok with the client and journey context, receives proposed tasks each carrying a source reference, translates where needed, and writes them to Inbox under Captured. A person accepts, edits or discards.

4.2 Flagged email to task. Graph change notification on the consultant's mailbox for the flag action. Edge Function reads subject, sender name and the first lines, never the whole thread, proposes one task on the right client parent. The email stays in Outlook.

4.3 Calendar gaps. Graph calendarView read for the working day. Grok places focus blocks. Pinned blocks are not moved. Nothing is written to the calendar unless the person accepts.

4.4 Documents. Proposals, attendance lists and pro forma drafts are created in the client's SharePoint library. The task stores the drive item id and a link. Grok never receives the whole document, only the fields it needs.

4.5 Notifications. One daily digest by email through Graph. Exceptions (SLA at risk, signature waiting) to a Teams channel through an incoming webhook.

## 5. Entra app registration, least privilege [CONFIRM with the M365 administrator]

Application permissions requested: Mail.Read on consented mailboxes only, Calendars.Read, OnlineMeetingTranscript.Read.All (phase 2), Sites.Selected with access granted per client library, ChannelMessage.Send through webhook instead of Graph where possible. Admin consent recorded in the confirmation register. Secrets in Supabase Vault, never in Make scenario fields.

## 6. POPIA and clinical boundaries

6.1 Meeting recording and transcription need a notice at the start of the call. Add the notice to the Care Net meeting template.
6.2 Transcripts contain personal information. Retention: the reference is kept with the task, the extract is kept 90 days [CONFIRM], the full transcript stays in the source system under its own retention.
6.3 Medical outcomes never enter the transcript extract, the task or the translation store. The capture agent drops lines that name a worker with a health result and logs that it did so.
6.4 The capture agent reads untrusted content. It holds no secrets, writes only to its own report table, and treats instructions found in content as data.
6.5 Cross border: Azure region, Supabase region and xAI processing location are listed in the operator register [CONFIRM regions].

## 7. Build order

Phase 1, two weeks. Entra app, Graph mail flag and calendar read, Fireflies webhook to Make to Edge Function, Grok extraction, Inbox Captured, Azure Translator on summaries.
Phase 2. Teams native transcript through Graph, SharePoint Sites.Selected per client, Teams channel exceptions.
Phase 3. Zoom only if a client requires it. Whisper class fallback for recordings without transcripts.

## 8. Confirmation register additions

| Ref | Item | Owner |
|-----|------|-------|
| C17 | Fireflies plan and seat count in the estate | Director |
| C18 | Graph transcript API metering and admin consent | M365 administrator |
| C19 | xAI model choice and current per token pricing | Build agent |
| C20 | Azure Translator tier and region | Build agent |
| C21 | Zoom required by any client | Sales Manager |
| C22 | Transcript extract retention period | Information Officer |
