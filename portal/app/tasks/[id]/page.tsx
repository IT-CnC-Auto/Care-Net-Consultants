import Link from "next/link";
import { notFound } from "next/navigation";
import { Shell } from "@/components/shell";
import { Avatar, Btn, Card, Icon, Pill, SourceBadge, StageChip } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { d, dt } from "@/lib/format";
import { comment, decide, logFocus, tick } from "@/app/actions";

export default async function TaskPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { person, sb, inboxCount } = await pageContext();
  const { data: t } = await sb.from("task").select("*, client:client(id, name), assignee:person!task_assignee_id_fkey(id, full_name, initials), signer:person!task_signer_id_fkey(full_name, initials), template:template(name, version)").eq("id", id).maybeSingle();
  if (!t) notFound();
  const [{ data: subs }, { data: approvals }, { data: comments }, { data: runs }, { data: deps }, { data: time }, { data: docs }] = await Promise.all([
    sb.from("task").select("*, assignee:person!task_assignee_id_fkey(initials, full_name)").eq("parent_id", id).order("start_date", { ascending: true, nullsFirst: true }),
    sb.from("approval").select("*").eq("task_id", id).eq("state", "pending"),
    sb.from("task_comment").select("*, author:person(full_name, initials)").eq("task_id", id).order("created_at", { ascending: false }).limit(10),
    sb.from("agent_run").select("*").eq("input_ref", t.source_ref ?? "").order("started_at", { ascending: false }).limit(5),
    sb.from("task_dependency").select("predecessor_id, successor_id").or(`predecessor_id.eq.${id},successor_id.eq.${id}`),
    sb.from("time_entry").select("minutes").eq("task_id", id),
    sb.from("task_document").select("*").eq("task_id", id),
  ]);
  const minutes = (time ?? []).reduce((n, x) => n + x.minutes, 0);
  const done = (subs ?? []).filter((s) => s.status === "completed").length;
  const Prop = ({ l, children }: { l: string; children: React.ReactNode }) => <div className="flex min-h-9 items-center gap-3"><span className="w-[110px] shrink-0 text-[12px] font-semibold text-cnc-mute">{l}</span><div className="flex min-w-0 items-center gap-2 text-[13px]">{children}</div></div>;

  return (
    <Shell person={person} active="/work" crumbs={["Sales Executive desk", "My work", t.client?.name ?? "Task", t.ref]} inboxCount={inboxCount}>
      <div className="flex gap-4">
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          <div className="flex items-start gap-4">
            <div className="min-w-0"><div className="flex items-center gap-2 text-[12px] text-cnc-mute"><span>{t.parent_id ? "Subtask" : "Parent task"}</span>·<span>{t.ref}</span>·<SourceBadge source={t.source} /></div><h1 className="mt-1 text-[21px] font-semibold leading-snug">{t.title}</h1></div>
            <div className="ml-auto flex shrink-0 gap-2">
              <form action={tick}><input type="hidden" name="task_id" value={t.id} /><input type="hidden" name="done" value={t.status === "completed" ? "false" : "true"} /><Btn kind="sec" icon="check" type="submit">{t.status === "completed" ? "Reopen" : "Mark complete"}</Btn></form>
              <Btn kind="sec" icon="users" href="/permissions">Reassign</Btn>{t.source === "mco" && <Btn kind="sec" icon="external" href={t.source_url ?? "#"}>Open in MCO</Btn>}
            </div>
          </div>
          {(approvals ?? []).map((a) => (
            <div key={a.id} className="flex items-center gap-3 rounded-md border border-[#F3C4C6] bg-cnc-redSoft px-4 py-3"><span className="inline-flex h-8 w-8 items-center justify-center rounded-sm bg-cnc-red text-white"><Icon name="sparkle" size={16} /></span><div className="flex-1"><div className="text-[13px] font-semibold">{a.title}. A named human signs{t.signer ? `: ${t.signer.full_name}` : ""}.</div><div className="text-[12px]">{a.detail}</div></div>
              <form action={decide} className="flex gap-2"><input type="hidden" name="approval_id" value={a.id} /><Btn kind="sec" type="submit" name="decision" value="reject">Request changes</Btn><Btn kind="pri" icon="check" type="submit" name="decision" value="approve">Approve{a.kind === "outbound_email" ? " and send" : ""}</Btn></form></div>
          ))}
          {!t.parent_id && <Card title="Subtasks" sub={`${done} of ${subs?.length ?? 0} ticked`} right={<Link href={`/work?new=1&parent=${t.id}`} className="inline-flex items-center gap-1.5 text-[12.5px] font-semibold"><Icon name="plus" size={14} />Add subtask</Link>}>
            {(subs ?? []).map((s: any) => { const blocked = (deps ?? []).some((dp) => dp.successor_id === s.id); return (
              <div key={s.id} className="flex items-start gap-3 border-t border-cnc-greyLight py-2.5">
                <form action={tick}><input type="hidden" name="task_id" value={s.id} /><input type="hidden" name="done" value={s.status === "completed" ? "false" : "true"} /><button className={`mt-0.5 inline-flex h-[18px] w-[18px] items-center justify-center rounded-[5px] border-[1.5px] ${s.status === "completed" ? "border-transparent bg-cnc-green text-white" : "border-[#BDBDBD] bg-white"}`}>{s.status === "completed" && <Icon name="check" size={12} />}</button></form>
                <div className="min-w-0 flex-1"><Link href={`/tasks/${s.id}`} className={`text-[13px] font-semibold text-cnc-ink ${s.status === "completed" ? "line-through text-[#8A8A8A]" : ""}`}>{s.title}</Link><div className="text-[11.5px] text-cnc-mute">{blocked ? "Blocked by a predecessor, start after finish" : s.drafted_by_agent ? "Drafted by Grok" : ""}{s.stage ? ` · ${s.stage.replace("_", " ")}` : ""}</div></div>
                <Pill status={s.status} /><span className="w-11 text-right text-[12px]">{d(s.due_date).slice(0, 5)}</span>{s.assignee && <Avatar initials={s.assignee.initials} size={24} />}
              </div>); })}
            <div className="mt-2 text-[11.5px] text-cnc-mute">Tickbox principle: every leaf is a single tick. The agent proposes the breakdown, a person accepts or edits it.</div>
          </Card>}
          {t.description && <Card title="Description" sub={t.drafted_by_agent ? "summarised by Grok from MCO" : undefined}><p className="text-[13px] leading-relaxed">{t.description}</p>{(docs ?? []).length > 0 && <div className="mt-2.5 flex gap-2">{(docs ?? []).map((x) => <a key={x.id} href={x.web_url ?? "#"} className="inline-flex h-7 items-center gap-1.5 rounded-sm border border-cnc-line px-2.5 text-[12px] text-cnc-ink"><Icon name="file" size={13} className="text-cnc-mute" />{x.name}</a>)}</div>}</Card>}
          <Card title="Activity" right={<form action={logFocus}><input type="hidden" name="task_id" value={t.id} /><input type="hidden" name="minutes" value="25" /><Btn kind="sec" small icon="clock" type="submit">Log 25 min focus</Btn></form>}>
            {(runs ?? []).map((r) => <div key={r.id} className="flex gap-3 border-t border-cnc-greyLight py-2.5 first:border-t-0"><Avatar initials="GA" size={26} /><div className="min-w-0 text-[12.5px]"><div className="text-[11.5px] text-cnc-mute"><span className="font-semibold text-cnc-ink">Grok agent · {r.agent_key}</span> · {dt(r.started_at)} · model {r.model} · prompt {r.prompt_version}{r.error ? " · error" : ""}</div><div>Agent run logged with input reference {r.input_ref}, {r.tokens_in ?? 0} tokens in, {r.tokens_out ?? 0} out. Reversible until {dt(r.reversible_until)}.</div></div></div>)}
            {(comments ?? []).map((c: any) => <div key={c.id} className="flex gap-3 border-t border-cnc-greyLight py-2.5"><Avatar initials={c.author?.initials ?? "??"} size={26} /><div className="text-[12.5px]"><div className="text-[11.5px] text-cnc-mute"><span className="font-semibold text-cnc-ink">{c.author?.full_name}</span> · {dt(c.created_at)}</div>{c.body}</div></div>)}
            <form action={comment} className="mt-3 flex gap-2.5"><input type="hidden" name="task_id" value={t.id} /><Avatar initials={person.initials} /><input name="body" required placeholder="Write a comment or mention a colleague" className="h-10 flex-1 rounded-sm border border-cnc-line px-3 text-[12.5px] outline-none" /><Btn kind="sec" type="submit">Post</Btn></form>
          </Card>
        </div>
        <Card className="w-[320px] shrink-0 self-start">
          <Prop l="Status"><Pill status={t.status} /></Prop>
          <Prop l="Priority"><span className={`inline-flex items-center gap-1.5 font-semibold ${t.priority === "high" ? "text-cnc-redDark" : ""}`}>{t.priority === "high" && <Icon name="alert" size={14} />}{t.priority}</span></Prop>
          <Prop l="Assigned to">{t.assignee ? <><Avatar initials={t.assignee.initials} size={24} />{t.assignee.full_name}</> : <span className="text-cnc-mute">Unallocated</span>}</Prop>
          <Prop l="Signs for">{t.signer ? <><Avatar initials={t.signer.initials} size={24} />{t.signer.full_name}</> : <span className="text-cnc-mute">—</span>}</Prop>
          <Prop l="Due date"><Icon name="calendar" size={14} className="text-cnc-mute" />{d(t.due_date)}</Prop>
          <Prop l="Client">{t.client ? <Link href={`/clients/${t.client.id}`}>{t.client.name}</Link> : "—"}</Prop>
          <Prop l="Journey stage">{t.stage && <StageChip stage={t.stage} on />}</Prop>
          <Prop l="Task type">{t.task_type ?? "—"}</Prop>
          {t.template && <Prop l="Template">{t.template.name} v{t.template.version}</Prop>}
          <Prop l="Depends on"><span className="text-[12px]">{(deps ?? []).filter((dp) => dp.successor_id === id).length} predecessors · blocks {(deps ?? []).filter((dp) => dp.predecessor_id === id).length}</span></Prop>
          <Prop l="Time logged"><Icon name="clock" size={14} className="text-cnc-mute" />{Math.floor(minutes / 60)}h {minutes % 60}m</Prop>
          <Prop l="Source"><SourceBadge source={t.source} /><span className="text-[12px] text-cnc-mute">{t.source_ref}</span></Prop>
          {t.client_source && <Prop l="Client source">{t.client_source}</Prop>}
          <div className="my-2.5 border-t border-cnc-greyLight" />
          <div className="mb-1.5 text-[12px] font-semibold text-cnc-mute">Rights on this task</div>
          <div className="flex flex-col gap-1.5 text-[12px]"><div className="flex items-center gap-2"><Icon name="check" size={13} className="text-cnc-green" />Assignee edits subtasks and logs activity</div><div className="flex items-center gap-2"><Icon name="check" size={13} className="text-cnc-green" />Signer reassigns, signs and closes</div><div className="flex items-center gap-2"><Icon name="lock" size={13} className="text-cnc-mute" />Grok proposes, never sends without a signature</div></div>
        </Card>
      </div>
    </Shell>
  );
}
