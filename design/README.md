# Care Net AI tasks module – design handoff (Sales first)

Claude Design artboards for the AI tasks management module of the Care Net
Consultants sales platform. MyClinicOnline (MCO) tasks land in Supabase, Grok
agents read them, create one parent task per client, draft subtasks along the
client journey and propose who does the work. AI drafts, a named human signs.
Managers oversee through role rights. Sales is the first module; the same
shell carries Clinic operations, Finance and HR and compliance later.

This pack follows the CNC Sales platform design handoff (Client Portal shell
and CNC tokens) and its governing rules. Everything on screen is demo fixture
data and is labelled as such in the top bar.

## 1. Page list

| File | Screen | Who sees it | What is hidden or off |
|------|--------|-------------|-----------------------|
| `Main.dc.html` | 01 My work (Today view) | Sales Consultant | Only own tasks and clients. Team and other consultants' books are not in this list. |
| `Inbox.dc.html` | 02 Inbox | Every role, content differs | Consultant sees own items only. Sales Manager sees escalations and allocation signatures. Franchise Director sees threshold breaches and the daily agent digest. |
| `TeamBoard.dc.html` | 03 Team board | Sales Manager, Franchise Director | Franchisee own sales deals never appear. Package off for franchisees without Independent Sales or Full. |
| `ClientJourney.dc.html` | 04 Client 360 | Account owner, Sales Manager, Director | No contact email or phone (lives in AutoHive CRM). No employee medical outcomes. Cases by number. |
| `TaskDetail.dc.html` | 05 Task detail | Assignee, signer, watchers, Director | Rights on this task listed on the card. Send is blocked until a named human signs. |
| `Automations.dc.html` | 06 Sales automations | Sales Manager, Franchise Director | Consultants see run history only. Kill switch per rule. |
| `Permissions.dc.html` | 07 Roles and permissions | Franchise Director, Information Officer (read) | Medical outcomes are not viewable by any sales role. |
| `States.dc.html` | 08 Screen states | Reference for every screen | Empty, loading, error, forbidden (wrong tenant), package off. |
| `canvas.json` | Artboard layout and sticky notes | | Brief, matched shell and tokens, open questions. |

## 2. Component inventory

- **AppShell** 216px white sidebar (logo slot 457x303 asset, wordmark, nav, modules, signed in person), 64px top bar (breadcrumb, demo data chip, quick add bar, search, notifications, avatar), attribution footer pill marked [CONFIRM].
- **StatCard** 104px, label, value, detail, tone success / warning / danger. Same anatomy as the Client Portal desk.
- **TaskRow** tick, title, subline, status pill, journey chip, due, owner avatar, source badge. Indented variant for subtasks with a connector.
- **ClientGroupHeader** client, meta, parent and subtask count.
- **StatusPill** New, In progress, Completed (MCO vocabulary) plus Awaiting approval (outlined charcoal) and Overdue, On hold.
- **SourceBadge** MCO, Grok, Manual, AutoHive CRM.
- **JourneyChip** and **JourneyStepper** Prospect, Quote, Onboard, Schedule, Clinic day, Certificates, Invoice, Renewal.
- **AssistantRail** agent summary, signature requests, ask box, "AI drafts, a named human signs" line.
- **ApprovalBar** drafted by Grok, named signer, preview, request changes, approve and send.
- **KanbanCard** and **StageColumn** for the Team board.
- **WorkloadCard** consultant load against capacity, red when over.
- **AllocationQueue** dark card with the allocation rule text.
- **AgentRuleRow** rule id, trigger, agent and action, owner, runs, guard line, kill switch.
- **AgentRunRow** and **GuardrailList**.
- **OrgTree** person cards with parent and child connectors, agent as a service account.
- **RoleMatrix** allowed, propose, not allowed cells.
- **ConfirmTag** yellow [CONFIRM] chip for unconfirmed values.
- **EmptyState, LoadingSkeleton, ErrorBanner, ForbiddenState, PackageOffState** on screen 08.

## 3. Tokens

`design/tokens/` is copied from the CNC Sales platform handoff and is the
single source: red `#ED1B24` primary, red dark `#C1272D`, red tint `#FDE8E9`,
charcoal `#1E1E1E`, grey mid `#787878`, grey light `#F0F0F0`, panel `#F2F2F2`,
border `#E2E2E2`, blue `#001489` links and in progress, green `#007749`
success, yellow `#FFB81C` warning. Montserrat 600 headings, Open Sans body.
Radii 6 / 10 / 14, pills 999. Shadow `0 1px 3px rgba(0,0,0,.08), 0 4px 14px rgba(0,0,0,.06)`.
Active nav item is red tinted (8% red on white). Red is accent, overdue and
failure only.

## 4. Governing rules applied

- British English, sentence case, no dash or hyphen punctuation in prose or UI copy.
- The CRM is only ever "AutoHive CRM".
- Unconfirmed values carry [CONFIRM]: the 20 medical threshold, the 15 minute sync interval, the attribution pill.
- AI drafts, a named human signs. No agent sends, pays, files or advances a gated step. Every gated step names its signer.
- POPIA: no contact email or phone on boards. Cases by number, not worker name. Medical outcomes never enter the sales app. Emails carry counts and dates only.
- HPCSA: certificates are issued by the OMP only, never by the sales desk.
- Tickbox principle: every leaf is a single tick; the agent proposes the breakdown, the person accepts or edits it.
- One Task table serves every module. Ticket, complaint, renewal and campaign step are Task types.

## 5. MCO task type to journey stage (draft, confirm before build)

| MCO task type | Journey stage | Default agent |
|---------------|---------------|---------------|
| Medicals Due | Renewal | Booking agent, 30 to 90 days |
| Medicals Overdue | Renewal, priority High | Follow up agent |
| Medicals: Admin | Invoice | Documentation agent |
| Medicals: Documents, Medicals: ID Pending | Certificates | Documentation agent |
| Medicals: Error Resolution | Certificates | Documentation agent |
| Non Arrival | Clinic day | Booking agent, 30 to 90 days |
| Christmas message | Renewal (relationship) | Follow up agent |
| General, Other | Stage of the parent task, else Onboard | Allocation rule |

## 6. Open questions

- 20 medical threshold for Sales Manager sign off and who signs [CONFIRM].
- Sync interval, default 15 minutes [CONFIRM].
- May Grok close portal tasks when MCO marks them Completed, or always ask?
- Attribution pill on CNC screens [CONFIRM per licence tier].
- Team lead layer: needed now or when the team grows?

## 7. Regenerating

Edit `build.py`, then run `python3 design/build.py`. Every artboard is
produced from the generator so tokens, shell and copy stay consistent.
