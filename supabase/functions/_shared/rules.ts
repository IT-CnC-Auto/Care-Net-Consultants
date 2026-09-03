/** Journey stage mapping, allocation and ranking. Pure functions so they can be unit tested without a database. */
export type Stage = "prospect" | "quote" | "onboard" | "schedule" | "clinic_day" | "certificates" | "invoice" | "renewal";

/** Draft mapping from design/README section 5. [CONFIRM] with the Sales Manager before build sign off. */
export function stageForMcoType(taskType: string): Stage {
  const t = taskType.toLowerCase();
  if (t.startsWith("medicals due")) return "renewal";
  if (t.startsWith("medicals overdue")) return "renewal";
  if (t.includes("admin")) return "invoice";
  if (t.includes("id pending") || t.includes("documents") || t.includes("error resolution")) return "certificates";
  if (t.includes("non arrival")) return "clinic_day";
  if (t.includes("christmas")) return "renewal";
  return "onboard";
}

export function priorityForMcoType(taskType: string): "low" | "normal" | "high" {
  const t = taskType.toLowerCase();
  if (t.startsWith("medicals overdue") || t.includes("non arrival")) return "high";
  return "normal";
}

export interface Load { person_id: string; full_name: string; capacity_open_parents: number; open_parents: number; }

/** Allocation rule R-07: standard work to the largest book gap. Returns the person with the most headroom. */
export function largestGap(loads: Load[]): Load | null {
  const ranked = [...loads].sort((a, b) => (b.capacity_open_parents - b.open_parents) - (a.capacity_open_parents - a.open_parents));
  return ranked[0] ?? null;
}

export interface RankInput { dueDate: string | null; dependents: number; priority: string; slaProbability: number | null; }

/** Today ranking with a visible reason. Lower score sorts first. */
export function rank(input: RankInput, today = new Date()): { score: number; reason: string } {
  const reasons: string[] = [];
  let score = 100;
  if (input.dueDate) {
    const days = Math.round((new Date(input.dueDate).getTime() - today.getTime()) / 86_400_000);
    score += days * 2;
    reasons.push(days < 0 ? `overdue by ${-days} days` : days === 0 ? "due today" : `due in ${days} days`);
  }
  if (input.dependents > 0) { score -= input.dependents * 5; reasons.push(`${input.dependents} dependent subtasks`); }
  if (input.priority === "high") { score -= 15; reasons.push("priority high"); }
  if ((input.slaProbability ?? 0) >= 0.5) { score -= 20; reasons.push(`SLA risk ${Math.round((input.slaProbability ?? 0) * 100)}%`); }
  return { score, reason: reasons.join(", ") };
}

/** SLA breach prediction from queue depth and historical resolution time. Simple, explainable, tuned later. */
export function breachProbability(hoursRemaining: number, medianHoursToResolve: number, queueDepthAhead: number): number {
  const expected = medianHoursToResolve * (1 + queueDepthAhead * 0.15);
  if (hoursRemaining <= 0) return 0.98;
  const ratio = expected / hoursRemaining;
  return Math.max(0.02, Math.min(0.97, 1 - Math.exp(-ratio)));
}
