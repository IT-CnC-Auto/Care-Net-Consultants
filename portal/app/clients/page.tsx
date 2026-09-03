import Link from "next/link";
import { Shell } from "@/components/shell";
import { Avatar, PageHead, Pill, StageChip } from "@/components/ui";
import { pageContext } from "@/lib/page";
import { d } from "@/lib/format";

export default async function Clients() {
  const { person, sb, inboxCount } = await pageContext();
  const { data: clients } = await sb.from("client").select("*, owner:person!client_account_owner_id_fkey(full_name, initials)").order("name");
  const { data: open } = await sb.from("task").select("client_id").is("parent_id", null).neq("status", "completed");
  const counts: Record<string, number> = {}; for (const t of open ?? []) if (t.client_id) counts[t.client_id] = (counts[t.client_id] ?? 0) + 1;
  return (
    <Shell person={person} active="/clients" crumbs={["Sales Executive desk", "Clients"]} inboxCount={inboxCount}>
      <PageHead title="Clients" sub="Every client on the journey. Names and roles only, contact details live in AutoHive CRM." />
      <div className="overflow-hidden rounded-md border border-cnc-line bg-white shadow-card">
        <div className="grid h-9 grid-cols-[minmax(0,2fr)_150px_120px_140px_100px_120px] items-center px-4 text-[11px] font-bold uppercase tracking-wider text-cnc-mute"><div>Client</div><div>Journey stage</div><div>Open tasks</div><div>Account owner</div><div>Source</div><div>Renewal</div></div>
        {(clients ?? []).map((c: any) => <Link key={c.id} href={`/clients/${c.id}`} className="grid h-[52px] grid-cols-[minmax(0,2fr)_150px_120px_140px_100px_120px] items-center border-t border-cnc-greyLight px-4 text-[13px] hover:bg-[#FAFAFA]"><div className="min-w-0"><div className="truncate font-semibold">{c.name}</div><div className="truncate text-[11.5px] text-cnc-mute">{c.industry} · {(c.sites ?? []).join(", ")}</div></div><div><StageChip stage={c.current_stage} on /></div><div>{counts[c.id] ?? 0}</div><div className="flex items-center gap-2">{c.owner && <><Avatar initials={c.owner.initials} size={22} /><span className="truncate text-[12px]">{c.owner.full_name.split(" ")[0]}</span></>}</div><div className="text-[12px] text-cnc-mute">{c.client_source}</div><div className="text-[12px]">{d(c.contract_renewal)}</div></Link>)}
      </div>
    </Shell>
  );
}
