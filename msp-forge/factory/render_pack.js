// CNC MSP FORGE | DOC-GEN-01 v1.0.0 | Document Factory renderer
// Renders the validated structured draft (agent/draft.json) into the dual
// branded Medical Surveillance Pack DOCX per the cnc-msp-dualbrand skill
// v1.0.0. Locked template blocks insert verbatim from templates.json and are
// never paraphrased. Geometry is verified after render by verify_geometry.py.
//
// Usage: node render_pack.js <draft.json> <output.docx>

const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, ImageRun, Header, Footer,
  Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType,
  AlignmentType, HeadingLevel, TableOfContents, PageBreak, PageNumber,
  TabStopType, VerticalAlign,
} = require('docx');

const draft = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const OUT = process.argv[3];
const TPL = JSON.parse(fs.readFileSync(path.join(__dirname, 'templates.json'), 'utf8'));
const ASSETS = path.join(__dirname, 'assets');

const RED = 'ED1B24';
const CHARCOAL = '1A1A1A';
const LIGHT = 'F2F2F2';
const FONT = 'Arial';
const CONTENT_W = 9072;

const P = draft.composed.placeholders;
// The Designated OMP identity comes from factory config (CR-12.7); the
// engagement placeholder wins only when it names a specific OMP.
const CONFIG = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
if (!P.omp_name_placeholder || P.omp_name_placeholder.includes('CR-12.7')) {
  P.omp_name_placeholder = CONFIG.designated_omp.display_line + ' (approval pending, Section 11.1)';
}
const cncBanner = fs.readFileSync(path.join(ASSETS, 'cnc_header_banner.png'));
const cncFooter = fs.readFileSync(path.join(ASSETS, 'cnc_footer_banner.png'));
const clientLogo = fs.readFileSync(path.join(ASSETS, 'client_logo_prepared.png'));
const clientLogoSize = JSON.parse(fs.readFileSync(path.join(ASSETS, 'client_logo_prepared.report.json'), 'utf8')).prepared_size;

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
      ...rows.map((r, ri) => new TableRow({ children: r.map((t, i) => cell(t, { w: widths[i], shade: ri % 2 ? LIGHT : 'FFFFFF' })) })),
    ],
  });
}

// -------------------------------------------------------------- header/footer --
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
    })],
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
body.push(para(`Three measured exposures at ${P.client_name} stand at or above their occupational exposure limits: noise in the plant and compaction area at 92 dB(A) against the 85 dB(A) rating limit, respirable crystalline silica at 0.15 mg/m3 against the 0.1 mg/m3 limit, and welding fume reported well above its stated limit. These exceedances drive this Plan's central prescription: annual surveillance as a strict minimum for every affected category, tighter where the Designated OMP directs, and a clear message that surveillance detects early effect but does not substitute for controlling exposure at source.`, { size: 19 }));
body.push(para(`The Plan covers ${P.workforce_covered.toLowerCase()} across the sites listed in Section 2. The Occupational Risk Exposure Profile identifies ${critical.length} hazard exposures carrying critical residual risk after reported controls, concentrated in: ${[...new Set(critical.map(c => c.split(':')[0]))].join(', ')}. Respiratory protective equipment is issued but not yet confirmed fit tested for two dust exposed categories, so RPE is not relied upon as a full control and fit testing is recommended as a priority.`, { size: 19 }));
body.push(para(`Every test prescribed in the Worker Allocated Surveillance Programme is justified twice: against the exposure it monitors and against the inherent requirements of the job under section 7 of the Employment Equity Act. Five matters are reserved to the Designated OMP, including biological monitoring reference values and the enhanced screening approach for the two job categories flagged, at aggregate level only, for chronic conditions with sudden incapacity potential. This Plan is a draft until the Designated OMP's approval is recorded in Section 11.`, { size: 19 }));
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

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(OUT, buf);
  console.log(`${OUT} written (${buf.length} bytes)`);
});
