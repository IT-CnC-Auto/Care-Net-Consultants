export type Status = "new" | "in_progress" | "awaiting_approval" | "completed" | "overdue" | "on_hold";
export type Source = "mco" | "grok" | "manual" | "crm" | "capture";
export interface Person { id: string; full_name: string; initials: string; role: string; email: string; language: string; tenant_id: string; }
export interface Task {
  id: string; ref: string; parent_id: string | null; client_id: string | null; title: string; description: string | null; task_type: string | null;
  stage: string | null; status: Status; priority: "low" | "normal" | "high"; source: Source; source_ref: string | null; source_url: string | null;
  assignee_id: string | null; signer_id: string | null; due_date: string | null; start_date: string | null; rank_score: number | null; rank_reason: string | null;
  sla_breach_probability: number | null; medical_count: number | null; drafted_by_agent: boolean; pinned: boolean; client_source: string | null; created_at: string;
  client?: { id: string; name: string } | null; assignee?: { id: string; full_name: string; initials: string } | null;
}
export interface Approval { id: string; kind: string; state: string; task_id: string | null; requested_by_agent: string | null; approver_id: string | null; title: string; detail: string | null; payload: Record<string, unknown>; options: { key: string; label: string }[]; created_at: string; }
