// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | Bee-Inspect Edge Function: report-draft 26/09/2026
//
// Deliberately thin, in the style of hsf-mco-transfer: all logic lives in the
// plain ES module ../_shared/bi/handlers/report-draft.js, which node --test exercises with
// fetch mocked (test/api/bi-edge-functions.test.mjs). What it does:
//   POST (signed in inspector) {inspection_id, use_ai?, wallet_id?}
// See the handler's header for the input, the answers and the environment
// variables it reads (names only; values live in Supabase secrets, never in
// files). Built to hsf/BUILD-CONTRACT.md 16 (Bee-Inspect P3).

import { handle } from "../_shared/bi/handlers/report-draft.js";

Deno.serve((req: Request) =>
  handle(req, {
    env: Deno.env.toObject(),
    fetch: (input: RequestInfo | URL, init?: RequestInit) => fetch(input, init),
    log: (line: string) => console.error(line),
  })
);
