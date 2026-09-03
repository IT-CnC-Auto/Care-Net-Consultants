import { Shell } from "@/components/shell";
import { Btn, Card, ConfirmTag, Icon, PageHead, Pill } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { dt } from "@/lib/format";

const CONNECTORS = [
  { key: "graph_mail", icon: "mail", name: "Microsoft 365 · Graph", role: "Identity, mail, calendar, Teams, SharePoint through one Entra app", reads: "flagged email (subject, sender, first lines), calendar gaps, Teams transcripts", writes: "daily digest email, Teams channel exceptions, nothing to the calendar without acceptance", cost: "no API charge, included in licences", phase: 1, guard: "Least privilege: Mail.Read on consented mailboxes, Calendars.Read, Sites.Selected per client library" },
  { key: "sharepoint", icon: "file", name: "SharePoint", role: "Client document libraries", reads: "drive item id and link for proposals, attendance lists, pro forma drafts", writes: "documents created in the client library from templates, task stores the link only", cost: "included in M365", phase: 2, guard: "Grok receives fields, never the whole document" },
  { key: "fireflies", icon: "message", name: "Fireflies", role: "Meeting layer for Teams and Zoom, phase 1", reads: "transcript and summary by webhook after each call", writes: "nothing", cost: "existing subscription, about USD 19 per recording seat", phase: 1, guard: "Recording notice at the start of every call" },
  { key: "teams_transcript", icon: "users", name: "Teams native transcript", role: "Replaces Fireflies seats later if wanted", reads: "OnlineMeetingTranscript through Graph", writes: "nothing", cost: "included in M365, API metering", phase: 2 },
  { key: "zoom", icon: "db", name: "Zoom", role: "Only where a client insists on Zoom", reads: "cloud recording transcript on Pro and above", writes: "nothing", cost: "about USD 13 to 16 per host per month", phase: 3, guard: "Fireflies already covers Zoom calls in phase 1" },
  { key: "translator", icon: "layers", name: "Azure AI Translator", role: "Language layer: Afrikaans, isiZulu, isiXhosa, Sesotho, Setswana and the rest", reads: "task extract, summary, client draft", writes: "translation stored beside the original with a language tag", cost: "free to 2 million characters a month, then about USD 10 per million", phase: 1 },
  { key: "grok", icon: "bot", name: "Grok · xAI API", role: "Extraction, classification, allocation proposals, drafts. Text only, never audio", reads: "MCO rows, transcript text, email extract, client and journey context", writes: "proposed tasks with source reference into Inbox, agent_run log", cost: "under USD 5 a month at 1 to 2 million tokens", phase: 1, guard: "Reads untrusted content: no secrets, writes to its own report table only" },
  { key: "mco", icon: "db", name: "MyClinicOnline", role: "System of record for medicals", reads: "mco_task rows every 15 minutes", writes: "nothing, MCO is read only from the portal", cost: "existing", phase: 1 },
];

export default async function Connections() {
  const { person, sb, inboxCount } = await pageContext();
  const { data: sync } = await sb.from("integration_sync").select("*");
  const { data: dead } = await sb.from("dead_letter").select("id, at, function_name, error").eq("resolved", false).order("at", { ascending: false }).limit(6);
  const s = new Map((sync ?? []).map((x) => [x.connector, x]));
  return (
    <Shell person={person} active="/automations" crumbs={["Sales Executive desk", "Sales automations", "Data and connections"]} inboxCount={inboxCount}>
      <PageHead title="Data and connections" sub="Buy transcripts, do not build them. Store references, not copies. Every connector is a Supabase Edge Function with an owner, a retry and a dead letter table."><Btn kind="sec" href="/automations">Back to rules</Btn></PageHead>
      <div className="grid grid-cols-3 gap-3">
        {CONNECTORS.map((c) => { const st: any = s.get(c.key); return (
          <div key={c.key} className="flex min-w-0 flex-col gap-2 rounded-md border border-cnc-line bg-white p-4 shadow-card">
            <div className="flex items-center gap-2.5"><span className="inline-flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-sm bg-cnc-redTint text-cnc-red"><Icon name={c.icon} /></span><div className="min-w-0"><div className="font-heading text-[13.5px] font-semibold">{c.name}</div><div className="text-[11.5px] text-cnc-mute">{c.role}</div></div><span className="ml-auto"><Pill status={st?.status ?? "paused"} text={st?.status === "ok" ? "Live" : st?.status === "failed" ? "Failed" : `Phase ${c.phase}`} /></span></div>
            <div className="text-[12px]"><strong>Reads</strong> {c.reads}</div><div className="text-[12px]"><strong>Writes</strong> {c.writes}</div><div className="flex items-center gap-2 text-[12px]"><strong>Cost</strong> {c.cost} <ConfirmTag /></div>
            {c.guard && <div className="flex items-start gap-1.5 text-[11.5px] font-semibold text-cnc-blue"><Icon name="shield" size={12} className="mt-0.5 shrink-0" />{c.guard}</div>}
            {st?.last_ok_at && <div className="text-[11px] text-cnc-mute">Last OK {dt(st.last_ok_at)}</div>}
          </div>); })}
      </div>
      <Card title="Dead letters" sub="failed runs waiting for a person">{(dead ?? []).length === 0 ? <p className="text-[12.5px] text-cnc-mute">Nothing failed.</p> : (dead ?? []).map((x) => <div key={x.id} className="flex gap-3 border-t border-cnc-greyLight py-2 text-[12px]"><span className="text-cnc-mute">{dt(x.at)}</span><span className="font-semibold">{x.function_name}</span><span className="truncate text-cnc-redDark">{x.error}</span></div>)}</Card>
    </Shell>
  );
}
