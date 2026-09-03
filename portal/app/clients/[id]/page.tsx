import Link from "next/link";
import { notFound } from "next/navigation";
import { Shell } from "@/components/shell";
import { Avatar, Btn, Card, Icon, PageHead, Pill, SourceBadge, StageChip, StatCard } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { d, dt, STAGES, STAGE_LABEL } from "@/lib/format";

export default async function Client({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { person, sb, inboxCount } = await pageContext();
  const { data: c } = await sb.from("client").select("*, owner:person!client_account_owner_id_fkey(full_name, initials), oversight:person!client_oversight_id_fkey(full_name, initials)").eq("id", id).maybeSingle();
  if (!c) notFound();
  const [{ data: tasks }, { data: contacts }, { data: events }] = await Promise.all([
    sb.from("task").select("id, ref, title, status, due_date, parent_id, medical_count, assignee:person!task_assignee_id_fkey(initials, full_name)").eq("client_id", id).neq("status", "completed").order("due_date").limit(8),
    sb.from("client_contact").select("*").eq("client_id", id),
    sb.from("audit_log").select("at, action, actor_kind, detail, actor:person!audit_log_actor_person_id_fkey(full_name, initials)").contains("detail", {}).order("at", { ascending: false }).limit(8),
  ]);
  const cur = STAGES.indexOf(c.current_stage);
  const medicalsDue = (tasks ?? []).filter((t) => !t.parent_id).reduce((n, t) => n + (t.medical_count ?? 0), 0);
  return (
    <Shell person={person} active="/clients" crumbs={["Sales Executive desk", "Clients", c.name]} inboxCount={inboxCount}>
      <Card>
        <div className="mb-4 flex items-start gap-4">
          <span className="inline-flex h-12 w-12 items-center justify-center rounded-md bg-cnc-ink font-heading text-[16px] font-semibold text-white">{c.name.slice(0, 2).toUpperCase()}</span>
          <div className="min-w-0"><h1 className="text-[20px] font-semibold">{c.name}</h1><div className="text-[12.5px] text-cnc-mute">{c.industry} · {(c.sites ?? []).join(" and ")} · {c.employees_on_surveillance ?? "?"} employees on medical surveillance</div>
            <div className="mt-2 flex flex-wrap items-center gap-2 text-[12px]"><Pill status="active" /><StageChip stage={c.current_stage} on /><span>Account owner</span>{c.owner && <><Avatar initials={c.owner.initials} size={22} /><span>{c.owner.full_name}</span></>}<span className="ml-1.5">Oversight</span>{c.oversight && <Avatar initials={c.oversight.initials} size={22} />}{c.client_source && <span className="ml-1.5 inline-flex h-[22px] items-center rounded-full bg-cnc-greyLight px-2 text-[11px] font-semibold">Client source: {c.client_source} · {c.client_source_recorded_at?.slice(0, 4)} · carried on every task</span>}</div></div>
          <div className="ml-auto flex gap-2"><Btn kind="sec" icon="external" href={`https://myclinic.online/clients/${c.mco_client_ref ?? ""}`}>Open in MCO</Btn><Btn kind="sec" icon="external" href="#">Open in AutoHive CRM</Btn><Btn kind="pri" icon="plus" href={`/work?new=1&client=${c.id}`}>New task</Btn></div>
        </div>
        <div className="flex items-center">{STAGES.map((s, i) => <div key={s} className="flex flex-1 items-center"><div className="flex w-[110px] flex-col items-center gap-1.5"><span className={`inline-flex h-6 w-6 items-center justify-center rounded-full border-2 ${i === cur ? "border-cnc-red bg-cnc-red" : i < cur ? "border-cnc-ink bg-cnc-ink" : "border-[#BDBDBD] bg-white"}`}>{i < cur ? <Icon name="check" size={12} className="text-white" /> : i === cur ? <span className="h-2 w-2 rounded-full bg-white" /> : null}</span><span className={`whitespace-nowrap text-[11.5px] font-semibold ${i === cur ? "text-cnc-redDark" : i < cur ? "text-cnc-ink" : "text-cnc-mute"}`}>{STAGE_LABEL[s]}</span></div>{i < STAGES.length - 1 && <span className={`-mx-[30px] mb-[22px] h-0.5 flex-1 ${i < cur - 1 ? "bg-cnc-ink" : i === cur - 1 ? "bg-cnc-red" : "bg-[#D6D6D6]"}`} />}</div>)}</div>
      </Card>
      <div className="flex gap-3">
        <StatCard label="Medicals due" value={medicalsDue} detail="from open MCO parents" /><StatCard label="Open tasks" value={tasks?.length ?? 0} /><StatCard label="Contract renewal" value={d(c.contract_renewal) || "—"} detail="SLA · annual" /><StatCard label="Sites" value={(c.sites ?? []).length} detail={(c.sites ?? []).join(", ")} />
      </div>
      <div className="flex gap-3">
        <Card title="Journey timeline" sub="every touchpoint from MCO, the agents and the team" className="min-w-0 flex-1">
          {(events ?? []).length === 0 && <p className="text-[12.5px] text-cnc-mute">No activity logged yet.</p>}
          {(events ?? []).map((e: any, i) => <div key={i} className="flex gap-3 border-t border-cnc-greyLight py-2.5 first:border-t-0"><Avatar initials={e.actor?.initials ?? "GA"} size={26} /><div className="min-w-0"><div className="flex items-center gap-2 text-[11.5px] text-cnc-mute"><span className="font-semibold text-cnc-ink">{e.actor?.full_name ?? "Grok agent"}</span>· {dt(e.at)}</div><div className="text-[12.5px]">{e.action.replace(/[._]/g, " ")}</div></div></div>)}
        </Card>
        <div className="flex w-[380px] shrink-0 flex-col gap-3">
          <Card title="Open tasks" right={<Link href={`/work`} className="text-[12px] font-semibold">View all</Link>}>{(tasks ?? []).map((t: any) => <Link key={t.id} href={`/tasks/${t.id}`} className="flex items-center gap-2.5 border-t border-cnc-greyLight py-2 text-[12.5px] first:border-t-0"><span className="h-4 w-4 shrink-0 rounded-[5px] border-[1.5px] border-[#BDBDBD]" /><span className={`min-w-0 flex-1 truncate ${!t.parent_id ? "font-semibold" : ""}`}>{t.title}</span><Pill status={t.status} /><span className="w-11 text-right text-[11.5px] text-cnc-mute">{d(t.due_date).slice(0, 5)}</span>{t.assignee && <Avatar initials={t.assignee.initials} size={22} />}</Link>)}</Card>
          <Card title="Client contacts"><p className="mb-1 text-[11.5px] text-cnc-mute">Names and roles only. Email and phone live in AutoHive CRM (POPIA board rule).</p>{(contacts ?? []).map((k) => <div key={k.id} className="flex items-center gap-2.5 border-t border-cnc-greyLight py-2"><span className="inline-flex h-[30px] w-[30px] items-center justify-center rounded-full bg-cnc-greyLight font-heading text-[11px] font-semibold">{k.display_name.split(" ").map((x: string) => x[0]).join("").slice(0, 2)}</span><div className="flex-1"><div className="text-[12.5px] font-semibold">{k.display_name}</div><div className="text-[11.5px] text-cnc-mute">{k.role}</div></div><Btn kind="ghost" small href="#">Open in CRM</Btn></div>)}</Card>
        </div>
      </div>
    </Shell>
  );
}
