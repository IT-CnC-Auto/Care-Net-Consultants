import Link from "next/link";
import { Shell } from "@/components/shell";
import { Avatar, Btn, Icon, PageHead, Pill, SourceBadge } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { d, STAGES, STAGE_LABEL } from "@/lib/format";
import type { Task } from "@/lib/types";

const TONE: Record<string, string> = { onboard: "#BDBDBD", schedule: "#FFB81C", clinic_day: "#B35A1E", certificates: "#001489", invoice: "#007749", renewal: "#ED1B24", prospect: "#BDBDBD", quote: "#BDBDBD" };

export default async function Board() {
  const { person, sb, inboxCount } = await pageContext();
  const { data: tasks } = await sb.from("task").select("*, client:client(id,name), assignee:person!task_assignee_id_fkey(id,full_name,initials)").is("parent_id", null).neq("status", "completed").order("due_date");
  const { data: loads } = await sb.from("v_person_load").select("*").lt("capacity_open_parents", 900).order("open_parents", { ascending: false });
  const { data: progress } = await sb.from("v_task_progress").select("*");
  const { count: queue } = await sb.from("approval").select("id", { count: "exact", head: true }).eq("state", "pending").in("kind", ["allocation", "threshold"]);
  const prog = new Map((progress ?? []).map((p: any) => [p.task_id, p]));
  const all = (tasks ?? []) as Task[];
  const cols = STAGES.filter((s) => !["prospect", "quote"].includes(s));

  return (
    <Shell person={person} active="/board" crumbs={["Sales Executive desk", "Team board"]} inboxCount={inboxCount}>
      <PageHead title="Team board" sub="Every open parent task placed on the client journey · Sales Manager view">
        <Btn kind="sec" icon="users" href="/permissions">Reassign</Btn><Btn kind="pri" icon="sparkle" href="/inbox?tab=allocation">Allocate queue ({queue ?? 0})</Btn>
      </PageHead>
      <div className="flex items-start gap-2.5">
        {(loads ?? []).map((l: any) => { const pct = Math.min(100, Math.round(l.open_parents / l.capacity_open_parents * 100)); const over = l.open_parents > l.capacity_open_parents; return (
          <div key={l.person_id} className="flex min-w-0 flex-1 flex-col gap-2 rounded-md border border-cnc-line bg-white p-3 shadow-card">
            <div className="flex items-center gap-2"><Avatar initials={l.full_name.split(" ").map((x: string) => x[0]).join("").slice(0, 2)} size={26} /><div className="min-w-0"><div className="truncate text-[12.5px] font-semibold">{l.full_name}</div><div className="text-[11px] text-cnc-mute">{l.open_parents} open · {l.overdue} overdue</div></div><span className={`ml-auto font-heading text-[13px] font-semibold ${over ? "text-cnc-red" : ""}`}>{pct}%</span></div>
            <div className="h-1.5 overflow-hidden rounded-full bg-cnc-greyLight"><span className={`block h-full ${over ? "bg-cnc-red" : "bg-cnc-ink"}`} style={{ width: `${pct}%` }} /></div>
          </div>); })}
        <div className="flex w-[270px] shrink-0 flex-col gap-1.5 rounded-md bg-cnc-ink p-3 text-white"><div className="flex items-center gap-2"><Icon name="sparkle" size={16} className="text-cnc-red" /><span className="text-[12.5px] font-semibold">Allocation queue</span><span className="ml-auto font-heading text-[18px] font-semibold">{queue ?? 0}</span></div><div className="text-[11.5px] text-[#D6D6D6]">Allocation rule: standard task to the consultant with the largest book gap, high profile client to a senior with room. Sales Manager confirms.</div></div>
      </div>
      <div className="flex gap-3">
        {cols.map((s) => { const items = all.filter((t) => t.stage === s); return (
          <div key={s} className="flex min-w-0 flex-1 flex-col gap-2.5">
            <div className="flex h-8 items-center gap-2 px-1"><span className="h-2 w-2 rounded-full" style={{ background: TONE[s] }} /><span className="font-heading text-[12.5px] font-semibold">{STAGE_LABEL[s]}</span><span className="text-[11.5px] font-semibold text-cnc-mute">{items.length}</span></div>
            <div className="flex min-h-[380px] flex-col gap-2 rounded-md bg-cnc-greyLight p-2">
              {items.map((t) => { const p: any = prog.get(t.id); return (
                <Link key={t.id} href={`/tasks/${t.id}`} className="flex flex-col gap-2 rounded-sm border border-cnc-line bg-white p-3 shadow-card">
                  <div className="flex min-w-0 items-center gap-1.5 text-[11px] font-semibold text-cnc-mute"><Icon name="building" size={12} /><span className="truncate">{t.client?.name ?? "No client"}</span><span className="ml-auto"><SourceBadge source={t.source} /></span></div>
                  <div className="text-[12.5px] font-semibold leading-snug">{t.title}</div>
                  <div className="flex items-center gap-2"><Pill status={t.status} />{t.drafted_by_agent && <span className="inline-flex items-center gap-1 text-[10.5px] font-bold text-cnc-redDark"><Icon name="sparkle" size={11} />Grok</span>}<span className="ml-auto whitespace-nowrap text-[11px] text-cnc-mute">{p ? `${p.subtasks_done} of ${p.subtasks}` : ""}</span></div>
                  <div className={`flex items-center gap-1.5 text-[11.5px] ${t.status === "overdue" ? "text-cnc-redDark" : ""}`}><Icon name="calendar" size={13} className="text-cnc-mute" />{d(t.due_date)}<span className="ml-auto">{t.assignee && <Avatar initials={t.assignee.initials} size={24} />}</span></div>
                </Link>); })}
            </div>
          </div>); })}
      </div>
    </Shell>
  );
}
