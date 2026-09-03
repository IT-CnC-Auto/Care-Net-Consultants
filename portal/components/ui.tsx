import Link from "next/link";
import type { ReactNode } from "react";

const ICONS: Record<string, string> = {
  home: '<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6h-4v6H4a1 1 0 0 1-1-1z"/>',
  inbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  board: '<path d="M3 4h5v16H3z"/><path d="M10 4h5v10h-5z"/><path d="M17 4h4v7h-4z"/>',
  users: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  building: '<path d="M3 21h18"/><path d="M5 21V5a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v16"/><path d="M15 9h3a1 1 0 0 1 1 1v11"/><path d="M8 8h2M8 12h2M8 16h2"/>',
  bot: '<path d="M12 2v3"/><rect x="5" y="5" width="14" height="14" rx="3"/><path d="M9 12h.01M15 12h.01M9 16h6M2 11v4M22 11v4"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
  bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  chevright: '<path d="m9 6 6 6-6 6"/>',
  calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  alert: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
  sparkle: '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M19 17l.8 2.2L22 20l-2.2.8L19 23l-.8-2.2L16 20l2.2-.8z"/>',
  lock: '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  external: '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><path d="M15 3h6v6"/><path d="M10 14 21 3"/>',
  zap: '<path d="M13 2 3 14h9l-1 8 10-12h-9z"/>',
  desk: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  db: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.7 4 3 9 3s9-1.3 9-3V5"/><path d="M3 12c0 1.7 4 3 9 3s9-1.3 9-3"/>',
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
  mail: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m2 7 10 7 10-7"/>',
  message: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  layers: '<path d="m12 2 10 5-10 5L2 7z"/><path d="m2 12 10 5 10-5"/><path d="m2 17 10 5 10-5"/>',
};

export function Icon({ name, size = 18, className = "" }: { name: string; size?: number; className?: string }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" className={className} dangerouslySetInnerHTML={{ __html: ICONS[name] ?? "" }} />;
}

const PILL: Record<string, { cls: string; label: string }> = {
  new: { cls: "bg-cnc-yellowTint text-cnc-warn", label: "New" },
  in_progress: { cls: "bg-cnc-blueTint text-cnc-blue", label: "In progress" },
  completed: { cls: "bg-cnc-greenTint text-cnc-green", label: "Completed" },
  overdue: { cls: "bg-cnc-redTint text-cnc-redDark", label: "Overdue" },
  awaiting_approval: { cls: "bg-white text-cnc-ink border border-cnc-ink", label: "Awaiting approval" },
  on_hold: { cls: "bg-cnc-greyLight text-cnc-mute", label: "On hold" },
  active: { cls: "bg-cnc-greenTint text-cnc-green", label: "Active" },
  ok: { cls: "bg-cnc-greenTint text-cnc-green", label: "OK" },
  failed: { cls: "bg-cnc-redTint text-cnc-redDark", label: "Failed" },
  paused: { cls: "bg-cnc-greyLight text-cnc-mute", label: "Paused" },
  pending: { cls: "bg-white text-cnc-ink border border-cnc-ink", label: "Pending" },
  approved: { cls: "bg-cnc-greenTint text-cnc-green", label: "Approved" },
  rejected: { cls: "bg-cnc-greyLight text-cnc-mute", label: "Rejected" },
};
export function Pill({ status, text }: { status: string; text?: string }) {
  const p = PILL[status] ?? { cls: "bg-cnc-greyLight text-cnc-mute", label: status };
  return <span className={`inline-flex h-[22px] items-center whitespace-nowrap rounded-full px-[9px] text-[11.5px] font-semibold ${p.cls}`}>{text ?? p.label}</span>;
}

const SRC: Record<string, { cls: string; label: string }> = {
  mco: { cls: "bg-cnc-blueTint text-cnc-blue", label: "MCO" },
  grok: { cls: "bg-cnc-redTint text-cnc-redDark", label: "Grok" },
  manual: { cls: "bg-cnc-greyLight text-cnc-mute", label: "Manual" },
  crm: { cls: "bg-[#EEE8F4] text-[#5C367D]", label: "AutoHive CRM" },
  capture: { cls: "bg-cnc-redTint text-cnc-redDark", label: "Captured" },
};
export function SourceBadge({ source }: { source: string }) {
  const s = SRC[source] ?? SRC.manual;
  return <span className={`inline-flex h-5 items-center whitespace-nowrap rounded-sm px-[7px] text-[10.5px] font-bold tracking-wide ${s.cls}`}>{s.label}</span>;
}

export function StageChip({ stage, on = false, done = false }: { stage: string; on?: boolean; done?: boolean }) {
  const label = ({ prospect: "Prospect", quote: "Quote", onboard: "Onboard", schedule: "Schedule", clinic_day: "Clinic day", certificates: "Certificates", invoice: "Invoice", renewal: "Renewal" } as Record<string, string>)[stage] ?? stage;
  const cls = on ? "bg-cnc-red text-white border-cnc-red" : done ? "bg-cnc-greyLight text-cnc-ink border-cnc-line" : "bg-white text-cnc-mute border-dashed border-[#CFCFCF]";
  return <span className={`inline-flex h-[22px] items-center whitespace-nowrap rounded-sm border px-[9px] text-[11px] font-semibold ${cls}`}>{label}</span>;
}

const AV_COLOURS = ["#33578C", "#5C367D", "#007749", "#B35A1E", "#0F6E6A", "#1E1E1E"];
export function Avatar({ initials, name, size = 28 }: { initials: string; name?: string; size?: number }) {
  const colour = initials === "GA" ? "#ED1B24" : AV_COLOURS[(initials.charCodeAt(0) + (initials.charCodeAt(1) || 0)) % AV_COLOURS.length];
  return <span title={name} style={{ width: size, height: size, background: colour, fontSize: size >= 28 ? 11 : 9 }} className="inline-flex shrink-0 items-center justify-center rounded-full font-heading font-semibold text-white">{initials}</span>;
}

export function StatCard({ label, value, detail, tone }: { label: string; value: ReactNode; detail?: string; tone?: "warning" | "success" | "danger" }) {
  const v = tone === "danger" ? "text-cnc-redDark" : tone === "success" ? "text-cnc-green" : tone === "warning" ? "text-cnc-warn" : "text-cnc-ink";
  return (
    <div className="flex h-[104px] min-w-0 flex-1 flex-col justify-center gap-0.5 rounded-md border border-cnc-line bg-white px-[18px] shadow-card">
      <div className="text-[12px] font-semibold text-cnc-mute">{label}</div>
      <div className={`font-heading text-[26px] font-semibold leading-tight ${v}`}>{value}</div>
      {detail && <div className="truncate text-[12px] text-cnc-mute">{detail}</div>}
    </div>
  );
}

export function Card({ title, sub, right, children, className = "" }: { title?: string; sub?: string; right?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`rounded-md border border-cnc-line bg-white p-4 shadow-card ${className}`}>
      {(title || right) && (
        <div className="mb-3 flex items-baseline gap-2.5">
          {title && <h2 className="text-[15px] font-semibold text-cnc-red">{title}</h2>}
          {sub && <span className="text-[12px] text-cnc-mute">{sub}</span>}
          {right && <div className="ml-auto">{right}</div>}
        </div>
      )}
      {children}
    </section>
  );
}

export function ConfirmTag({ children = "CONFIRM" }: { children?: ReactNode }) {
  return <span className="inline-flex h-[18px] items-center whitespace-nowrap rounded px-1.5 bg-cnc-yellowTint text-[10px] font-bold tracking-wide text-cnc-warn">{children}</span>;
}

export function Btn({ children, kind = "sec", href, icon, small, type = "button", name, value, formAction }: { children: ReactNode; kind?: "pri" | "sec" | "ghost" | "dark"; href?: string; icon?: string; small?: boolean; type?: "button" | "submit"; name?: string; value?: string; formAction?: (formData: FormData) => void | Promise<void> }) {
  const cls = { pri: "bg-cnc-red text-white border-cnc-red", sec: "bg-white text-cnc-ink border-cnc-line", ghost: "bg-transparent text-cnc-blue border-transparent px-1.5", dark: "bg-cnc-ink text-white border-cnc-ink" }[kind];
  const base = `inline-flex items-center gap-2 rounded-sm border px-3.5 text-[13px] font-semibold ${small ? "h-8" : "h-9"} ${cls}`;
  if (href) return <Link href={href} className={base}>{icon && <Icon name={icon} size={16} />}{children}</Link>;
  return <button type={type} name={name} value={value} formAction={formAction} className={base}>{icon && <Icon name={icon} size={16} />}{children}</button>;
}

export function PageHead({ title, sub, children }: { title: string; sub?: string; children?: ReactNode }) {
  return (
    <div className="flex items-end gap-4">
      <div><h1 className="text-[22px] font-semibold">{title}</h1>{sub && <div className="mt-0.5 text-[13px] text-cnc-mute">{sub}</div>}</div>
      {children && <div className="ml-auto flex gap-2">{children}</div>}
    </div>
  );
}

export function Empty({ title, text, children }: { title: string; text: string; children?: ReactNode }) {
  return (
    <div className="flex min-h-[220px] flex-col items-center justify-center gap-2 rounded-md border border-cnc-line bg-white p-6 text-center shadow-card">
      <span className="inline-flex h-11 w-11 items-center justify-center rounded-md bg-cnc-greyLight"><Icon name="check" size={22} /></span>
      <div className="font-heading text-[15px] font-semibold">{title}</div>
      <p className="max-w-[360px] text-[13px] text-cnc-mute">{text}</p>
      {children}
    </div>
  );
}
