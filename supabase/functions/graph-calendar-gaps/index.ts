/**
 * graph-calendar-gaps · Phase 1
 * Reads today's calendar for the signed in person through Graph, finds gaps in working hours (08:00 to 17:00 Africa/Johannesburg),
 * and proposes focus blocks for their top ranked tasks. Nothing is written to the calendar; the person accepts blocks in the portal.
 * Pinned blocks are never moved.
 */
import { serviceClient, userClient, TENANT_ID, json } from "../_shared/supabase.ts";
import { graph, GraphEvent } from "../_shared/graph.ts";

Deno.serve(async (req) => {
  const me = userClient(req);
  const uid = (await me.auth.getUser()).data.user?.id;
  const { data: person } = await me.from("person").select("id, email").eq("auth_user_id", uid ?? "").maybeSingle();
  if (!person) return json({ error: "not signed in" }, 401);
  const date = new URL(req.url).searchParams.get("date") ?? new Date().toISOString().slice(0, 10);
  const start = `${date}T08:00:00`; const end = `${date}T17:00:00`;
  const cal = await graph<{ value: GraphEvent[] }>(`/users/${encodeURIComponent(person.email)}/calendarView?startDateTime=${start}&endDateTime=${end}&$select=id,subject,start,end,showAs,isAllDay&$orderby=start/dateTime`, { headers: { Prefer: 'outlook.timezone="South Africa Standard Time"' } });
  const busy = (cal.value ?? []).filter((e) => !e.isAllDay && e.showAs !== "free").map((e) => ({ start: e.start.dateTime.slice(11, 16), end: e.end.dateTime.slice(11, 16), subject: e.subject }));
  const gaps = findGaps(busy, "08:00", "17:00", 45);
  const db = serviceClient();
  const { data: tasks } = await db.from("task").select("id, ref, title, rank_reason, pinned").eq("assignee_id", person.id).in("status", ["new", "in_progress", "overdue"]).order("rank_score", { ascending: true }).limit(gaps.length);
  const blocks = gaps.map((g, i) => ({ start: g.start, end: g.end, task: tasks?.[i] ?? null, movable: !(tasks?.[i]?.pinned ?? false) }));
  return json({ date, busy, blocks, tenant: TENANT_ID });
});

export function findGaps(busy: { start: string; end: string }[], dayStart: string, dayEnd: string, minMinutes: number) {
  const toMin = (t: string) => parseInt(t.slice(0, 2)) * 60 + parseInt(t.slice(3, 5));
  const toStr = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
  const sorted = [...busy].sort((a, b) => toMin(a.start) - toMin(b.start));
  const gaps: { start: string; end: string }[] = [];
  let cursor = toMin(dayStart);
  for (const b of sorted) {
    if (toMin(b.start) - cursor >= minMinutes) gaps.push({ start: toStr(cursor), end: toStr(Math.min(toMin(b.start), cursor + 90)) });
    cursor = Math.max(cursor, toMin(b.end));
  }
  if (toMin(dayEnd) - cursor >= minMinutes) gaps.push({ start: toStr(cursor), end: toStr(Math.min(toMin(dayEnd), cursor + 90)) });
  return gaps;
}
