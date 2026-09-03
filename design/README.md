# Care Net AI Tasks Portal – design source

Claude Design artboards for the AI tasks management system that brings
MyClinicOnline (MCO) tasks into the Care Net portal via Supabase, lets Grok
bots create and allocate parent/sub-tasks per employee, and keeps management
oversight through role rights. The Sales dashboard is the first department;
the same shell is reused for the others.

## Files

| File | Screen |
|------|--------|
| `Main.dc.html` | 01 My Work – consultant view (Celeste), parent task per MCO item with sub-tasks along the client journey, assistant rail |
| `Inbox.dc.html` | 02 Inbox – director approvals: bot allocations, outbound email holds, threshold escalations, MCO changes |
| `TeamBoard.dc.html` | 03 Team Board – manager view, workload per consultant, columns by journey stage, allocation queue |
| `ClientJourney.dc.html` | 04 Client 360 – journey stepper, timeline of MCO / bot / human touchpoints, open tasks, next best action |
| `TaskDetail.dc.html` | 05 Task detail – parent task, sub-task checklist, bot approval bar, properties and per-task permissions |
| `Automations.dc.html` | 06 Automations – MCO → Supabase → Grok → Portal → People pipeline, allocation rules, bot runs, guardrails |
| `Permissions.dc.html` | 07 Permissions – parent/child org tree and role rights matrix (Director, Manager, Team lead, Consultant, Grok bot) |
| `canvas.json` | Artboard layout and sticky notes (brief, design principles, open questions) |
| `build.py` | Generator – edit this, then run `python3 design/build.py` to regenerate the artboards |

## Design system used

- CNC Red `#ED1B24` leads, charcoal `#1F1F1F` carries text, light grey ground `#F5F5F3`
- Support colours only for status: green (completed), blue (in progress), yellow (new), purple (awaiting approval), red (overdue)
- Montserrat for headings, Open Sans for body (Google Fonts)
- Status vocabulary kept from MCO: New · In progress · Completed, plus Awaiting approval and Overdue
- Journey stages: Prospect · Quote · Onboard · Schedule · Clinic day · Certificates · Invoice · Renewal
- Source badge on every task: MCO · Grok · Manual · CRM

## Open questions captured on the canvas

- 20-medical threshold for manager approval of a bot allocation: confirm the number and the approver.
- MCO task type → journey stage mapping (draft on screen 06).
- Whether Grok may auto-close portal tasks when MCO marks them Completed, or must always ask.
- Whether a Team lead layer is needed now.
