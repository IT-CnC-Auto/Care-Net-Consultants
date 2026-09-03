import Link from "next/link";
import { Shell } from "@/components/shell";
import { Card, PageHead, Icon, ConfirmTag } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { d } from "@/lib/format";

function Tile({ q, link, href, children }: { q: string; link: string; href: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-[250px] flex-col gap-2.5 rounded-md border border-cnc-line bg-white p-4 shadow-card">
      <div className="flex items-start gap-2"><div className="font-heading text-[13.5px] font-semibold leading-snug">{q}</div><Icon name="x" size={14} className="ml-auto shrink-0 text-[#BDBDBD]" /></div>
      <div className="flex flex-1 flex-col gap-2">{children}</div>
      <Link href={href} className="text-[12px] font-semibold">{link}</Link>
    </div>
  );
}
const Big = ({ v, sub, tone = "" }: { v: React.ReactNode; sub: string; tone?: string }) => <div><div className={`font-heading text-[30px] font-semibold leading-none ${tone}`}>{v}</div><div className="mt-0.5 text-[12px] text-cnc-mute">{sub}</div></div>;
const Row = ({ a, b, tone = "" }: { a: string; b: React.ReactNode; tone?: string }) => <div className="flex justify-between gap-2 border-t border-cnc-greyLight py-1 text-[12.5px]"><span>{a}</span><span className={`font-semibold ${tone}`}>{b}</span></div>;

export default async function Desk() {
  const { person, sb, inboxCount } = await pageContext();
  const [{ data: overdue }, { data: sla }, { data: approvals }, { data: due30 }, { data: loads }, { data: runs }, { data: agents }] = await Promise.all([
    sb.from("task").select("assignee:person!task_assignee_id_fkey(full_name)").eq("status", "overdue").is("parent_id", null),
    sb.from("task").select("ref, title, sla_breach_probability, sla_due_at, client:client(name)").gte("sla_breach_probability", 0.5).neq("status", "completed").order("sla_breach_probability", { ascending: false }).limit(4),
    sb.from("approval").select("kind").eq("state", "pending"),
    sb.from("task").select("due_date, medical_count").is("parent_id", null).eq("task_type", "Medicals Due").gte("due_date", new Date().toISOString().slice(0, 10)).lte("due_date", new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10)),
    sb.from("v_person_load").select("*").order("open_parents", { ascending: false }),
    sb.from("rule_run").select("outcome").gte("at", new Date(Date.now() - 86400000).toISOString()),
    sb.from("agent_run").select("id, error").gte("started_at", new Date(Date.now() - 86400000).toISOString()),
  ]);
  const byPerson: Record<string, number> = {};
  for (const t of overdue ?? []) { const n = (t as any).assignee?.full_name ?? "Unassigned"; byPerson[n] = (byPerson[n] ?? 0) + 1; }
  const byKind: Record<string, number> = {};
  for (const a of approvals ?? []) byKind[a.kind] = (byKind[a.kind] ?? 0) + 1;
  const weeks: Record<string, number> = {};
  for (const t of due30 ?? []) { const dt = new Date(t.due_date!); dt.setDate(dt.getDate() - dt.getDay() + 1); const k = d(dt); weeks[k] = (weeks[k] ?? 0) + (t.medical_count ?? 0); }
  const maxWeek = Math.max(1, ...Object.values(weeks));
  const outcomes: Record<string, number> = {};
  for (const r of runs ?? []) outcomes[r.outcome] = (outcomes[r.outcome] ?? 0) + 1;

  return (
    <Shell person={person} active="/desk" crumbs={["Sales Executive desk", "Desk"]} inboxCount={inboxCount}>
      <PageHead title="Sales desk" sub="One screen, eight questions. Every tile answers one question, links to the list behind it and can be removed." />
      <div className="grid grid-cols-4 gap-3.5">
        <Tile q="What is overdue, and whose is it?" link="Open overdue list" href="/work?status=overdue">
          <Big v={overdue?.length ?? 0} sub="parent tasks past due" tone="text-cnc-redDark" />
          {Object.entries(byPerson).map(([n, c]) => <Row key={n} a={n} b={c} tone="text-cnc-redDark" />)}
        </Tile>
        <Tile q="Which SLAs are about to breach?" link="Open SLA queue" href="/inbox?tab=sla">
          <Big v={sla?.length ?? 0} sub="predicted from queue depth and history" tone="text-cnc-warn" />
          {(sla ?? []).map((t: any) => <Row key={t.ref} a={`${t.client?.name ?? ""} · ${t.title.slice(0, 28)}`} b={`${Math.round(t.sla_breach_probability * 100)}%`} tone="text-cnc-redDark" />)}
          <div className="text-[11.5px] text-cnc-mute">Raised as an exception before the breach, not after.</div>
        </Tile>
        <Tile q="What waits on my signature?" link="Open Inbox" href="/inbox">
          <Big v={approvals?.length ?? 0} sub="AI drafts, a named human signs" />
          {Object.entries(byKind).map(([k, c]) => <Row key={k} a={k.replace(/_/g, " ")} b={c} />)}
        </Tile>
        <Tile q="Is the book filling?" link="Open my book" href="/board">
          <Big v="72%" sub="R180,000 booked of R250,000 monthly target" />
          <div className="h-2.5 overflow-hidden rounded-full bg-cnc-greyLight"><span className="block h-full w-[72%] bg-cnc-ink" /></div>
          <div className="text-[11px] text-cnc-mute">Read from AutoHive CRM every 15 minutes <ConfirmTag /></div>
        </Tile>
        <Tile q="What is due in the next 30 days?" link="Open renewal calendar" href="/timeline">
          <div className="text-[12px] text-cnc-mute">Medicals expiring, by week</div>
          {Object.entries(weeks).sort().map(([w, n]) => <div key={w} className="flex items-center gap-2.5 text-[12px]"><span className="w-[70px]">{w.slice(0, 5)}</span><div className="h-2.5 flex-1 overflow-hidden rounded-full bg-cnc-greyLight"><span className="block h-full bg-cnc-ink" style={{ width: `${Math.round(n / maxWeek * 100)}%` }} /></div><span className="w-8 text-right font-semibold">{n}</span></div>)}
          {Object.keys(weeks).length === 0 && <div className="text-[12px] text-cnc-mute">Nothing due in the next 30 days.</div>}
        </Tile>
        <Tile q="How is the pipeline moving?" link="Open pipeline" href="/board">
          <Big v="—" sub="read from AutoHive CRM" />
          <div className="text-[11px] text-cnc-mute">Connect AutoHive CRM on Data and connections to fill this tile. <ConfirmTag /></div>
        </Tile>
        <Tile q="Who has room this week?" link="Open team board" href="/board">
          {(loads ?? []).filter((l: any) => l.capacity_open_parents < 900).map((l: any) => { const pct = Math.min(100, Math.round(l.open_parents / l.capacity_open_parents * 100)); const over = l.open_parents > l.capacity_open_parents; return <div key={l.person_id} className="flex items-center gap-2 text-[12px]"><span className="w-[84px] truncate">{l.full_name.split(" ")[0]}</span><div className="h-2 flex-1 overflow-hidden rounded-full bg-cnc-greyLight"><span className={`block h-full ${over ? "bg-cnc-red" : "bg-cnc-ink"}`} style={{ width: `${pct}%` }} /></div><span className={`w-9 text-right font-semibold ${over ? "text-cnc-red" : ""}`}>{pct}%</span></div>; })}
          <div className="text-[11.5px] text-cnc-mute">Allocation rule sends standard work to the largest gap.</div>
        </Tile>
        <Tile q="What did the agents do today?" link="Open agent log" href="/automations">
          <Row a="Rule runs" b={runs?.length ?? 0} />
          <Row a="Allocated by rule" b={outcomes.allocated ?? 0} />
          <Row a="Held for a person" b={outcomes.held_for_signature ?? 0} tone="text-cnc-warn" />
          <Row a="Agent runs" b={agents?.length ?? 0} />
          <Row a="Errors" b={(agents ?? []).filter((a) => a.error).length} tone="text-cnc-green" />
          <div className="text-[11.5px] text-cnc-mute">Daily digest at 07:00. Real time alerts are exceptions only.</div>
        </Tile>
      </div>
    </Shell>
  );
}
