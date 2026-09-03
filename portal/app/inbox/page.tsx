import Link from "next/link";
import { Shell } from "@/components/shell";
import { Avatar, Btn, Card, Empty, Icon, PageHead, SourceBadge } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { dt } from "@/lib/format";
import { decide } from "@/app/actions";
import type { Approval } from "@/lib/types";

const TABS = [["all", "Needs my signature"], ["allocation", "Allocations"], ["captured_task", "Captured"], ["threshold", "SLA and thresholds"], ["outbound_email", "Outbound email"], ["reassignment", "Reassignments"]];
const ICON: Record<string, string> = { allocation: "sparkle", outbound_email: "mail", threshold: "alert", reassignment: "users", captured_task: "message", schedule_block: "clock", close_from_mco: "refresh" };

export default async function Inbox({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  const { person, sb, inboxCount } = await pageContext();
  let q = sb.from("approval").select("*, task:task(ref, title), decider:person!approval_decided_by_fkey(full_name)").order("created_at", { ascending: false }).limit(50);
  q = sp.tab && sp.tab !== "all" ? q.eq("kind", sp.tab).eq("state", "pending") : q.eq("state", "pending");
  const { data } = await q;
  const items = (data ?? []) as (Approval & { task?: { ref: string; title: string } | null })[];
  const counts: Record<string, number> = {};
  const { data: allPending } = await sb.from("approval").select("kind").eq("state", "pending");
  for (const a of allPending ?? []) counts[a.kind] = (counts[a.kind] ?? 0) + 1;
  const { data: sync } = await sb.from("integration_sync").select("connector, status, last_ok_at, detail").order("connector");

  return (
    <Shell person={person} active="/inbox" crumbs={["Sales Executive desk", "Inbox"]} inboxCount={inboxCount}>
      <PageHead title="Inbox" sub="Everything that needs a decision from you in one place: agent proposals, signatures, captured tasks, SLA warnings">
        <Btn kind="sec" href="/inbox?tab=all">Refresh</Btn>
      </PageHead>
      <div className="flex gap-1 border-b border-cnc-line">{TABS.map(([k, label]) => <Link key={k} href={`/inbox?tab=${k}`} className={`-mb-px flex items-center gap-1.5 px-3 py-2 text-[13px] font-semibold ${(sp.tab ?? "all") === k ? "border-b-2 border-cnc-red text-cnc-ink" : "text-cnc-mute"}`}>{label}<span className="rounded-full bg-cnc-greyLight px-1.5 text-[11px] text-cnc-mute">{k === "all" ? allPending?.length ?? 0 : counts[k] ?? 0}</span></Link>)}</div>
      <div className="flex gap-3">
        <div className="min-w-0 flex-1">
          {items.length === 0 ? <Empty title="Nothing waits on you" text="Every agent proposal has a named human. When one lands here you will see the reasoning, the alternatives and one button to approve." /> : (
            <div className="overflow-hidden rounded-md border border-cnc-line bg-white shadow-card">
              {items.map((a) => (
                <div key={a.id} id={a.id} className="flex gap-3 border-t border-cnc-greyLight px-4 py-3.5 first:border-t-0">
                  <span className={`inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-sm ${a.requested_by_agent ? "bg-cnc-redTint text-cnc-red" : "bg-cnc-greyLight text-cnc-ink"}`}><Icon name={ICON[a.kind] ?? "inbox"} size={16} /></span>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2"><span className="text-[13px] font-semibold">{a.title}</span><SourceBadge source={a.requested_by_agent ? "grok" : "manual"} /><span className="ml-auto text-[11.5px] text-cnc-mute">{dt(a.created_at)}</span></div>
                    {a.detail && <div className="mt-0.5 text-[12.5px]">{a.detail}</div>}
                    {a.kind === "outbound_email" && (a.payload as any).draft_email && <pre className="mt-2 whitespace-pre-wrap rounded-sm bg-cnc-panel p-3 font-body text-[12px]">{String((a.payload as any).draft_email)}</pre>}
                    {a.kind === "captured_task" && Array.isArray((a.payload as any).tasks) && <ul className="mt-2 flex flex-col gap-1 text-[12.5px]">{(a.payload as any).tasks.map((t: any, i: number) => <li key={i} className="flex gap-2"><Icon name="check" size={14} className="mt-0.5 text-cnc-mute" /><span><strong>{t.title}</strong>{t.quote && <span className="text-cnc-mute"> · "{t.quote}"</span>}</span></li>)}</ul>}
                    <form action={decide} className="mt-2 flex items-center gap-1.5">
                      <input type="hidden" name="approval_id" value={a.id} />
                      {(a.options?.length ? a.options : [{ key: "approve", label: "Approve" }]).map((o, i) => <Btn key={o.key} kind={i === 0 ? "pri" : "sec"} small type="submit" name={o.key === "discard" || o.key === "dismiss" ? "decision" : "option"} value={o.key === "discard" || o.key === "dismiss" ? "reject" : o.key}>{o.label}</Btn>)}
                      {!a.options?.some((o) => o.key === "discard" || o.key === "dismiss") && <Btn kind="ghost" small type="submit" name="decision" value="reject">Decline</Btn>}
                      {a.task && <Link href={`/tasks/${a.task_id}`} className="ml-2 text-[12px] font-semibold">Open {a.task.ref}</Link>}
                      <span className="ml-auto inline-flex items-center gap-1.5 text-[11.5px] text-cnc-mute"><Avatar initials="GA" size={20} />{a.requested_by_agent ?? "person"}</span>
                    </form>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
        <aside className="flex w-[320px] shrink-0 flex-col gap-3">
          <Card title="Why you are seeing these"><p className="text-[12.5px]">You are the {person.role.replace(/_/g, " ")}. You receive the signatures named to you, anything escalated to your level and one daily digest. Consultants only see items for their own tasks.</p></Card>
          <Card title="Connectors">{(sync ?? []).map((s) => <div key={s.connector} className="flex justify-between border-t border-cnc-greyLight py-1.5 text-[12.5px]"><span>{s.connector.replace(/_/g, " ")}</span><span className={`font-semibold ${s.status === "ok" ? "text-cnc-green" : s.status === "failed" ? "text-cnc-redDark" : "text-cnc-mute"}`}>{s.status}</span></div>)}<Link href="/connections" className="mt-2 block text-[12px] font-semibold">Data and connections</Link></Card>
        </aside>
      </div>
    </Shell>
  );
}
