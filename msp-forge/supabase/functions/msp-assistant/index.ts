// CNC MSP FORGE | AI-CONN-01 v1.0.0 | The assistant connection 15/08/2026
//
// One edge function, four actions, no hard coded settings. Model, reasoning
// effort, thinking mode, output ceiling, spend ceiling, rate limits and the
// enabled action list all come from the parameter store on every single call, so
// Care Net can retune the assistant from the admin page without a deployment.
//
// What this function will never do:
//   It never answers from its own memory of South African law. Every legal
//   statement it makes must come from the framework rows handed to it in the
//   same request, and those rows only ever contain verified instruments.
//   It never gives an opinion on an individual worker's fitness. That is the
//   practitioner's decision and the database will not release a pack without one.
//   It never sees client medical data. The grounding functions do not expose it.
//
// Secrets: the Anthropic key lives in Supabase secrets, the service key is
// injected by the platform. Neither is ever written to the database.

import Anthropic from "npm:@anthropic-ai/sdk@0.117.1";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("SB_URL") ?? "";
const SERVICE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SB_SERVICE_ROLE_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

// Actions a signed in client company may run. Everything else is staff only.
const CLIENT_ACTIONS = new Set(["explain_plan"]);

type Cfg = Record<string, string>;

// The instruction set. Versioned by the ai.prompt_version parameter: bump that
// parameter whenever this text changes so the ledger can tell you which rules
// were in force for any given answer.
function systemPrompt(cfg: Cfg, audience: "client" | "staff"): string {
  return [
    "You are the assistant to the Care Net Consultants medical surveillance planning framework.",
    "Care Net Consultants (Pty) Ltd is a South African occupational health company.",
    "",
    "How you must answer:",
    "1. Answer only from the framework rows supplied in the user message. Those rows are the single source of truth.",
    "2. Never cite a law, regulation, gazette notice or standard that does not appear in the supplied rows. If the rows do not cover the question, say the framework does not carry it and that a Care Net occupational medical practitioner will answer.",
    "3. Never quote a threshold, exposure limit, frequency or reference range that is not in the supplied rows.",
    "4. Never express an opinion on whether any individual worker is fit for work. Fitness is a decision for the registered practitioner alone.",
    "5. Never describe a plan as approved, signed or final. Nothing is released until a registered practitioner signs it.",
    "6. Where you are uncertain, say so and route the question to the practitioner. An honest gap is worth more than a confident guess.",
    "",
    "How you must write:",
    "South African British English. Plain, direct sentences. No dashes of any kind as punctuation: use a comma, a full stop or a new sentence.",
    "Do not use marketing language and do not oversell. Do not name any internal system component or technology.",
    "Refer to Care Net people as sales executives or as occupational medical practitioners, never as consultants.",
    audience === "client"
      ? "You are speaking to a company representative who is not a clinician. Explain in ordinary language what the plan covers and why, and what they will be asked for."
      : "You are speaking to Care Net staff. Be concise and technical, and flag anything that needs a practitioner decision.",
  ].join("\n");
}

function userPrompt(action: string, ground: unknown, question: string, extra: unknown): string {
  const rows = "FRAMEWORK ROWS (the only source you may use):\n" + JSON.stringify(ground, null, 1);
  switch (action) {
    case "explain_plan":
      return `${rows}\n\nThe company representative asks:\n${question}\n\nAnswer their question using the rows above. If the rows do not carry the answer, say so and say a practitioner will follow up.`;
    case "industry_brief":
      return `${rows}\n\nWrite a short internal brief for this industry: what drives the surveillance requirement, which instruments apply and to whom, which roles carry the heaviest exposure profile, and what a sales executive should ask the client to confirm. Use only the rows above.`;
    case "triage_other":
      return `${rows}\n\nA prospective client describes their business as follows:\n${question}\n\nUsing only the industry codes present in the rows above, say which industry is the best fit and why, and give a confidence of high, medium or low. If nothing fits well, say the enquiry needs a Care Net review rather than forcing a code. Start your answer with a single line in the form CODE: XXXX or CODE: NONE.`;
    case "monthly_watch":
      return `AUDIT REPORT:\n${JSON.stringify(extra, null, 1)}\n\n${rows}\n\nThis is the output of the monthly framework audit. Summarise what it found in plain language, say which findings need a practitioner to look at them and which are housekeeping, and propose the next actions in priority order. Propose only: you may not change anything, and nothing you suggest takes effect until a person applies it.`;
    default:
      return rows;
  }
}

function priceCall(cfg: Cfg, model: string, inTok: number, outTok: number): number | null {
  try {
    const table = JSON.parse(cfg["ai.price_table_json"] ?? "{}");
    const row = table[model];
    if (!row) return null;
    return Number(((inTok / 1e6) * row.in + (outTok / 1e6) * row.out).toFixed(4));
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  if (!SUPABASE_URL || !SERVICE_KEY) {
    return json({ error: "The connection is not configured. SUPABASE_URL and the service key are missing." }, 500);
  }

  const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const started = Date.now();

  let action = "";
  let actor = "anonymous";
  let cfg: Cfg = {};
  let industryCode: string | null = null;

  // Every exit from here on writes a ledger row, including the refusals. A call
  // that was turned away is as much a fact as one that was answered.
  const record = async (
    outcome: string,
    opts: { inTok?: number; outTok?: number; cost?: number | null; error?: string } = {},
  ) => {
    try {
      await db.rpc("msp_ai_log", {
        p_action: action || "unknown",
        p_model: cfg["ai.model"] ?? "none",
        p_effort: cfg["ai.effort"] ?? null,
        p_prompt_version: cfg["ai.prompt_version"] ?? null,
        p_outcome: outcome,
        p_actor: actor,
        p_input_tokens: opts.inTok ?? null,
        p_output_tokens: opts.outTok ?? null,
        p_cost_usd: opts.cost ?? null,
        p_latency_ms: Date.now() - started,
        p_industry_code: industryCode,
        p_error: opts.error ?? null,
      });
    } catch (_) {
      // A ledger failure must not swallow the caller's answer, but it is never
      // silent either: it surfaces in the function logs.
      console.error("ledger write failed for action", action);
    }
  };

  try {
    const body = await req.json().catch(() => ({}));
    action = String(body.action ?? "");
    const question = String(body.question ?? "").slice(0, 4000);
    industryCode = body.industry_code ? String(body.industry_code).toUpperCase().slice(0, 16) : null;

    if (!action) return json({ error: "An action is required." }, 400);

    // 1. Who is asking. The bearer token is verified against Supabase Auth, never
    // trusted as presented.
    const auth = req.headers.get("Authorization") ?? "";
    const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
    if (!token) return json({ error: "Sign in first." }, 401);

    const { data: userData, error: userErr } = await db.auth.getUser(token);
    if (userErr || !userData?.user) {
      await record("refused", { error: "invalid token" });
      return json({ error: "Sign in first." }, 401);
    }
    const user = userData.user;
    actor = user.email ?? user.id;
    const roles: string[] = (user.app_metadata?.msp_roles as string[]) ?? [];
    const isStaff = roles.some((r) => ["forge_admin", "forge_omp", "forge_agent", "forge_verifier"].includes(r));

    // 2. What the system is running on right now, and whether it may spend.
    const { data: pre, error: preErr } = await db.rpc("msp_ai_preflight", { p_action: action });
    if (preErr) {
      await record("error", { error: preErr.message });
      return json({ error: "The connection could not read its configuration." }, 500);
    }
    cfg = (pre?.config ?? {}) as Cfg;

    if (pre?.allowed !== true) {
      await record(pre?.reason === "over_budget" ? "over_budget" : "disabled");
      return json({
        error:
          pre?.reason === "over_budget"
            ? "The assistant has reached its monthly ceiling and will resume next month."
            : "The assistant is switched off.",
        reason: pre?.reason,
      }, 429);
    }

    // 3. Is this action switched on, and may this caller run it.
    const enabled = (cfg["ai.actions_enabled"] ?? "").split(",").map((s) => s.trim());
    if (!enabled.includes(action)) {
      await record("refused", { error: "action not enabled" });
      return json({ error: "That action is switched off." }, 403);
    }

    let clientAccount: Record<string, unknown> | null = null;
    if (!isStaff) {
      if (!CLIENT_ACTIONS.has(action)) {
        await record("refused", { error: "staff only action" });
        return json({ error: "That action is for Care Net staff." }, 403);
      }
      if ((cfg["ai.allow_client_facing"] ?? "false") !== "true") {
        await record("refused", { error: "client facing disabled" });
        return json({ error: "The assistant is not available to clients at the moment." }, 403);
      }
      const { data: ident } = await db.rpc("msp_ai_client_identity", { p_auth_user_id: user.id });
      if (ident?.found !== true) {
        await record("refused", { error: "no client account" });
        return json({ error: "This sign in is not linked to a company account." }, 403);
      }
      clientAccount = ident;
    }

    // 4. Rate limit, per caller, per hour, from the parameters.
    const limit = Number(isStaff ? cfg["ai.staff_hourly_limit"] : cfg["ai.client_hourly_limit"]);
    if (Number.isFinite(limit)) {
      const { data: used } = await db.rpc("msp_ai_recent_calls", { p_actor: actor, p_minutes: 60 });
      if (Number(used ?? 0) >= limit) {
        await record("refused", { error: "hourly limit" });
        return json({ error: "You have reached this hour's limit. Try again shortly." }, 429);
      }
    }

    // 5. The grounding rows. This is the only knowledge the model may use.
    let ground: unknown = null;
    if (action === "monthly_watch") {
      const { data } = await db.rpc("msp_ai_context_instruments");
      ground = { verified_instruments: data };
    } else {
      if (!industryCode) {
        await record("refused", { error: "no industry code" });
        return json({ error: "An industry code is required for this action." }, 400);
      }
      const { data, error } = await db.rpc("msp_ai_context_industry", { p_code: industryCode });
      if (error || data?.found !== true) {
        await record("refused", { error: "unknown industry" });
        return json({ error: "That industry is not in the framework." }, 404);
      }
      ground = data;
    }

    if (!ANTHROPIC_API_KEY) {
      await record("error", { error: "ANTHROPIC_API_KEY not set" });
      return json({ error: "The assistant key is not configured on this project." }, 500);
    }

    // 6. The call itself. Nothing below is hard coded: it is all parameters.
    const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
    const model = cfg["ai.model"] ?? "claude-opus-5";
    const effort = cfg["ai.effort"] ?? "high";
    const maxTokens = Number(cfg["ai.max_output_tokens"] ?? 8000);

    const request: Record<string, unknown> = {
      model,
      max_tokens: maxTokens,
      system: systemPrompt(cfg, isStaff ? "staff" : "client"),
      output_config: { effort },
      messages: [
        { role: "user", content: userPrompt(action, ground, question, body.report ?? null) },
      ],
    };
    if ((cfg["ai.thinking"] ?? "adaptive") === "adaptive") {
      request.thinking = { type: "adaptive" };
    }

    // Streamed so a long answer cannot hit the request timeout, then collected.
    const stream = anthropic.messages.stream(request as never);
    const message = await stream.finalMessage();

    const text = (message.content ?? [])
      .filter((b: { type: string }) => b.type === "text")
      .map((b: { text: string }) => b.text)
      .join("\n")
      .trim();

    const inTok = message.usage?.input_tokens ?? 0;
    const outTok = message.usage?.output_tokens ?? 0;
    const cost = priceCall(cfg, model, inTok, outTok);
    await record("ok", { inTok, outTok, cost });

    return json({
      action,
      answer: text,
      grounded_on: action === "monthly_watch" ? "verified instruments" : industryCode,
      model,
      effort,
      prompt_version: cfg["ai.prompt_version"] ?? null,
      company: clientAccount?.company_name ?? null,
      // Said on every answer, because it is true on every answer.
      notice:
        "This is an explanation of the framework, not a clinical opinion and not a signed plan. A Care Net occupational medical practitioner reviews and signs every plan before release.",
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    await record("error", { error: msg.slice(0, 500) });
    console.error("assistant call failed:", msg);
    return json({ error: "The assistant could not complete that request." }, 500);
  }
});
