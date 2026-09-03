import Link from "next/link";
import Image from "next/image";
import type { ReactNode } from "react";
import { Avatar, ConfirmTag, Icon } from "./ui";
import { ROLE_LABEL } from "@/lib/format";
import type { Person } from "@/lib/types";

const NAV = [
  { href: "/desk", icon: "desk", label: "Desk" },
  { href: "/work", icon: "home", label: "My work" },
  { href: "/inbox", icon: "inbox", label: "Inbox" },
  { href: "/board", icon: "board", label: "Team board" },
  { href: "/clients", icon: "building", label: "Clients" },
  { href: "/automations", icon: "zap", label: "Sales automations" },
  { href: "/permissions", icon: "shield", label: "Roles and permissions" },
];

export function Shell({ person, active, crumbs, inboxCount = 0, children }: { person: Person; active: string; crumbs: string[]; inboxCount?: number; children: ReactNode }) {
  return (
    <div className="flex min-h-screen bg-cnc-panel">
      <aside className="flex w-[216px] shrink-0 flex-col border-r border-cnc-line bg-white">
        <div className="flex flex-col gap-2.5 px-5 pb-3.5 pt-[18px]">
          <Image src="/cnc-logo-trim.png" alt="Care Net Consultants" width={66} height={44} priority />
          <div><div className="font-heading text-[16px] font-semibold text-cnc-red">Care Net Consultants</div><div className="mt-0.5 text-[12px] text-cnc-mute">Sales Executive desk</div></div>
        </div>
        <nav className="flex flex-col gap-0.5 px-3">
          {NAV.map((n) => {
            const on = n.href === active;
            return (
              <Link key={n.href} href={n.href} className={`flex h-10 items-center gap-2.5 rounded-sm px-3 text-[13px] font-semibold ${on ? "bg-cnc-redSoft text-cnc-redDark" : "text-cnc-ink hover:bg-cnc-greyLight"}`}>
                <Icon name={n.icon} className={on ? "text-cnc-redDark" : "text-cnc-mute"} />{n.label}
                {n.label === "Inbox" && inboxCount > 0 && <span className="ml-auto inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-full bg-cnc-red px-1.5 text-[10px] font-bold text-white">{inboxCount}</span>}
              </Link>
            );
          })}
        </nav>
        <div className="px-5 pb-2 pt-[18px] text-[10.5px] font-bold uppercase tracking-[.08em] text-cnc-mute">Modules</div>
        <div className="flex flex-col gap-0.5 px-3 text-[12.5px]">
          <div className="flex h-[34px] items-center gap-2.5 px-3"><span className="h-2 w-2 rounded-full bg-cnc-red" />Sales<span className="ml-auto text-[10.5px] font-semibold text-cnc-green">live</span></div>
          {["Clinic operations", "Finance", "HR and compliance"].map((m) => <div key={m} className="flex h-[34px] items-center gap-2.5 px-3 text-cnc-mute"><span className="h-2 w-2 rounded-full border border-[#BDBDBD]" />{m}<span className="ml-auto text-[10.5px]">next</span></div>)}
        </div>
        <div className="mt-auto flex items-center gap-2.5 border-t border-cnc-line px-5 py-3.5">
          <Avatar initials={person.initials} name={person.full_name} />
          <div className="min-w-0"><div className="text-[12.5px] font-semibold">{person.full_name}</div><div className="text-[11px] text-cnc-mute">{ROLE_LABEL[person.role] ?? person.role}</div></div>
          <form action="/auth/signout" method="post" className="ml-auto"><button className="text-cnc-mute" title="Sign out"><Icon name="settings" size={16} /></button></form>
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-16 shrink-0 items-center gap-3 border-b border-cnc-line bg-white px-6">
          <div className="flex items-center gap-1.5">
            {crumbs.map((c, i) => <span key={i} className="flex items-center gap-1.5"><span className={`text-[13px] ${i === crumbs.length - 1 ? "font-semibold text-cnc-ink" : "text-cnc-mute"}`}>{c}</span>{i < crumbs.length - 1 && <Icon name="chevright" size={14} className="text-[#BDBDBD]" />}</span>)}
          </div>
          {process.env.NEXT_PUBLIC_DEMO_DATA === "true" && <ConfirmTag>Demo data, mock fixtures</ConfirmTag>}
          <form action="/work" method="get" className="ml-auto flex items-center gap-3">
            <label className="flex h-10 w-[380px] items-center gap-2 rounded-sm border border-cnc-line bg-white px-3 text-[12.5px] text-cnc-mute">
              <Icon name="plus" size={16} className="text-cnc-redDark" />
              <input name="quick" placeholder="Quick add, for example call Thabo Friday 9am" className="w-full bg-transparent text-cnc-ink outline-none placeholder:text-cnc-mute" />
              <kbd className="rounded border border-cnc-line px-1.5 text-[10.5px]">Q</kbd>
            </label>
            <Link href="/inbox" className="relative inline-flex h-10 w-10 items-center justify-center rounded-sm border border-cnc-line"><Icon name="bell" />{inboxCount > 0 && <span className="absolute right-2 top-2 h-2 w-2 rounded-full border-2 border-white bg-cnc-red" />}</Link>
            <Avatar initials={person.initials} name={person.full_name} size={36} />
          </form>
        </header>
        <main className="flex flex-1 flex-col gap-4 p-6">{children}</main>
        <footer className="flex shrink-0 items-center justify-center gap-2.5 border-t border-cnc-line bg-white px-6 py-2.5 text-[11.5px] text-cnc-mute">
          <span>Care Net Consultants (Pty) Ltd · Sales tasks module · data stays in the portal and MyClinicOnline</span>
          <span className="inline-flex items-center gap-1.5 rounded-full border border-cnc-line px-2.5 py-0.5">A proudly AutoHive built application <ConfirmTag>CONFIRM attribution</ConfirmTag></span>
        </footer>
      </div>
    </div>
  );
}
