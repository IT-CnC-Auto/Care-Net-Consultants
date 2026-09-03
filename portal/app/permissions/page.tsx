import { Shell } from "@/components/shell";
import { Avatar, Btn, Card, Icon, PageHead } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { ROLE_LABEL } from "@/lib/format";

const ROLES = ["franchise_director", "sales_manager", "sales_consultant", "information_officer", "agent"];
const RIGHTS: [string, number[]][] = [
  ["View own tasks", [1, 1, 1, 0, 1]], ["View team tasks", [1, 1, 0, 0, 1]], ["View all modules", [1, 0, 0, 0, 0]], ["Create and edit tasks", [1, 1, 1, 0, 2]], ["Reassign within team", [1, 1, 0, 0, 2]],
  ["Sign agent allocation", [1, 1, 0, 0, 0]], ["Sign outbound client email", [1, 1, 1, 0, 0]], ["Edit automation rules and kill switch", [1, 1, 0, 0, 0]], ["View client financials and invoices", [1, 1, 0, 0, 0]],
  ["Export Excel reports (logged to audit)", [1, 1, 1, 0, 0]], ["View employee medical outcomes", [0, 0, 0, 0, 0]], ["POPIA data subject requests", [1, 0, 0, 1, 0]], ["Access audit log", [1, 1, 0, 1, 0]],
];

export default async function Permissions() {
  const { person, sb, inboxCount } = await pageContext();
  const { data: people } = await sb.from("person").select("*").order("full_name");
  const { data: loads } = await sb.from("v_person_load").select("*");
  const load = new Map((loads ?? []).map((l: any) => [l.person_id, l]));
  const kids = (id: string | null) => (people ?? []).filter((p) => p.manager_id === id);
  const Node = ({ p, depth }: { p: any; depth: number }) => { const l: any = load.get(p.id); return (
    <div className="flex flex-col gap-1.5" style={{ marginLeft: depth * 28 }}>
      <div className="flex items-center gap-2.5 rounded-sm border border-cnc-line bg-white px-3 py-2">{depth > 0 && <span className="-ml-[22px] -mt-2.5 h-3.5 w-3.5 shrink-0 rounded-bl border-b border-l border-[#CFCFCF]" />}<Avatar initials={p.initials} /><div className="min-w-0"><div className="text-[12.5px] font-semibold">{p.full_name}</div><div className="text-[11px] text-cnc-mute">{ROLE_LABEL[p.role]}{p.is_service_account ? " · service account" : ""}</div></div><span className="ml-auto text-[11.5px]">{p.is_service_account ? "proposes only" : `${l?.open_parents ?? 0} open`}</span></div>
      {kids(p.id).map((k) => <Node key={k.id} p={k} depth={depth + 1} />)}
    </div>); };
  const Cell = ({ v }: { v: number }) => v === 1 ? <span className="inline-flex h-6 w-6 items-center justify-center rounded-sm bg-cnc-greenTint text-cnc-green"><Icon name="check" size={14} /></span> : v === 2 ? <span className="inline-flex h-[22px] items-center rounded-sm bg-cnc-redTint px-2 text-[10.5px] font-bold text-cnc-redDark">propose</span> : <span className="inline-flex h-6 w-6 items-center justify-center rounded-sm bg-cnc-greyLight text-[#BDBDBD]"><Icon name="x" size={12} /></span>;
  return (
    <Shell person={person} active="/permissions" crumbs={["Sales Executive desk", "Roles and permissions"]} inboxCount={inboxCount}>
      <PageHead title="Roles and permissions" sub="Parent and child structure per employee · management oversight through role rights · agents are a role with the fewest rights"><Btn kind="sec" icon="file" href="/connections">Audit log</Btn>{person.role === "franchise_director" && <Btn kind="pri" icon="plus" href="#">Invite person</Btn>}</PageHead>
      <div className="flex gap-3">
        <div className="flex w-[420px] shrink-0 flex-col gap-3">
          <Card title="Sales module" sub="who oversees whom"><div className="flex flex-col gap-1.5">{kids(null).map((p) => <Node key={p.id} p={p} depth={0} />)}</div></Card>
          <Card title="How rights flow"><p className="text-[12.5px]">A person sees their own tasks plus everything owned by people below them in the tree. Signing rights sit one level above the doer. The Franchise Director sees everything, and every action is written to the audit log. Row Level Security in Supabase enforces this, not the portal.</p></Card>
        </div>
        <div className="min-w-0 flex-1 overflow-hidden rounded-md border border-cnc-line bg-white shadow-card">
          <div className="flex items-baseline gap-2 px-4 py-3.5"><h2 className="text-[15px] font-semibold text-cnc-red">Role rights</h2><span className="text-[12px] text-cnc-mute">a person inherits the role of their position in the tree</span></div>
          <div className="grid grid-cols-[minmax(0,1.6fr)_repeat(5,minmax(0,1fr))] gap-2 border-y border-cnc-line bg-[#FAFAFA] px-4 py-2 text-[11px] font-bold uppercase tracking-wider text-cnc-mute"><span>Right</span>{ROLES.map((r) => <span key={r} className="text-center">{ROLE_LABEL[r]}</span>)}</div>
          {RIGHTS.map(([r, v]) => <div key={r} className="grid grid-cols-[minmax(0,1.6fr)_repeat(5,minmax(0,1fr))] items-center gap-2 border-t border-cnc-greyLight px-4 py-2 text-[12.5px]"><span>{r}</span>{v.map((x, i) => <span key={i} className="flex justify-center"><Cell v={x} /></span>)}</div>)}
          <div className="border-t border-cnc-greyLight px-4 py-2.5 text-[11.5px] text-cnc-mute">Medical outcomes never enter the sales app. Clinical records stay in MyClinicOnline and certificates are issued by the OMP only (HPCSA).</div>
        </div>
      </div>
    </Shell>
  );
}
