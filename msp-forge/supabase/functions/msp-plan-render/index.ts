// @ts-nocheck
// CNC MSP FORGE | DOC-GEN-02 v1.0.0 | msp-plan-render 14/10/2026
//
// Renders a reference's latest Plan on the server (gap analysis CNC-IT-MSP-019, item B):
// the same document as factory/render_pack.js, built by factory/render_core.js (inlined
// below by build.mjs), stored in the private bucket msp-plans and recorded in msp_document.
// The PLANNING ONLY marking is decided from msp_plan_signoff, read straight from the
// database (migration 073): no caller can ask for an unmarked Plan.
//
// PDF: there is no Word on the server, so the DOCX is placed in a SharePoint folder,
// converted by Microsoft Graph (?format=pdf), stored beside the DOCX and the SharePoint
// copy deleted. This needs the mail app (GRAPH_CLIENT_ID) to hold Sites.Selected with
// write on that one site, and integration.msp_pdf_site set; until then only the DOCX is
// produced and the response says why.
//
// Request: POST, header x-msp-worker-key (the Vault secret msp_worker_key).
// Body: { "reference": "CNC-MSP-...", "dry_run": true }   render and report, store nothing
//       { "reference": "CNC-MSP-..." }                    render, store, record (DOCX, and PDF when granted)
//       { "action": "seed_assets", "sha": "<commit>" }     copy factory/assets images from the repository
//                                                          at that commit into the bucket msp-factory
//       { "action": "pdf_preflight" }                      can the app reach the configured site?
// GET: health (version, secrets, assets present).
//
// Secrets: GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET (already set for the mail
// worker). The platform injects SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. Deploy with JWT
// verification OFF: the worker key is the gate. No clinical data: the Plan works at job
// category level and holds no person's results.

import * as docx from "npm:docx@9.10.0";

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
const TENANT_ID = (Deno.env.get("GRAPH_TENANT_ID") ?? "").trim();
const CLIENT_ID = (Deno.env.get("GRAPH_CLIENT_ID") ?? "").trim();
const CLIENT_SECRET = (Deno.env.get("GRAPH_CLIENT_SECRET") ?? "").trim();
const REPO_RAW = "https://raw.githubusercontent.com/IT-CnC-Auto/Care-Net-Consultants";

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function rpc(fn, args = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${fn} ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

async function storageGet(bucket, path) {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}/${path}`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!res.ok) throw new Error(`storage get ${bucket}/${path} ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

async function storagePut(bucket, path, bytes, contentType, upsert = false) {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}/${path}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": contentType,
      "x-upsert": upsert ? "true" : "false" },
    body: bytes,
  });
  if (!res.ok) throw new Error(`storage put ${bucket}/${path} ${res.status}: ${(await res.text()).slice(0, 200)}`);
}

async function sha256(bytes) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}

let cachedToken = null;
async function graphToken() {
  if (cachedToken) return cachedToken;
  const res = await fetch(`https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: CLIENT_ID, client_secret: CLIENT_SECRET,
      scope: "https://graph.microsoft.com/.default", grant_type: "client_credentials" }),
  });
  if (!res.ok) throw new Error(`graph token ${res.status}: ${(await res.text()).slice(0, 200)}`);
  cachedToken = (await res.json()).access_token;
  return cachedToken;
}

async function graph(path, init = {}) {
  const token = await graphToken();
  return fetch(`https://graph.microsoft.com/v1.0${path}`, {
    ...init, headers: { Authorization: `Bearer ${token}`, ...(init.headers || {}) },
  });
}

// The site setting may be a site id or "hostname:/sites/path"; Graph takes both in /sites/{x}.
async function pdfPreflight(site) {
  if (!pdfSiteConfigured(site)) return { ok: false, reason: "integration.msp_pdf_site is pending" };
  const res = await graph(`/sites/${site}/drive?$select=id,name,webUrl`);
  const body = await res.text();
  return { ok: res.ok, status: res.status, detail: body.slice(0, 300) };
}

async function convertToPdf(site, folder, fileName, bytes) {
  const up = await graph(`/sites/${site}/drive/root:/${spPath(folder, fileName)}:/content?@microsoft.graph.conflictBehavior=replace`, {
    method: "PUT", headers: { "Content-Type": DOCX_TYPE }, body: bytes,
  });
  if (!up.ok) throw new Error(`sharepoint upload ${up.status}: ${(await up.text()).slice(0, 200)}`);
  const item = await up.json();
  try {
    const pdf = await graph(`/sites/${site}/drive/items/${item.id}/content?format=pdf`, { redirect: "follow" });
    if (!pdf.ok) throw new Error(`pdf conversion ${pdf.status}: ${(await pdf.text()).slice(0, 200)}`);
    return new Uint8Array(await pdf.arrayBuffer());
  } finally {
    await graph(`/sites/${site}/drive/items/${item.id}`, { method: "DELETE" }).catch(() => null);
  }
}

async function loadAssets() {
  const [banner, footer, marking, clientLogo] = await Promise.all(
    [ASSET_FILES.banner, ASSET_FILES.footer, ASSET_FILES.marking, ASSET_FILES.placeholderLogo].map((f) => storageGet("msp-factory", f)));
  return { banner, footer, marking, clientLogo };
}

async function seedAssets(sha) {
  if (!/^[0-9a-f]{7,40}$/.test(sha || "")) throw new Error("seed_assets needs the commit sha");
  const out = [];
  for (const f of Object.values(ASSET_FILES)) {
    const res = await fetch(`${REPO_RAW}/${sha}/msp-forge/factory/assets/${f}`);
    if (!res.ok) throw new Error(`fetch ${f} at ${sha}: ${res.status}`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    await storagePut("msp-factory", f, bytes, "image/png", true);
    out.push({ file: f, bytes: bytes.length, sha256: await sha256(bytes) });
  }
  return out;
}

async function render(reference, dryRun) {
  const input = await rpc("msp_plan_render_input", { p_reference: reference });
  const images = await loadAssets();
  const built = RENDER.buildPlan(docx, input.draft, { templates: TEMPLATES, config: CONFIG, signoff: input.signoff,
    images, clientLogoSize: PLACEHOLDER_LOGO_SIZE });
  const bytes = new Uint8Array(await docx.Packer.toBuffer(built.doc));
  const fileName = planFileName(reference, input.version, built.marked, "docx");
  const out = { reference, plan_id: input.plan_id, version: input.version, marked: built.marked,
    marking_reason: built.markReason, docx: { file: fileName, bytes: bytes.length, sha256: await sha256(bytes) } };
  if (dryRun) return { dry_run: true, ...out, pdf: { status: pdfSiteConfigured(input.settings.pdf_site) ? "would_convert" : "waiting_for_sharepoint_grant" } };

  const docxPath = `${reference}/${fileName}`;
  await storagePut("msp-plans", docxPath, bytes, DOCX_TYPE);
  out.docx.path = docxPath;
  out.docx.document_id = await rpc("msp_plan_render_record", { p_reference: reference, p_plan_id: input.plan_id,
    p_kind: "docx", p_path: docxPath, p_version: input.version, p_marked: built.marked, p_file_name: fileName,
    p_bytes: bytes.length, p_sha256: out.docx.sha256 });

  const site = input.settings.pdf_site;
  if (!pdfSiteConfigured(site)) {
    out.pdf = { status: "waiting_for_sharepoint_grant", reason: "integration.msp_pdf_site is pending" };
    return out;
  }
  try {
    const pdf = await convertToPdf(site, input.settings.pdf_folder || "MSP Plan rendering", fileName, bytes);
    const pdfName = planFileName(reference, input.version, built.marked, "pdf");
    const pdfPath = `${reference}/${pdfName}`;
    await storagePut("msp-plans", pdfPath, pdf, "application/pdf");
    const pdfSha = await sha256(pdf);
    out.pdf = { status: "stored", file: pdfName, path: pdfPath, bytes: pdf.length, sha256: pdfSha,
      document_id: await rpc("msp_plan_render_record", { p_reference: reference, p_plan_id: input.plan_id,
        p_kind: "pdf", p_path: pdfPath, p_version: input.version, p_marked: built.marked, p_file_name: pdfName,
        p_bytes: pdf.length, p_sha256: pdfSha }) };
  } catch (err) {
    out.pdf = { status: "failed", error: String(err.message || err).slice(0, 300) };
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "GET") {
    let assets = null;
    try { assets = (await loadAssets()) && true; } catch (_) { assets = false; }
    return json({ ok: true, fn: "msp-plan-render", version: RENDER_VERSION, assets,
      secrets: { graph: !!(TENANT_ID && CLIENT_ID && CLIENT_SECRET), service: !!SERVICE_KEY } });
  }
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const key = req.headers.get("x-msp-worker-key") || "";
  try {
    if (!(await rpc("msp_worker_key_check", { p_key: key }))) return json({ error: "unauthorised" }, 401);
  } catch (err) {
    return json({ error: "key check failed", detail: String(err.message || err).slice(0, 200) }, 500);
  }
  const body = await req.json().catch(() => ({}));
  const started = Date.now();
  try {
    if (body.action === "seed_assets") return json({ action: "seed_assets", version: RENDER_VERSION, seeded: await seedAssets(body.sha) });
    if (body.action === "pdf_preflight") {
      const site = (await rpc("msp_env_get", { p_key: "integration.msp_pdf_site" }));
      return json({ action: "pdf_preflight", version: RENDER_VERSION, site, ...(await pdfPreflight(site)) });
    }
    if (!body.reference) return json({ error: "reference is required" }, 400);
    const out = await render(String(body.reference), body.dry_run === true);
    return json({ version: RENDER_VERSION, ...out, ms: Date.now() - started });
  } catch (err) {
    return json({ error: "render failed", detail: String(err.message || err).slice(0, 500), ms: Date.now() - started }, 500);
  }
});

// ============================== CORE START ==============================
// Pure JavaScript from here to CORE END: no Deno, no network. The Node test
// (msp-forge/test/plan-render.test.mjs) loads this region on its own.

const RENDER_VERSION = "1.0.0";
const DOCX_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const ASSET_FILES = {
  banner: "cnc_header_banner.png",
  footer: "cnc_footer_banner.png",
  marking: "marking_planning_only.png",
  placeholderLogo: "client_logo_placeholder.png",
};
// MD ruling 31/08/2026: no real client logo on a document until the client supplies one.
const PLACEHOLDER_LOGO_SIZE = [130, 32];

function planFileName(reference, version, marked, ext) {
  return `${reference}_Medical_Surveillance_Plan_v${version}${marked ? "_PLANNING_ONLY" : "_SIGNED"}.${ext}`;
}

function pdfSiteConfigured(site) {
  const s = String(site || "").trim();
  return s !== "" && s.toLowerCase() !== "pending";
}

// "MSP Plan rendering" + "file.docx" -> "MSP%20Plan%20rendering/file.docx"
function spPath(folder, fileName) {
  return [...String(folder || "").split("/").filter(Boolean), fileName].map(encodeURIComponent).join("/");
}

const TEMPLATES = /* TEMPLATES START: generated from msp-forge/factory/templates.json by build.mjs, do not edit here */
{
 "TPL-LIA-01": {
  "heading": "Compliance note: limitation of Care Net's role and liability",
  "body": [
   "Care Net Consultants (Pty) Ltd did not conduct the underlying workplace risk assessment or occupational hygiene survey referred to in this Plan. That risk assessment was conducted by, or on behalf of, the Client, and was supplied to Care Net for the sole purpose of designing this medical surveillance programme.",
   "Care Net's role is limited to the design and implementation of the medical surveillance programme (the OREP and WASP) based on the exposure information provided by the Client. Care Net has not independently verified the accuracy, completeness, or currency of that risk assessment data.",
   "Accordingly, Care Net accepts no responsibility or liability for the accuracy, completeness, or currency of the risk assessment information supplied by the Client, or for any hazard, exposure, or job category that was not disclosed to Care Net at the time this Plan was prepared.",
   "The Client remains responsible for ensuring that its workplace risk assessment is conducted and kept up to date by a competent person or approved inspection authority, and for promptly informing Care Net of any change in process, plant, materials, or job content so that this Plan can be reviewed and, where necessary, revised."
  ]
 },
 "TPL-POP-01": {
  "heading": "Confidentiality and protection of personal information",
  "bullets": [
   "Individual medical results remain strictly confidential and are held by Care Net's Occupational Health Practitioners under the Designated OMP.",
   "The Client receives only the fitness outcome and any applicable work restrictions for each employee, never clinical detail or test results.",
   "Employees provide informed consent before any personal medical information is released beyond the fitness outcome.",
   "De-identified, aggregated group data may be shared with the Client for workplace risk-management purposes.",
   "All records are processed and stored in accordance with the Protection of Personal Information Act 4 of 2013 (POPIA)."
  ],
  "note_heading": "POPIA note",
  "note": "This Plan and its annexures contain only job-category and fitness-outcome information. Clinical findings and individual test results are not recorded in this document and are held separately under the Designated OMP."
 },
 "TPL-SGN-01": {
  "omp_heading": "Care Net Occupational Medical Practitioner approval",
  "omp_intro": "Approval of this Plan by the Designated OMP confirms that the medical assessments and intervals in Sections 5 and 6 are clinically appropriate to the exposures reported by the Client, on the basis set out in Section 4.",
  "omp_lines": [
   "Signature: __________________________________________",
   "Full name: __________________________________________",
   "Role: Designated Occupational Medical Practitioner. {designated_omp_line}",
   "For and on behalf of Care Net Consultants (Pty) Ltd",
   "Date (DD/MM/YYYY): __________________________________________"
  ],
  "client_heading": "Client acknowledgement",
  "client_intro": "The Client acknowledges that the hazard and exposure information described in Sections 2, 5, and 8 of this Plan was supplied by the Client, that Care Net did not conduct the underlying risk assessment, and that the Client remains responsible for the accuracy of that information and for its periodic review, as set out in Section 4.",
  "client_lines": [
   "Signature: __________________________________________",
   "Full name: __________________________________________",
   "Role: [Client Representative Title]",
   "For and on behalf of {client_name}",
   "Date (DD/MM/YYYY): __________________________________________"
  ]
 },
 "TPL-EXA-01": {
  "heading": "Types of medical examination performed under this Plan",
  "rows": [
   [
    "Pre-placement / pre-employment",
    "Establishes baseline health status and confirms fitness for the specific job's requirements before exposure begins"
   ],
   [
    "Routine / periodic",
    "Conducted at the interval defined in the WASP table above, for as long as the employee remains in the exposed role"
   ],
   [
    "Transfer examination",
    "Performed when an employee moves to a role with a different exposure profile or capability requirement"
   ],
   [
    "Return-to-work examination",
    "Performed following occupational injury, illness, or prolonged absence, before the employee resumes duties"
   ],
   [
    "Exit / termination examination",
    "Performed at the end of service to establish health status and whether any occupational exposure effect has developed"
   ],
   [
    "Trigger / unscheduled examination",
    "Performed where there is a change in the OREP, new symptoms are reported, or a significant workplace incident occurs"
   ]
  ]
 },
 "TPL-CGN-01": {
  "heading": "Clinical protocol note: implication of exceedances, subject to OMP confirmation",
  "body": [
   "The measured levels above indicate exposures at or above the applicable occupational exposure limit for one or more job categories. Pending the Designated OMP's review and confirmation, Care Net's provisional view is that the affected categories warrant the annual interval already set in Section 6 as a minimum, with earlier or additional testing where clinical findings indicate.",
   "These figures also indicate a need for the Client to review engineering and administrative controls for the affected areas per the hierarchy of controls. Medical surveillance detects early effect but does not substitute for controlling the exposure at source."
  ]
 }
}
/* TEMPLATES END */;

const CONFIG = /* CONFIG START: generated from msp-forge/factory/config.json by build.mjs, do not edit here */
{
 "designated_omp": {
  "name": "Dr C. P. Green-Thompson",
  "hpcsa_registration": "MP 0195952",
  "sasom_membership": "SAS1270",
  "display_line": "Dr C. P. Green-Thompson | HPCSA Reg No. MP 0195952 | SASOM Membership SAS1270",
  "source": "Confirmed 13/08/2026 (CR-12.7). Default Designated OMP for engagements until varied per engagement. If a separate SAIOSH registration must appear in document control, add it here as saiosh_registration."
 }
}
/* CONFIG END */;

const RENDER = (() => {
  const module = { exports: {} };
  /* RENDER START: generated from msp-forge/factory/render_core.js by build.mjs, do not edit here */
// CNC MSP FORGE | DOC-GEN-01 v1.3.0 | Document Factory core
// v1.3.0 (14/10/2026): the document builder of render_pack.js v1.2.0, unchanged, lifted into a
// pure function so the Node command line (render_pack.js) and the msp-plan-render edge
// function (Deno, inlined by its build.mjs) produce the same Plan from the same inputs. No
// file system, no environment: the caller passes the docx library, the draft and the assets.
//
// buildPlan(docx, draft, inp) -> { doc, marked, markReason }
//   draft: { classification, framed, profile, prescribed, composed, validation } (one drafting run)
//   inp:   { templates, config, signoff, clientLogoSize: [w, h],
//            images: { banner, footer, marking, clientLogo } }  (bytes: Buffer or Uint8Array)
// The PLANNING ONLY marking is left off only for a signoff record from msp_plan_signoff that
// shows an approved decision with name, HPCSA number, signature and signing time for this Plan.

function buildPlan(docx, draftIn, inp) {
  const {
    Document, Packer, Paragraph, TextRun, ImageRun, Header, Footer,
    Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType,
    AlignmentType, HeadingLevel, TableOfContents, PageBreak, PageNumber,
    TabStopType, VerticalAlign,
    HorizontalPositionRelativeFrom, VerticalPositionRelativeFrom, TextWrappingType,
  } = docx;
  const draft = JSON.parse(JSON.stringify(draftIn));
  const TPL = inp.templates;

  const RED = 'ED1B24';
  const CHARCOAL = '1A1A1A';
  const LIGHT = 'F2F2F2';
  const FONT = 'Arial';
  const CONTENT_W = 9072;

  const P = draft.composed.placeholders;
  // The Designated OMP identity comes from factory config (CR-12.7); the
  // engagement placeholder wins only when it names a specific OMP.
  const CONFIG = inp.config;
  if (!P.omp_name_placeholder || P.omp_name_placeholder.includes('CR-12.7')) {
    P.omp_name_placeholder = CONFIG.designated_omp.display_line + ' (approval pending, Section 11.1)';
  }
  // ------------------------------------------------------------ planning only --
  // The marking is a clinical statement: no Occupational Medical Practitioner has
  // reviewed or signed this document. Marked unless a valid sign off record says otherwise.
  const MARK_BAND = 'PLANNING ONLY. NOT REVIEWED OR SIGNED BY AN OMP.';
  function signoffProblem(s) {
    if (!s) return 'no practitioner sign off record';
    if (s.reference !== P.reference) return `sign off record is for ${s.reference}, not ${P.reference}`;
    if (s.decision !== 'approved') return `practitioner decision is ${s.decision || 'not recorded'}, not approved`;
    for (const k of ['omp_name', 'omp_hpcsa_number', 'signature_name', 'signed_at']) {
      if (!String(s[k] || '').trim()) return `sign off record has no ${k}`;
    }
    if (s.signed !== true) return 'sign off record is not marked signed';
    return null;
  }
  const SIGNOFF = inp.signoff || null;
  const MARK_REASON = signoffProblem(SIGNOFF);
  const MARKED = MARK_REASON !== null;
  const markingImage = MARKED ? inp.images.marking : null;
  if (!MARKED) {
    P.omp_name_placeholder = `${SIGNOFF.omp_name}, HPCSA ${SIGNOFF.omp_hpcsa_number}, approved and signed ${String(SIGNOFF.signed_at).slice(0, 10)}`;
  }

  const cncBanner = inp.images.banner;
  const cncFooter = inp.images.footer;
  // Client logo: the caller supplies the image and its size in points (the prepared sample,
  // a neutral placeholder, or the client's own prepared logo). MD ruling 31/08/2026: no real
  // client logo on non-client documents.
  const clientLogo = inp.images.clientLogo;
  const clientLogoSize = inp.clientLogoSize;

  // ------------------------------------------------------------------ helpers --
  const run = (text, opts = {}) => new TextRun({ text, font: FONT, size: opts.size || 20, bold: !!opts.bold, italics: !!opts.italics, color: opts.color || CHARCOAL });
  const para = (text, opts = {}) => new Paragraph({
    alignment: opts.align, spacing: { after: opts.after ?? 120, line: 300, lineRule: 'auto' },
    heading: opts.heading, children: [run(text, opts)],
  });
  const h1 = (text) => new Paragraph({
    heading: HeadingLevel.HEADING_1, spacing: { before: 320, after: 160 },
    children: [new TextRun({ text, font: FONT, size: 28, bold: true, color: RED })],
  });
  const h2 = (text) => new Paragraph({
    heading: HeadingLevel.HEADING_2, spacing: { before: 240, after: 120 },
    children: [new TextRun({ text, font: FONT, size: 23, bold: true, color: CHARCOAL })],
  });
  const h3 = (text) => new Paragraph({
    heading: HeadingLevel.HEADING_3, spacing: { before: 180, after: 100 },
    children: [new TextRun({ text, font: FONT, size: 21, bold: true, color: RED })],
  });

  function cell(text, opts = {}) {
    return new TableCell({
      width: { size: opts.w, type: WidthType.DXA },
      shading: opts.shade ? { type: ShadingType.CLEAR, fill: opts.shade } : undefined,
      verticalAlign: VerticalAlign.TOP,
      margins: { top: 60, bottom: 60, left: 80, right: 80 },
      children: [new Paragraph({ children: [run(String(text ?? ''), { size: opts.size || 17, bold: !!opts.bold, color: opts.color })] })],
    });
  }

  function brandTable(headers, rows, widths) {
    const total = widths.reduce((a, b) => a + b, 0);
    return new Table({
      width: { size: total, type: WidthType.DXA },
      columnWidths: widths,
      borders: {
        top: { style: BorderStyle.SINGLE, size: 4, color: CHARCOAL },
        bottom: { style: BorderStyle.SINGLE, size: 4, color: CHARCOAL },
        left: { style: BorderStyle.SINGLE, size: 2, color: 'BBBBBB' },
        right: { style: BorderStyle.SINGLE, size: 2, color: 'BBBBBB' },
        insideHorizontal: { style: BorderStyle.SINGLE, size: 2, color: 'CCCCCC' },
        insideVertical: { style: BorderStyle.SINGLE, size: 2, color: 'CCCCCC' },
      },
      rows: [
        new TableRow({ tableHeader: true, children: headers.map((t, i) => cell(t, { w: widths[i], shade: CHARCOAL, color: 'FFFFFF', bold: true })) }),
        ...rows.map((r, ri) => new TableRow({ children: r.map((t, i) => cell(t, { w: widths[i], shade: ri % 2 ? LIGHT : undefined })) })),
      ],
    });
  }

  // -------------------------------------------------------------- header/footer --
  // Full page image anchored to the page and drawn behind the text, so it repeats on
  // every page under the content; then a red band under the brand row. Table rows that
  // were filled white are left unfilled (same look on a white page) so the marking shows.
  function markingParagraphs() {
    if (!MARKED) return [];
    return [new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 0 },
      shading: { type: ShadingType.CLEAR, fill: RED },
      children: [
        new ImageRun({
          type: 'png', data: markingImage,
          transformation: { width: 794, height: 1123 },
          floating: {
            horizontalPosition: { relative: HorizontalPositionRelativeFrom.PAGE, offset: 0 },
            verticalPosition: { relative: VerticalPositionRelativeFrom.PAGE, offset: 0 },
            behindDocument: true, allowOverlap: true, lockAnchor: true,
            wrap: { type: TextWrappingType.NONE },
          },
          altText: { title: 'Planning only', description: 'PLANNING ONLY marking: not reviewed or signed by an Occupational Medical Practitioner', name: 'planning-only-marking' },
        }),
        new TextRun({ text: MARK_BAND, font: FONT, size: 16, bold: true, color: 'FFFFFF' }),
      ],
    })];
  }

  function dualBrandHeader() {
    return new Header({
      children: [new Table({
        width: { size: CONTENT_W, type: WidthType.DXA },
        columnWidths: [6500, 2572],
        borders: { top: { style: BorderStyle.NONE }, bottom: { style: BorderStyle.NONE }, left: { style: BorderStyle.NONE }, right: { style: BorderStyle.NONE }, insideHorizontal: { style: BorderStyle.NONE }, insideVertical: { style: BorderStyle.NONE } },
        rows: [new TableRow({
          children: [
            new TableCell({
              width: { size: 6500, type: WidthType.DXA }, verticalAlign: VerticalAlign.CENTER,
              children: [new Paragraph({ children: [new ImageRun({ type: 'png', data: cncBanner, transformation: { width: 440, height: 102 }, altText: { title: 'Care Net Consultants', description: 'Care Net Consultants brand banner', name: 'cnc-banner' } })] })],
            }),
            new TableCell({
              width: { size: 2572, type: WidthType.DXA }, verticalAlign: VerticalAlign.CENTER,
              children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [new ImageRun({ type: 'png', data: clientLogo, transformation: { width: clientLogoSize[0], height: clientLogoSize[1] }, altText: { title: 'Client logo', description: 'Client brand mark', name: 'client-logo' } })] })],
            }),
          ],
        })],
      }), ...markingParagraphs()],
    });
  }

  function brandFooter() {
    return new Footer({
      children: [
        new Paragraph({
          tabStops: [{ type: TabStopType.RIGHT, position: CONTENT_W }],
          spacing: { after: 40 },
          children: [
            new TextRun({ text: 'Proudly prepared by the Care Net Consultants Team. Your Partner in Workplace Health.', font: FONT, size: 14, color: CHARCOAL, italics: true }),
            new TextRun({ text: '\t', font: FONT }),
            new TextRun({ children: ['Page ', PageNumber.CURRENT, ' of ', PageNumber.TOTAL_PAGES], font: FONT, size: 14, color: CHARCOAL }),
          ],
        }),
        new Paragraph({ alignment: AlignmentType.CENTER, children: [new ImageRun({ type: 'png', data: cncFooter, transformation: { width: 605, height: 161 }, altText: { title: 'Care Net Consultants footer', description: 'Care Net Consultants letterhead footer', name: 'cnc-footer' } })] }),
      ],
    });
  }

  // ---------------------------------------------------------------- lock blocks --
  function lockedBlock(anchor) {
    const t = TPL[anchor];
    const out = [];
    if (anchor === 'TPL-LIA-01' || anchor === 'TPL-CGN-01') {
      out.push(h3(t.heading));
      t.body.forEach(b => out.push(para(b, { size: 19 })));
    } else if (anchor === 'TPL-POP-01') {
      t.bullets.forEach(b => out.push(new Paragraph({ spacing: { after: 80 }, numbering: { reference: 'bullets', level: 0 }, children: [run(b, { size: 19 })] })));
      out.push(h3(t.note_heading));
      out.push(para(t.note, { size: 19 }));
    } else if (anchor === 'TPL-EXA-01') {
      out.push(h3(t.heading));
      out.push(brandTable(['Examination type', 'Purpose and timing'], t.rows, [2800, 6272]));
    } else if (anchor === 'TPL-SGN-01') {
      out.push(h2('11.1 ' + t.omp_heading));
      out.push(para(t.omp_intro, { size: 19 }));
      t.omp_lines.forEach(l => out.push(para(l.replace('{designated_omp_line}', CONFIG.designated_omp.display_line), { size: 19, after: 60 })));
      out.push(h2('11.2 ' + t.client_heading));
      out.push(para(t.client_intro, { size: 19 }));
      t.client_lines.forEach(l => out.push(para(l.replace('{client_name}', P.client_name), { size: 19, after: 60 })));
    }
    return out;
  }

  // -------------------------------------------------------------------- tables --
  const TABLE_DEFS = {
    regulatory_frame: { headers: ['Instrument', 'Applicability to this engagement'], widths: [4600, 4472], map: r => [r.instrument, r.applicability] },
    orep_jobs: { headers: ['Job title', 'Employees', 'Principal duties', 'Identified hazards', 'Exposure rating'], widths: [1750, 850, 2300, 2600, 1572], map: r => [r.job_title, r.headcount, r.duties, r.hazards, r.exposure_rating] },
    quantified_exposures: { headers: ['Hazard and location', 'Measured level', 'OEL or action value', 'Assessment', 'Date measured'], widths: [2700, 1500, 2400, 1400, 1072], map: r => [r.hazard_location, r.measured, r.oel, String(r.assessment).replace(/_/g, ' '), r.date] },
    risk_matrix: { headers: ['Job title', 'Hazard', 'L', 'S', 'Exposure rating', 'Control adequacy', 'Residual risk'], widths: [1850, 2100, 500, 500, 1500, 1300, 1322], map: r => [r.job_title, `${r.hazard_code}: ${r.hazard_name}`, r.likelihood, r.severity, r.exposure_rating, r.control_adequacy, r.residual_risk] },
    inherent_requirements: { headers: ['Job title', 'Physical demands', 'Sensory and cognitive demands', 'Statutory or competency requirement'], widths: [1850, 2500, 2500, 2222], map: r => [r.job_title, r.physical, r.sensory_cognitive, r.statutory] },
    chemical_register: { headers: ['Substance', 'SDS reference', 'Task or process', 'Frequency', 'Controls in place'], widths: [2100, 1300, 2100, 1300, 2272], map: r => [r.substance_name, r.sds_reference, r.task_process, r.frequency, r.controls] },
    wasp: { headers: ['Job title', 'Baseline (pre placement)', 'Periodic and interval', 'Exit', 'Biological monitoring'], widths: [1600, 2000, 2400, 1600, 1472], map: r => [r.job_title, r.baseline, r.periodic, r.exit, r.biological_monitoring] },
    rpe_status: { headers: ['Job title', 'RPE issued', 'RPE fit tested', 'Surveillance implication'], widths: [1850, 1500, 1300, 4422], map: r => [r.job_title, r.rpe_issued, r.rpe_fit_tested, r.implication] },
  };

  function renderTable(name, rows) {
    const def = TABLE_DEFS[name];
    if (!def) return [para(`[table ${name}]`)];
    return [brandTable(def.headers, rows.map(def.map), def.widths)];
  }

  // ---------------------------------------------------------------------- body --
  const body = [];

  // Document control block
  body.push(h1('DOCUMENT CONTROL'));
  body.push(brandTable(['Item', 'Detail'], [
    ['Document reference', P.reference],
    ['Version', P.version],
    ['Date of issue', P.date_of_issue],
    ['Classification', P.classification_banner.replace('CLASSIFICATION: ', '')],
    ['Prepared by', 'Care Net Consultants (Pty) Ltd, CNC MSP FORGE Document Factory'],
    ['Author governance', 'Prepared under the direction of the Director: BCom, Postgraduate qualification in Taxation, MBA, Professional Masters in Artificial Intelligence, Candidate Doctorate in Artificial Intelligence'],
    ['OMP approval record', P.omp_name_placeholder],
    ['Compensation route', P.compensation_route],
    ['Next review', 'Twelve months from date of issue, and immediately on the triggers in Section 10. Scheduled trigger: noise instrument transition, 6 September 2026'],
  ], [2600, 6472]));
  body.push(new Paragraph({ children: [new PageBreak()] }));

  // Table of contents, three levels
  body.push(h1('TABLE OF CONTENTS'));
  body.push(new TableOfContents('Table of Contents', { hyperlink: true, headingStyleRange: '1-3' }));
  body.push(new Paragraph({ children: [new PageBreak()] }));

  // Executive summary, findings first, never exceeding two pages
  const critical = draft.profile.jobs.flatMap(j => j.risk_matrix.filter(r => r.residual_risk === 'critical').map(r => `${j.title}: ${r.hazard_name}`));
  body.push(h1('EXECUTIVE SUMMARY'));
  // Every figure below is read from the validated draft for this engagement; nothing is templated.
  const overLimit = draft.profile.exceedances.filter(x => ['exceeds', 'significantly_exceeds', 'borderline'].includes(x.assessment));
  const describeOel = x => x.kernel_oel || (x.stated_oel ? `${x.stated_oel} (client stated)` : 'its stated limit');
  const words = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine'];
  const countWord = n => n < words.length ? words[n] : String(n);
  const plural = (n, one, many) => (n === 1 ? one : many);
  if (overLimit.length) {
    body.push(para(`${countWord(overLimit.length)} measured ${plural(overLimit.length, 'exposure', 'exposures')} at ${P.client_name} ${plural(overLimit.length, 'stands', 'stand')} at or above ${plural(overLimit.length, 'its', 'their')} occupational exposure ${plural(overLimit.length, 'limit', 'limits')}: ${overLimit.map(x => `${x.hazard_location.toLowerCase()} at ${x.measured} against ${describeOel(x)}`).join('; ')}. ${plural(overLimit.length, 'This exceedance drives', 'These exceedances drive')} this Plan's central prescription: annual surveillance as a strict minimum for every affected category, tighter where the Designated OMP directs, and a clear message that surveillance detects early effect but does not substitute for controlling exposure at source.`, { size: 19 }));
  } else {
    body.push(para(`No measured exposure supplied by ${P.client_name} stands above its occupational exposure limit. The surveillance intervals in this Plan therefore rest on the hazard profile of each job category and the twelve month floor, and are reviewed when hygiene measurements are supplied or updated.`, { size: 19 }));
  }
  const critCats = [...new Set(critical.map(c => c.split(':')[0]))];
  const rpeUnconfirmed = draft.profile.jobs.filter(j => j.rpe.issued && !/^n(one|ot|\/a)/i.test(String(j.rpe.issued)) && !String(j.rpe.fit_tested || '').toLowerCase().startsWith('y')).map(j => j.title);
  body.push(para(`The Plan covers ${P.workforce_covered.toLowerCase()} across the sites listed in Section 2. The Occupational Risk Exposure Profile identifies ${critical.length} hazard ${plural(critical.length, 'exposure', 'exposures')} carrying critical residual risk after reported controls${critCats.length ? ', concentrated in: ' + critCats.join(', ') : ''}. ${rpeUnconfirmed.length ? `Respiratory protective equipment is issued but not yet confirmed fit tested for ${rpeUnconfirmed.join(' and ')}, so RPE is not relied upon as a full control and fit testing is recommended as a priority.` : 'Where respiratory protective equipment is issued it is recorded in Section 6; no category relies on unconfirmed RPE as a control.'}`, { size: 19 }));
  const ompMatters = (draft.prescribed.omp_notes || []).length;
  const chronicCats = draft.profile.jobs.filter(j => j.chronic_flag).map(j => j.title);
  body.push(para(`Every test prescribed in the Worker Allocated Surveillance Programme is justified twice: against the exposure it monitors and against the inherent requirements of the job under section 7 of the Employment Equity Act. ${ompMatters ? `${countWord(ompMatters)} ${plural(ompMatters, 'matter is', 'matters are')} reserved to the Designated OMP${chronicCats.length ? `, including the enhanced screening approach for the ${plural(chronicCats.length, 'job category', 'job categories')} flagged, at aggregate level only, for chronic conditions with sudden incapacity potential` : ''}.` : 'No matter is reserved to the Designated OMP beyond the review itself; every reference value cited is kernel verified.'} This Plan is a draft until the Designated OMP's approval is recorded in Section 11.`, { size: 19 }));
  body.push(new Paragraph({ children: [new PageBreak()] }));

  // Sections 1 to 11 from the composed draft
  for (const s of draft.composed.sections) {
    body.push(h1(`${s.section_no}. ${s.heading.toUpperCase()}`));
    for (const b of s.blocks) {
      if (b.kind === 'paragraph') body.push(para(b.text, { size: 19 }));
      else if (b.kind === 'questionnaire_context') {
        body.push(h2(`${s.section_no}.1 Context drawn from the Client's completed onboarding form`));
        b.items.forEach(i => body.push(new Paragraph({ spacing: { after: 80 }, numbering: { reference: 'bullets', level: 0 }, children: [run(i, { size: 19 })] })));
      } else if (b.kind === 'table') {
        body.push(...renderTable(b.table.name, b.table.rows));
        body.push(para('', { after: 100 }));
      } else if (b.kind === 'locked_template') {
        body.push(...lockedBlock(b.template_anchor));
      }
    }
  }

  // Annexures
  body.push(new Paragraph({ children: [new PageBreak()] }));
  body.push(h1('ANNEXURE B: EMPLOYEE TO JOB CATEGORY REGISTER TEMPLATE'));
  body.push(para('Only the last four digits of each identity number are ever recorded, in line with Care Net data minimisation practice under POPIA. The register is maintained by the Client SHE or HR representative and updated on every start, transfer, and exit.', { size: 19 }));
  body.push(brandTable(['Employee (surname, initial)', 'ID number (last 4 digits only)', 'Job category (per Sections 5 and 6)'], [['', '', ''], ['', '', ''], ['', '', '']], [3200, 2400, 3472]));

  body.push(h1('ANNEXURE C: TWELVE MONTH SURVEILLANCE CALENDAR'));
  body.push(para('All categories carry annual periodic surveillance. Baseline examinations are completed before exposure begins for every new engagement, transfer examinations on any change of exposure profile, and exit examinations on termination of exposure. The annual cycle for this Plan runs from the date of the OMP approval in Section 11.', { size: 19 }));
  body.push(brandTable(['Month', 'Activity'], [
    ['Month 1', 'Baseline completion sweep and programme induction for all categories'],
    ['Months 2 to 11', 'Periodic examinations by category per the WASP, scheduled with the Client SHE representative'],
    ['Month 12', 'Annual cycle close, exceedance review against updated hygiene data, and Plan review per Section 10'],
  ], [1800, 7272]));

  body.push(h1('ANNEXURE D: SOURCE LIST'));
  body.push(para('Sources are drawn from verified kernel rows only and presented once, with no in text citations, per house style.', { size: 19 }));
  draft.framed.instruments.forEach(i => body.push(new Paragraph({ spacing: { after: 60 }, numbering: { reference: 'bullets', level: 0 }, children: [run(i.full_citation, { size: 17 })] })));

  // ---------------------------------------------------------------------- cover --
  const cover = [
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 500, after: 200 }, children: [run(P.classification_banner, { size: 18, bold: true, color: 'FFFFFF' })], shading: { type: ShadingType.CLEAR, fill: RED } },),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 1200, after: 200 }, children: [run('MEDICAL SURVEILLANCE PLAN', { size: 48, bold: true, color: RED })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 500 }, children: [run(P.client_name.toUpperCase(), { size: 30, bold: true })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 1200 }, children: [run(`Document Reference: ${P.reference}   |   Version ${P.version}   |   Date of Issue: ${P.date_of_issue}`, { size: 18 })] }),
  ];
  const meta = brandTable(['', ''], [
    ['Client company name', P.client_name],
    ['Core industry / sector', `${P.industry_name}: ${P.subindustry_name}`],
    ['Registered address', P.client_address],
    ['Sites covered by this plan', P.sites_covered],
    ['Workforce covered', P.workforce_covered],
    ['Client contact person', P.client_contact],
    ['Care Net service line', P.care_net_service_line],
    ['Designated Occupational Medical Practitioner', P.omp_name_placeholder],
  ], [3200, 5872]);
  cover.push(meta);
  cover.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 700 }, children: [run(P.footer_line, { size: 18, italics: true })] }));
  cover.push(new Paragraph({ children: [new PageBreak()] }));

  // ------------------------------------------------------------------ document --
  const doc = new Document({
    features: { updateFields: true },
    numbering: {
      config: [{
        reference: 'bullets',
        levels: [{ level: 0, format: 'bullet', text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 360, hanging: 200 } } } }],
      }],
    },
    styles: { default: { document: { run: { font: FONT, size: 20, color: CHARCOAL } } } },
    sections: [{
      properties: {
        page: {
          size: { width: 11906, height: 16838 },
          margin: { top: 2892, right: 1417, bottom: 3207, left: 1417, header: 504, footer: 504 },
        },
      },
      headers: { default: dualBrandHeader() },
      footers: { default: brandFooter() },
      children: [...cover, ...body],
    }],
  });

  return { doc, marked: MARKED, markReason: MARK_REASON };
}

module.exports = { buildPlan };
  /* RENDER END */
  return module.exports;
})();
// =============================== CORE END ===============================
