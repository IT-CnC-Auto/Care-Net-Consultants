// CNC HSF FORGE | HSF-MCO-01 v1.0.0 | MyClinicOnline transfer worker 23/09/2026
//
// Moves documents that companies dropped into their Health and Safety File from
// the private hsf-staging bucket to MyClinicOnline (MCO), then removes them from
// Care Net staging. It also removes the bytes of uploads that failed their
// fingerprint check, were rejected, or were never completed within 24 hours.
// The row in hsf_upload and its fingerprints stay for the audit trail; only the
// bytes leave.
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
// Each run (contract 9.5, all through service role only database functions):
//   1. hsf_transfer_mode() reads msp_env_parameter hsf.mco_transfer_mode
//   2. hsf_transfer_claim(10) hands out uploads to transfer, locked and marked
//      'transferring'; accounts that withdrew consent are left out
//   3. hsf_sweep_stale_uploads(24) fails uploads never completed within a day
//   4. hsf_transfer_cleanup_queue(25) lists uploads whose bytes must leave
//      staging (transferred, failed, rejected); each object is deleted, then
//      hsf_mark_staging_deleted records it
// Hold is the default while the MCO interface contract (HSF-3, register
// CR-13.12) is pending: nothing leaves Care Net, and held documents are never
// deleted. Live refuses to run without MCO_BASE_URL and MCO_API_TOKEN, and its
// request shape is a placeholder until the contract arrives. Fixture is for
// tests and is refused unless
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

    // A refused run (unreadable or unknown mode, live without its settings,
    // fixture where it is not allowed, a claim that could not be read) touched
    // nothing and says why. Sweep and cleanup failures are in the summary and
    // the function logs.
    return json(summary, summary.ok ? 200 : 503);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("hsf-mco-transfer run failed:", msg.slice(0, 300));
    return json({ error: "The transfer run could not complete. Check the function logs." }, 500);
  }
});
