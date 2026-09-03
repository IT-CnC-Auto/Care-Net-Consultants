import { Shell } from "@/components/shell";
import { Avatar, Btn, Card, Icon, PageHead, SourceBadge } from "@/components/ui";
import { pageContext } from "@/lib/page";
import type { Task } from "@/lib/types";

const ROW = 44; const DAYS = 70; const LABEL = 300;

export default async function Timeline({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  const { person, sb, inboxCount } = await pageContext();
  const { data: parents } = await sb.from("task").select("id, ref, title, client:client(name)").is("parent_id", null).neq("status", "completed").order("due_date").limit(20);
  const parentId = sp.task ?? parents?.[0]?.id;
  const { data: tasks } = parentId ? await sb.from("task").select("*, assignee:person!task_assignee_id_fkey(initials, full_name)").or(`id.eq.${parentId},parent_id.eq.${parentId}`).order("start_date", { ascending: true, nullsFirst: true }) : { data: [] };
  const { data: deps } = await sb.from("task_dependency").select("predecessor_id, successor_id").in("successor_id", (tasks ?? []).map((t) => t.id));
  const rows = (tasks ?? []) as Task[];
  const start = new Date(); start.setDate(start.getDate() - start.getDay() + 1); start.setHours(0, 0, 0, 0);
  const AREA = 1176 - 40 - LABEL; const PX = AREA / DAYS;
  const x = (iso: string | null) => iso ? Math.max(0, Math.round((new Date(iso).getTime() - start.getTime()) / 86400000 * PX)) : 0;
  const idx = new Map(rows.map((r, i) => [r.id, i]));
  // critical path: longest chain by dependency depth
  const depth = (id: string, seen = new Set<string>()): number => { if (seen.has(id)) return 0; seen.add(id); const preds = (deps ?? []).filter((d) => d.successor_id === id); return preds.length ? 1 + Math.max(...preds.map((p) => depth(p.predecessor_id, seen))) : 0; };
  const depths = rows.map((r) => depth(r.id)); const maxDepth = Math.max(0, ...depths);
  const critical = new Set<string>(); let cur = rows[depths.indexOf(maxDepth)]?.id;
  while (cur) { critical.add(cur); const pred = (deps ?? []).find((d) => d.successor_id === cur); cur = pred?.predecessor_id; }
  const todayX = x(new Date().toISOString());
  const parent = rows.find((r) => !r.parent_id);

  return (
    <Shell person={person} active="/work" crumbs={["Sales Executive desk", "My work", "Timeline"]} inboxCount={inboxCount}>
      <PageHead title="Timeline" sub="Dependencies enforce start after finish · the critical path is red · pick a parent task to see its wave">
        <form className="flex gap-2"><select name="task" defaultValue={parentId} className="h-9 rounded-sm border border-cnc-line bg-white px-3 text-[13px]">{(parents ?? []).map((p: any) => <option key={p.id} value={p.id}>{p.client?.name ?? ""} · {p.title.slice(0, 50)}</option>)}</select><Btn kind="sec" type="submit">Show</Btn></form>
        {parent && <Btn kind="pri" icon="external" href={`/tasks/${parent.id}`}>Open task</Btn>}
      </PageHead>
      <Card title={parent ? `${parent.title}` : "No open parent tasks"} sub={`${rows.length} items · critical path highlighted`} right={parent && <SourceBadge source={parent.source} />}>
        <div className="flex">
          <div className="shrink-0 pr-3" style={{ width: LABEL }}>
            <div className="flex h-[34px] items-center text-[11px] font-bold uppercase tracking-wider text-cnc-mute">Task</div>
            {rows.map((r) => <div key={r.id} className={`flex items-center gap-2 border-t border-cnc-greyLight text-[12.5px] ${critical.has(r.id) || !r.parent_id ? "font-semibold" : ""}`} style={{ height: ROW, paddingLeft: r.parent_id ? 18 : 0 }}>{r.assignee ? <Avatar initials={r.assignee.initials} size={22} /> : <span className="w-[22px]" />}<span className="truncate">{r.title}</span></div>)}
          </div>
          <div className="relative flex-1 overflow-hidden">
            <div className="relative h-[34px] border-b border-cnc-line">{Array.from({ length: 10 }).map((_, w) => { const dte = new Date(start); dte.setDate(dte.getDate() + 7 * w); return <div key={w} className="absolute h-full border-l border-cnc-greyLight px-2 py-1.5 text-[11px] text-cnc-mute" style={{ left: w * 7 * PX, width: 7 * PX }}><span className="font-semibold text-cnc-ink">{dte.getDate()} {dte.toLocaleDateString("en-ZA", { month: "short" })}</span></div>; })}</div>
            <div className="relative" style={{ height: rows.length * ROW }}>
              {Array.from({ length: 10 }).map((_, w) => <div key={w} className="absolute top-0 h-full border-l border-cnc-greyLight" style={{ left: w * 7 * PX }} />)}
              <div className="absolute top-0 h-full border-l-2 border-dashed border-cnc-red" style={{ left: todayX }} /><div className="absolute -top-0.5 text-[10.5px] font-bold text-cnc-redDark" style={{ left: todayX + 6 }}>Today</div>
              <svg className="pointer-events-none absolute left-0 top-0" width={AREA} height={rows.length * ROW}>
                {(deps ?? []).map((dp) => { const a = idx.get(dp.predecessor_id); const b = idx.get(dp.successor_id); if (a === undefined || b === undefined) return null; const ra = rows[a]; const rb = rows[b]; const xa = x(ra.due_date) + PX; const ya = a * ROW + 22; const xb = x(rb.start_date ?? rb.due_date); const yb = b * ROW + 22; const col = critical.has(dp.successor_id) && critical.has(dp.predecessor_id) ? "#ED1B24" : "#9A9A9A"; return <g key={dp.predecessor_id + dp.successor_id}><path d={`M${xa},${ya} H${xa + 8} V${yb} H${xb - 2}`} fill="none" stroke={col} strokeWidth={1.5} /><path d={`M${xb - 6},${yb - 4} L${xb - 1},${yb} L${xb - 6},${yb + 4}`} fill="none" stroke={col} strokeWidth={1.5} /></g>; })}
              </svg>
              {rows.map((r, i) => { const s = r.start_date ?? r.due_date; const left = x(s); const w = Math.max(PX * 2, x(r.due_date) + PX - left); const kind = !r.parent_id ? "bg-cnc-greyLight border-cnc-line text-cnc-ink" : r.status === "completed" ? "bg-cnc-greenTint border-cnc-green text-cnc-green" : r.status === "awaiting_approval" ? "bg-white border-cnc-ink text-cnc-ink" : "bg-cnc-blueTint border-cnc-blueTint text-cnc-blue"; return <div key={r.id} className={`absolute flex h-6 items-center gap-1.5 overflow-hidden whitespace-nowrap rounded-sm border px-2 text-[11px] font-semibold ${kind} ${critical.has(r.id) && r.parent_id ? "ring-2 ring-cnc-red" : ""}`} style={{ left, top: i * ROW + 10, width: w }}>{w > 110 ? (r.parent_id ? r.status.replace(/_/g, " ") : r.ref) : ""}</div>; })}
            </div>
          </div>
        </div>
        <div className="mt-3.5 flex flex-wrap items-center gap-4 text-[11.5px] text-cnc-mute">
          <span className="flex items-center gap-1.5"><span className="h-2.5 w-3.5 rounded-sm border border-cnc-green bg-cnc-greenTint" />Completed</span><span className="flex items-center gap-1.5"><span className="h-2.5 w-3.5 rounded-sm border border-cnc-ink bg-white" />Awaiting approval</span><span className="flex items-center gap-1.5"><span className="h-2.5 w-3.5 rounded-sm bg-cnc-blueTint" />Planned</span><span className="flex items-center gap-1.5"><span className="h-2.5 w-3.5 rounded-sm bg-white ring-2 ring-cnc-red" />Critical path</span>
        </div>
      </Card>
    </Shell>
  );
}
