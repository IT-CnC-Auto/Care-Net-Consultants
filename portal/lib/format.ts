/** DD/MM/YYYY, en-ZA, Africa/Johannesburg. */
export function d(date: string | Date | null | undefined): string {
  if (!date) return "";
  const x = typeof date === "string" ? new Date(date) : date;
  return x.toLocaleDateString("en-ZA", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "Africa/Johannesburg" }).replace(/-/g, "/");
}
export function dt(date: string | Date | null | undefined): string {
  if (!date) return "";
  const x = typeof date === "string" ? new Date(date) : date;
  return d(x) + " " + x.toLocaleTimeString("en-ZA", { hour: "2-digit", minute: "2-digit", timeZone: "Africa/Johannesburg" });
}
export function zar(n: number): string { return "R" + n.toLocaleString("en-ZA", { maximumFractionDigits: 0 }).replace(/\s/g, ","); }
export const STAGES = ["prospect", "quote", "onboard", "schedule", "clinic_day", "certificates", "invoice", "renewal"] as const;
export const STAGE_LABEL: Record<string, string> = { prospect: "Prospect", quote: "Quote", onboard: "Onboard", schedule: "Schedule", clinic_day: "Clinic day", certificates: "Certificates", invoice: "Invoice", renewal: "Renewal" };
export const ROLE_LABEL: Record<string, string> = { franchise_director: "Franchise Director", sales_manager: "Sales Manager", sales_consultant: "Sales Consultant", information_officer: "Information Officer", agent: "Grok agent" };
