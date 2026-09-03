/**
 * mco-sync · Phase 1
 * Reads new rows in mco_task (landed by the MyClinicOnline sync), applies rules R-01 to R-08, creates parent tasks,
 * asks the Booking or Documentation agent for subtasks, allocates or holds for a signature, and predicts SLA breaches.
 * Runs every 15 minutes from pg_cron. mode=sla runs only the breach prediction.
 */
import { serviceClient, TENANT_ID, audit, deadLetter, markSync, json } from "../_shared/supabase.ts";
import { scrubMcoDescription } from "../_shared/popia.ts";
import { stageForMcoType, priorityForMcoType, largestGap, rank, breachProbability, Load } from "../_shared/rules.ts";
import { grokJson } from "../_shared/grok.ts";

interface ProposedSubtask { title: string; stage: string; offset_days: number; duration_days: number; role: string; depends_on: number | null; requires_signature: boolean; draft_email?: string | null; }

Deno.serve(async (req) => {
  const db = serviceClient();
  const body = await req.json().catch(() => ({}));
  if (body.mode === "sla") return json(await predictSla(db));

  const { data: rows, error } = await db.from("mco_task").select("*").is("processed_at", null).limit(50);
  if (error) return json({ error: error.message }, 500);
  const results: unknown[] = [];
  for (const row of rows ?? []) {
    try { results.push(await processRow(db, row)); }
    catch (e) { await deadLetter(db, "mco-sync", row, e); results.push({ mco_id: row.mco_id, error: String(e) }); }
  }
  await db.rpc("mark_overdue");
  await markSync(db, "mco", true, { processed: results.length });
  return json({ processed: results.length, results });
});

async function processRow(db: ReturnType<typeof serviceClient>, row: any) {
  const { data: rules } = await db.from("rule").select("*").eq("tenant_id", TENANT_ID).eq("enabled", true);
  const ruleBy = (ref: string) => rules?.find((r: any) => r.ref === ref);
  const r01 = ruleBy("R-01");
  if (!r01) return { mco_id: row.mco_id, outcome: "R-01 disabled" };

  // R-01 · parent task on the mapped journey stage
  const { data: client } = await db.from("client").select("id, account_owner_id, oversight_id, name").ilike("name", row.client_name ?? "").maybeSingle();
  const stage = stageForMcoType(row.task_type);
  const title = scrubMcoDescription(row.description ?? row.task_type, row.medical_count);
  const { data: parent } = await db.from("task").insert({
    tenant_id: TENANT_ID, client_id: client?.id ?? null, title, task_type: row.task_type, stage,
    priority: priorityForMcoType(row.task_type), source: "mco", source_ref: row.mco_id, due_date: row.due_date,
    medical_count: row.medical_count, assignee_id: null, signer_id: client?.oversight_id ?? null, created_by: null,
  }).select("id, ref").single();
  await fire(db, r01, row.mco_id, "created", { task: parent!.ref });

  // R-02 / R-03 / R-04 / R-05 · allocation and drafting by type
  const typeRule = rules?.find((r: any) => r.trigger === `mco_type:${row.task_type}`) ?? (row.task_type.startsWith("Medicals: ") ? ruleBy("R-05") : null);
  let outcome = "created";
  if (typeRule) {
    const owner = client?.account_owner_id ?? null;
    const overThreshold = typeRule.threshold_medicals && (row.medical_count ?? 0) > typeRule.threshold_medicals;
    // subtasks drafted by the agent, in draft state until accepted
    const subtasks = await draftSubtasks(db, typeRule.agent_key, row, parent!.id, stage);
    if (overThreshold) {
      await db.from("approval").insert({
        tenant_id: TENANT_ID, kind: "threshold", task_id: parent!.id, requested_by_agent: typeRule.agent_key, approver_id: client?.oversight_id,
        title: `Threshold exceeded: ${row.medical_count} medicals · ${client?.name ?? row.client_name}`,
        detail: `Above the ${typeRule.threshold_medicals} medical limit in rule ${typeRule.ref} [CONFIRM]. Allocation is on hold until a Sales Manager confirms.`,
        payload: { proposed_assignee: owner, subtasks },
        options: [{ key: "confirm", label: "Confirm allocation" }, { key: "split", label: "Split across two consultants" }],
      });
      outcome = "held_for_signature";
    } else if (owner) {
      const proposeOnly = await overCapacity(db, owner);
      if (proposeOnly) {
        const { data: loads } = await db.from("v_person_load").select("*");
        const alt = largestGap((loads ?? []).filter((l: Load) => l.person_id !== owner));
        await db.from("approval").insert({
          tenant_id: TENANT_ID, kind: "allocation", task_id: parent!.id, requested_by_agent: "allocation", approver_id: client?.oversight_id,
          title: `Approve allocation: ${row.medical_count ?? ""} ${row.task_type} · ${client?.name}`,
          detail: `Account owner is above capacity. Rule R-07 suggests ${alt?.full_name ?? "the consultant with the largest gap"}.`,
          payload: { proposed_assignee: owner, alternative_assignee: alt?.person_id ?? null, subtasks },
          options: [{ key: "owner", label: "Approve account owner" }, { key: "alternative", label: `Assign ${alt?.full_name ?? "alternative"}` }],
        });
        await fire(db, ruleBy("R-07"), row.mco_id, "held_for_signature", {});
        outcome = "held_for_signature";
      } else {
        await db.from("task").update({ assignee_id: owner, status: "new" }).eq("id", parent!.id);
        await db.from("task").update({ assignee_id: owner }).eq("parent_id", parent!.id).is("assignee_id", null);
        outcome = "allocated";
      }
    }
    await fire(db, typeRule, row.mco_id, outcome, { subtasks: subtasks.length });
  }
  // R-08 · renewal ladder from the expiry window
  if (row.window_to && client?.id) {
    const { data: tpl } = await db.from("template").select("id").eq("key", "renewal_ladder").order("version", { ascending: false }).limit(1).maybeSingle();
    if (tpl) await db.from("recurrence_rule").insert({ tenant_id: TENANT_ID, client_id: client.id, template_id: tpl.id, anchor_date: row.window_to });
  }
  // ranking
  const rk = rank({ dueDate: row.due_date, dependents: 0, priority: priorityForMcoType(row.task_type), slaProbability: null });
  await db.from("task").update({ rank_score: rk.score, rank_reason: rk.reason }).eq("id", parent!.id);
  await db.from("mco_task").update({ processed_at: new Date().toISOString(), portal_task_id: parent!.id }).eq("id", row.id);
  await audit(db, "mco.task_ingested", "task", parent!.id, { mco_id: row.mco_id, outcome });
  return { mco_id: row.mco_id, task: parent!.ref, outcome };
}

async function draftSubtasks(db: any, agentKey: string | null, row: any, parentId: string, stage: string): Promise<ProposedSubtask[]> {
  if (!agentKey) return [];
  const { data: agent } = await db.from("agent").select("*").eq("key", agentKey).single();
  const prompt = `MyClinicOnline task.\nType: ${row.task_type}\nClient: ${row.client_name}\nCount: ${row.medical_count ?? "n/a"}\nWindow: ${row.window_from ?? ""} to ${row.window_to ?? ""}\nDue: ${row.due_date}\nJourney stage: ${stage}\nPropose 3 to 6 subtasks along the client journey (schedule, clinic_day, certificates, invoice, renewal). Each is one tick. Mark requires_signature true for anything that sends a client an email; include draft_email with counts and dates only.`;
  const schema = `{"subtasks":[{"title":string,"stage":string,"offset_days":number,"duration_days":number,"role":"sales_consultant"|"sales_manager","depends_on":number|null,"requires_signature":boolean,"draft_email":string|null}]}`;
  let proposed: ProposedSubtask[] = [];
  try {
    const out = await grokJson<{ subtasks: ProposedSubtask[] }>(db, agentKey, agent?.prompt_version ?? "v1", row.mco_id, prompt, schema, agent?.model ?? undefined);
    proposed = out.data.subtasks ?? [];
  } catch (e) {
    // No key or a model error: fall back to the template so the flow still works, and log it.
    await deadLetter(db, "mco-sync.draftSubtasks", { mco_id: row.mco_id }, e);
    const { data: tpl } = await db.from("template").select("id, template_item(*)").eq("key", row.task_type === "Non Arrival" ? "non_arrival_recovery" : "renewal_ladder").order("version", { ascending: false }).limit(1).maybeSingle();
    proposed = (tpl?.template_item ?? []).sort((a: any, b: any) => a.position - b.position).map((i: any) => ({ title: i.title, stage: i.stage, offset_days: i.offset_days, duration_days: i.duration_days, role: i.default_role, depends_on: i.depends_on_position, requires_signature: i.requires_signature, draft_email: null }));
  }
  const base = new Date(row.window_to ?? row.due_date ?? Date.now());
  const ids: string[] = [];
  for (const [i, s] of proposed.entries()) {
    const start = new Date(base); start.setDate(start.getDate() + (s.offset_days ?? 0));
    const due = new Date(start); due.setDate(due.getDate() + Math.max(1, s.duration_days ?? 1) - 1);
    const { data: t } = await db.from("task").insert({
      tenant_id: TENANT_ID, parent_id: parentId, client_id: null, title: s.title, stage: s.stage, task_type: row.task_type, source: "grok", source_ref: row.mco_id,
      status: s.requires_signature ? "awaiting_approval" : "new", start_date: start.toISOString().slice(0, 10), due_date: due.toISOString().slice(0, 10), drafted_by_agent: true,
    }).select("id").single();
    ids.push(t!.id);
    if (s.depends_on && ids[s.depends_on - 1]) await db.from("task_dependency").insert({ predecessor_id: ids[s.depends_on - 1], successor_id: t!.id });
    if (s.requires_signature && s.draft_email) {
      await db.from("approval").insert({ tenant_id: TENANT_ID, kind: "outbound_email", task_id: t!.id, requested_by_agent: agentKey, title: `Sign outbound email: ${s.title}`, detail: "Counts and dates only, no employee names. Rule R-06 hold.", payload: { draft_email: s.draft_email } });
    }
  }
  // fix client_id on subtasks from parent
  const { data: p } = await db.from("task").select("client_id").eq("id", parentId).single();
  await db.from("task").update({ client_id: p?.client_id }).eq("parent_id", parentId);
  return proposed;
}

async function overCapacity(db: any, personId: string): Promise<boolean> {
  const { data } = await db.from("v_person_load").select("*").eq("person_id", personId).maybeSingle();
  return !!data && data.open_parents >= data.capacity_open_parents;
}

async function fire(db: any, rule: any, ref: string, outcome: string, detail: Record<string, unknown>) {
  if (!rule) return;
  await db.from("rule_run").insert({ rule_id: rule.id, trigger_ref: ref, outcome, detail });
  await db.from("rule").update({ last_fired_at: new Date().toISOString(), runs_30d: (rule.runs_30d ?? 0) + 1 }).eq("id", rule.id);
}

async function predictSla(db: any) {
  const { data: policies } = await db.from("sla_policy").select("*").eq("tenant_id", TENANT_ID);
  const { data: open } = await db.from("task").select("id, task_type, created_at, due_date, assignee_id").is("parent_id", null).in("status", ["new", "in_progress", "overdue"]);
  let updated = 0;
  for (const t of open ?? []) {
    const pol = policies?.find((p: any) => p.task_type === t.task_type);
    if (!pol) continue;
    const dueAt = new Date(new Date(t.created_at).getTime() + pol.hours_to_resolve * 3_600_000);
    const hoursRemaining = (dueAt.getTime() - Date.now()) / 3_600_000;
    const ahead = (open ?? []).filter((o: any) => o.assignee_id === t.assignee_id && o.id !== t.id).length;
    const p = breachProbability(hoursRemaining, pol.hours_to_resolve * 0.6, ahead);
    await db.from("task").update({ sla_breach_probability: p, sla_due_at: dueAt.toISOString() }).eq("id", t.id);
    if (p >= 0.6) {
      const { data: existing } = await db.from("approval").select("id").eq("task_id", t.id).eq("kind", "threshold").eq("state", "pending").ilike("title", "SLA at risk%").maybeSingle();
      if (!existing) await db.from("approval").insert({ tenant_id: TENANT_ID, kind: "threshold", task_id: t.id, requested_by_agent: "follow_up", approver_id: t.assignee_id, title: `SLA at risk: predicted to breach`, detail: `Breach probability ${Math.round(p * 100)}% from queue depth and history. Move the call to today or draft the recovery offer now.`, options: [{ key: "move_today", label: "Move to today" }, { key: "dismiss", label: "Dismiss" }] });
    }
    updated++;
  }
  return { updated };
}
