// CNC HSF FORGE | HSF-MCO-01 v1.0.0 | MyClinicOnline transfer worker 23/09/2026
//
// Moves documents that companies dropped into their Health and Safety File from
// the private hsf-staging bucket to MyClinicOnline (MCO), then removes them from
// Care Net staging. The row in hsf_upload and its fingerprints stay for the
// audit trail; only the bytes leave.
//
// Invoked by a schedule or by hand, with the service role key as the bearer
// token. Nobody else may run it: the check is made here, not left to the
// gateway, because any valid project key would pass the gateway.
//
// This file is deliberately thin. All logic lives in two plain ES modules that
// are unit tested with node --test (test/mco/adapter.test.mjs):
//   ../_shared/mco-adapter.js    hold, fixture and the live PLACEHOLDER
//   ../_shared/transfer-core.js  the per upload flow, the deletion rule and the
//                                Supabase REST, Storage and rpc bindings
//
// Mode comes from msp_env_parameter hsf.mco_transfer_mode on every run. Hold is
// the default while the MCO interface contract (HSF-3, register CR-13.12) is
// pending: nothing leaves Care Net and nothing is deleted. Live refuses to run
// without MCO_BASE_URL and MCO_API_TOKEN, and its request shape is a placeholder
// until the contract arrives. Fixture is for tests and is refused unless
// HSF_MCO_ALLOW_FIXTURE is 'true' in this function's environment, which must
// never be set on the production project.
//
// Secrets: SUPABASE_SERVICE_ROLE_KEY is injected by the platform; MCO_BASE_URL
// and MCO_API_TOKEN live in Supabase secrets once HSF-3 closes. None of them is
// ever logged, returned or written to the database.

import { createAdapter, sha256Hex } from "../_shared/mco-adapter.js";
import { createSupabaseIo, isServiceCaller, runTransfer } from "../_shared/transfer-core.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("SB_URL") ?? "";
const SERVICE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SB_SERVICE_ROLE_KEY") ?? "";
const MCO_BASE_URL = Deno.env.get("MCO_BASE_URL") ?? "";
const MCO_API_TOKEN = Deno.env.get("MCO_API_TOKEN") ?? "";
const ALLOW_FIXTURE = (Deno.env.get("HSF_MCO_ALLOW_FIXTURE") ?? "") === "true";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  if (!SUPABASE_URL || !SERVICE_KEY) {
    return json({ error: "The worker is not configured. SUPABASE_URL and the service key are missing." }, 500);
  }

  if (!isServiceCaller(req.headers.get("Authorization") ?? "", SERVICE_KEY)) {
    return json({ error: "This worker runs with the service role only." }, 401);
  }

  try {
    const io = createSupabaseIo({ url: SUPABASE_URL, serviceKey: SERVICE_KEY });
    const summary = await runTransfer({
      rpc: io.rpc,
      download: io.download,
      remove: io.remove,
      createAdapter,
      sha256Hex,
      mco: { baseUrl: MCO_BASE_URL, token: MCO_API_TOKEN },
      allowFixture: ALLOW_FIXTURE,
      log: (line: string) => console.error(line),
    });

    // A refused run (unknown mode, live without its settings, fixture where it
    // is not allowed, unreadable queue) touched nothing and says why.
    return json(summary, summary.ok ? 200 : 503);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("hsf-mco-transfer run failed:", msg.slice(0, 300));
    return json({ error: "The transfer run could not complete. Check the function logs." }, 500);
  }
});
