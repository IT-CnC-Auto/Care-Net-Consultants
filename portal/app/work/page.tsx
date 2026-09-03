import Link from "next/link";
import { Shell } from "@/components/shell";
import { Avatar, Btn, Card, Empty, Icon, PageHead, Pill, SourceBadge, StageChip, StatCard } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { d } from "@/lib/format";
import { tick, quickAdd } from "@/app/actions";
import type { Task } from "@/lib/types";

export default async function Work({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  const { person, sb, inboxCount } = await pageContext();
  if (sp.quick) { await quickAdd(sp.quick); }
  const today = new Date().toISOString().slice(0, 10);
  let q = sb.from("task").select("*, client:client(id,name), assignee:person!task_assignee_id_fkey(id,full_name,initials)").neq("status", "completed").order("rank_score", { ascending: true, nullsFirst: false }).order("due_date", { ascending: true });
  if (sp.status) q = q.eq("status", sp.status);
  if (person.role === "sales_consultant") q = q.eq("assignee_id", person.id);
  const { data: tasks } = await q;
  const all = (tasks ?? []) as Task[];
  const parents = all.filter((t) => !t.parent_id);
  const children = (id: string) => all.filter((t) => t.parent_id === id);
  const byClient = new Map<string, Task[]>();
  for (const p of parents) { const k = p.client?.name ?? "No client"; byClient.set(k, [...(byClient.get(k) ?? []), p]); }
  const dueToday = all.filter((t) => t.due_date === today).length;
  const overdue = all.filter((t) => t.status === "overdue").length;
  const { count: sig } = await sb.from("approval").select("id", { count: "exact", head: true }).eq("state", "pending").eq("approver_id", person.id);
  const { count: ticked } = await sb.from("task").select("id", { count: "exact", head: true }).eq("status", "completed").gte("completed_at", new Date(Date.now() - 7 * 86400000).toISOString());
  const { data: myApprovals } = await sb.from("approval").select("id, title, detail, kind").eq("state", "pending").eq("approver_id", person.id).limit(2);

  return (
    <Shell person={person} active="/work" crumbs={["Sales Executive desk", "My work"]} inboxCount={inboxCount}>
      <div className="flex gap-5">
        <div className="flex min-w-0 flex-1 flex-col gap-4">
          <PageHead title="My work" sub={`${new Date().toLocaleDateString("en-ZA", { weekday: "long", day: "numeric", month: "long", year: "numeric" })} · ${person.full_name} · ranked by due date, SLA risk and dependency`}>
            <Btn kind="sec" icon="plus" href="/work?new=1">Add a task</Btn><Btn kind="sec" icon="file" href="/api/export">Excel report</Btn><Btn kind="pri" icon="sparkle" href="/work#assistant">Ask the assistant</Btn>
          </PageHead>
          <div className="flex gap-1 border-b border-cnc-line">{[["Today", "/work"], ["List", "/work?view=list"], ["Board", "/board"], ["Timeline", "/timeline"], ["Client journey", "/clients"]].map(([t, h], i) => <Link key={t} href={h} className={`-mb-px px-3 py-2 text-[13px] font-semibold ${i === 0 ? "border-b-2 border-cnc-red text-cnc-ink" : "text-cnc-mute"}`}>{t}</Link>)}</div>
          <div className="flex gap-3">
            <StatCard label="Due today" value={dueToday} detail="from the MCO sync and your own tasks" />
            <StatCard label="Overdue" value={overdue} tone="danger" detail={overdue ? "act on these first" : "nothing overdue"} />
            <StatCard label="Awaiting my signature" value={sig ?? 0} tone="warning" detail="Grok drafts to review before they send" />
            <StatCard label="Ticked this week" value={ticked ?? 0} tone="success" detail="every leaf is a single tick" />
          </div>
          {parents.length === 0 ? (
            <Empty title="Nothing due today" text="There are no results for the selected filters. The next MCO sync runs within 15 minutes. Tasks from clients you do not own are not in this list, which is correct."><Btn kind="sec" icon="plus" href="/work?new=1">Add a task</Btn></Empty>
          ) : (
            <div className="overflow-hidden rounded-md border border-cnc-line bg-white shadow-card">
              <div className="grid h-9 grid-cols-[minmax(0,1fr)_130px_150px_100px_72px_90px] items-center px-4 text-[11px] font-bold uppercase tracking-wider text-cnc-mute"><div>Task</div><div>Status</div><div>Journey stage</div><div>Due</div><div>Owner</div><div className="text-right">Source</div></div>
              {[...byClient.entries()].map(([client, ps]) => (
                <div key={client}>
                  <div className="flex h-[46px] items-center gap-3 border-t border-cnc-line bg-[#FAFAFA] px-4"><Icon name="building" size={16} className="text-cnc-mute" /><span className="font-heading text-[13.5px] font-semibold">{client}</span><span className="ml-auto text-[11.5px] font-semibold text-cnc-mute">{ps.length} parent · {ps.reduce((n, p) => n + children(p.id).length, 0)} subtasks</span></div>
                  {ps.map((p) => <><TaskRow key={p.id} t={p} />{children(p.id).map((c) => <TaskRow key={c.id} t={c} indent />)}</>)}
                </div>
              ))}
            </div>
          )}
        </div>
        <aside className="flex w-[300px] shrink-0 flex-col gap-3">
          <Card title="Assistant" className="scroll-mt-4" right={<span className="text-[11px] text-cnc-mute">Grok</span>}>
            <div id="assistant" className="flex flex-col gap-2">
              {(myApprovals ?? []).length === 0 && <p className="text-[12.5px] text-cnc-mute">Nothing waits on your signature.</p>}
              {(myApprovals ?? []).map((a) => <div key={a.id} className="flex flex-col gap-1.5 rounded-sm border border-cnc-line p-2.5"><div className="text-[12.5px] font-semibold">{a.title}</div><div className="text-[11.5px] text-cnc-mute">{a.detail}</div><Btn kind="pri" small href={`/inbox#${a.id}`}>Review</Btn></div>)}
              <form action="/api/assistant" method="post" className="mt-1 flex h-10 items-center gap-2 rounded-sm border border-cnc-line px-3 text-[12.5px] text-cnc-mute"><input name="question" placeholder="Ask about a client or task" className="w-full bg-transparent outline-none" /><Icon name="chevright" size={14} /></form>
              <div className="text-[11px] text-cnc-mute">AI drafts, a named human signs. Nothing sends without you.</div>
            </div>
          </Card>
          <Card title="Today" right={<Link href="/api/calendar" className="inline-flex h-[26px] items-center gap-1.5 rounded-full border border-cnc-line px-2 text-[11px] font-semibold text-cnc-ink"><Icon name="clock" size={12} />Plan focus blocks</Link>}>
            <p className="text-[11px] text-cnc-mute">Grok places focus blocks into calendar gaps from Microsoft 365. Pin a block to stop it moving.</p>
          </Card>
        </aside>
      </div>
    </Shell>
  );
}

function TaskRow({ t, indent = false }: { t: Task; indent?: boolean }) {
  const done = t.status === "completed";
  return (
    <div className={`grid grid-cols-[minmax(0,1fr)_130px_150px_100px_72px_90px] items-center border-t border-cnc-greyLight bg-white pr-4 ${indent ? "h-11 pl-14" : "h-[52px] pl-4"}`}>
      <div className="flex min-w-0 items-center gap-2.5">
        {indent && <span className="-mt-2 mr-1.5 h-3.5 w-3.5 shrink-0 rounded-bl border-b border-l border-[#CFCFCF]" />}
        <form action={tick}><input type="hidden" name="task_id" value={t.id} /><input type="hidden" name="done" value={done ? "false" : "true"} /><button className={`inline-flex h-[18px] w-[18px] items-center justify-center rounded-[5px] border-[1.5px] ${done ? "border-transparent bg-cnc-green text-white" : "border-[#BDBDBD] bg-white"}`} aria-label="Tick">{done && <Icon name="check" size={12} />}</button></form>
        <div className="min-w-0">
          <div className="flex items-center gap-2"><Link href={`/tasks/${t.id}`} className={`truncate text-[13px] text-cnc-ink ${indent ? "font-medium" : "font-semibold"}`}>{t.title}</Link>{t.drafted_by_agent && <span className="inline-flex shrink-0 items-center gap-1 text-[10.5px] font-bold text-cnc-redDark"><Icon name="sparkle" size={12} />drafted</span>}</div>
          {t.rank_reason && !indent && <div className="truncate text-[11.5px] text-cnc-mute">{t.rank_reason}</div>}
        </div>
      </div>
      <div><Pill status={t.status} /></div>
      <div>{t.stage && <StageChip stage={t.stage} on={!indent} done={indent} />}</div>
      <div className={`flex items-center gap-1.5 text-[12.5px] ${t.status === "overdue" ? "text-cnc-redDark" : ""}`}><Icon name="calendar" size={14} className={t.status === "overdue" ? "text-cnc-redDark" : "text-cnc-mute"} />{d(t.due_date)}</div>
      <div>{t.assignee && <Avatar initials={t.assignee.initials} name={t.assignee.full_name} size={26} />}</div>
      <div className="flex justify-end"><SourceBadge source={t.source} /></div>
    </div>
  );
}
