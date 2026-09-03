import { Shell } from "@/components/shell";
import { Avatar, Btn, Card, ConfirmTag, Icon, PageHead, Pill } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { dt } from "@/lib/format";
import { toggleRule } from "@/app/actions";

export default async function Automations() {
  const { person, sb, inboxCount } = await pageContext();
  const [{ data: rules }, { data: runs }, { data: templates }, { data: agents }] = await Promise.all([
    sb.from("rule").select("*, owner:person!rule_owner_id_fkey(full_name, initials), agent:agent(name)").order("ref"),
    sb.from("rule_run").select("*, rule:rule(ref)").order("at", { ascending: false }).limit(8),
    sb.from("template").select("*, items:template_item(id)").eq("active", true).order("key"),
    sb.from("agent").select("*"),
  ]);
  const manager = ["franchise_director", "sales_manager"].includes(person.role);
  const Node = ({ icon, title, sub, dark = false }: { icon: string; title: string; sub: React.ReactNode; dark?: boolean }) => <div className={`flex min-w-0 flex-1 items-center gap-3 rounded-md border p-3.5 shadow-card ${dark ? "border-cnc-ink bg-cnc-ink text-white" : "border-cnc-line bg-white"}`}><span className={`inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-sm ${dark ? "bg-[#333]" : "bg-cnc-redTint"} text-cnc-red`}><Icon name={icon} /></span><div className="min-w-0"><div className="font-heading text-[13px] font-semibold">{title}</div><div className={`text-[11.5px] ${dark ? "text-[#D6D6D6]" : "text-cnc-mute"}`}>{sub}</div></div></div>;
  const Arrow = () => <Icon name="chevright" size={18} className="shrink-0 text-[#BDBDBD]" />;
  return (
    <Shell person={person} active="/automations" crumbs={["Sales Executive desk", "Sales automations"]} inboxCount={inboxCount}>
      <PageHead title="Sales automations" sub="Grok agents read MyClinicOnline through Supabase, create and allocate portal tasks, and hand anything sensitive to a named person">
        <Btn kind="sec" href="/connections" icon="db">Data and connections</Btn><Btn kind="sec" icon="refresh" href={`${process.env.NEXT_PUBLIC_FUNCTIONS_URL}/mco-sync`}>Run sync now</Btn>
      </PageHead>
      <div className="flex items-stretch gap-2.5">
        <Node icon="db" title="MyClinicOnline" sub="Medicals Due, Overdue, Admin, Documents, Error Resolution, ID Pending, Non Arrival, General, Other" /><Arrow />
        <Node icon="db" title="Supabase" sub={<>mco_task table · sync every 15 minutes <ConfirmTag /></>} /><Arrow />
        <Node icon="bot" title="Grok agents" sub="Classify · group by client · draft subtasks · propose allocation" dark /><Arrow />
        <Node icon="layers" title="Portal tasks" sub="Parent and subtasks on the client journey, one Task table" /><Arrow />
        <Node icon="users" title="People" sub="Consultant works it · Sales Manager signs · Director audits" />
      </div>
      <div className="flex gap-3">
        <div className="min-w-0 flex-1 overflow-hidden rounded-md border border-cnc-line bg-white shadow-card">
          <div className="flex items-baseline gap-2 px-4 py-3.5"><h2 className="text-[15px] font-semibold text-cnc-red">Allocation and journey rules</h2><span className="text-[12px] text-cnc-mute">{rules?.filter((r) => r.enabled).length} active · every rule has a human owner, a last fired time and a kill switch</span></div>
          <div className="grid grid-cols-[52px_minmax(0,1fr)_minmax(0,2.1fr)_130px_90px_44px] gap-3 px-4 pb-2 text-[11px] font-bold uppercase tracking-wider text-cnc-mute"><span>Rule</span><span>When</span><span>Agent and action</span><span>Owner</span><span>Runs · last</span><span className="text-right">On</span></div>
          {(rules ?? []).map((r: any) => (
            <div key={r.id} className="grid grid-cols-[52px_minmax(0,1fr)_minmax(0,2.1fr)_130px_90px_44px] items-center gap-3 border-t border-cnc-greyLight px-4 py-3">
              <span className="font-heading text-[12px] font-semibold">{r.ref}</span><div className="text-[12.5px] font-semibold">{r.name}</div>
              <div><div className="text-[12.5px]"><strong>{r.agent?.name ?? "Rule"}:</strong> {r.action}</div>{r.guard && <div className="mt-0.5 flex items-center gap-1.5 text-[11px] font-semibold text-cnc-blue"><Icon name="shield" size={12} />{r.guard}</div>}</div>
              <div className="flex items-center gap-1.5 text-[12px]">{r.owner && <><Avatar initials={r.owner.initials} size={22} />{r.owner.full_name.split(" ")[0]}</>}</div>
              <span className="text-[12px] text-cnc-mute">{r.runs_30d}<br />{r.last_fired_at ? dt(r.last_fired_at).slice(0, 5) : "never"}</span>
              <form action={toggleRule} className="flex justify-end"><input type="hidden" name="rule_id" value={r.id} /><input type="hidden" name="enabled" value={r.enabled ? "false" : "true"} /><button disabled={!manager} title={manager ? "Kill switch" : "Only a Sales Manager may change this"} className={`relative inline-block h-5 w-[34px] rounded-full ${r.enabled ? "bg-cnc-green" : "bg-[#BDBDBD]"}`}><span className={`absolute top-0.5 h-4 w-4 rounded-full bg-white ${r.enabled ? "right-0.5" : "left-0.5"}`} /></button></form>
            </div>
          ))}
        </div>
        <div className="flex w-[400px] shrink-0 flex-col gap-3">
          <Card title="Rule runs">{(runs ?? []).map((r: any) => <div key={r.id} className="flex flex-col gap-0.5 border-t border-cnc-greyLight py-2 text-[12px] first:border-t-0"><div className="flex items-center gap-2"><span className="font-semibold">{r.rule?.ref}</span><span className="text-cnc-mute">{dt(r.at)}</span><span className="ml-auto"><Pill status={r.outcome === "error" ? "failed" : "ok"} text={r.outcome.replace(/_/g, " ")} /></span></div><div className="text-cnc-mute">{r.trigger_ref}</div></div>)}{(runs ?? []).length === 0 && <p className="text-[12.5px] text-cnc-mute">No runs yet. The first MCO sync will appear here.</p>}</Card>
          <Card title="Templates" sub="task lineage, one Task table">{(templates ?? []).map((t: any) => <div key={t.id} className="flex items-center gap-2 border-t border-cnc-greyLight py-1.5 text-[12.5px] first:border-t-0"><span className="font-semibold">{t.name}</span><span className="text-cnc-mute">{t.items?.length ?? 0} ticks</span><span className="ml-auto text-[11px] text-cnc-mute">v{t.version}</span></div>)}</Card>
          <Card title="Agents">{(agents ?? []).map((a) => <div key={a.key} className="flex items-center gap-2 border-t border-cnc-greyLight py-1.5 text-[12.5px] first:border-t-0"><span className="font-semibold">{a.name}</span>{a.reads_untrusted_input && <span className="inline-flex items-center gap-1 text-[10.5px] font-bold text-cnc-blue"><Icon name="shield" size={11} />untrusted input</span>}<span className="ml-auto text-[11px] text-cnc-mute">writes {a.report_table} · {a.prompt_version}</span></div>)}</Card>
        </div>
      </div>
    </Shell>
  );
}
