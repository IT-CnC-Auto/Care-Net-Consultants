// CNC MSP FORGE | FRM-DSL-01 v1.0.0 | Onboarding form DOCX generator
// Reads fields.json (single source of truth) and emits:
//   1. onboarding_form.docx with DocuSeal {{field}} text tags, ready to upload
//      as a DocuSeal template (fields parse from the tags on upload)
//   2. schema.json, the JSON Schema the webhook validator enforces
// Brand: Arial, CNC red #ED1B24, charcoal #1A1A1A. A4. No letterhead images in
// this machine form; the client facing pack (Phase 4) carries full dual branding.

const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType,
} = require('docx');

const spec = JSON.parse(fs.readFileSync(path.join(__dirname, 'fields.json'), 'utf8'));
const ROLE = spec.docuseal_role;

const RED = 'ED1B24';
const CHARCOAL = '1A1A1A';
const FONT = 'Arial';

function tag(name, type) {
  const t = type === 'textarea' ? 'text' : type;
  return `{{${name};role=${ROLE};type=${t}}}`;
}

function heading(text) {
  return new Paragraph({
    spacing: { before: 280, after: 120 },
    children: [new TextRun({ text, bold: true, color: RED, font: FONT, size: 26 })],
  });
}

function subheading(text) {
  return new Paragraph({
    spacing: { before: 200, after: 80 },
    children: [new TextRun({ text, bold: true, color: CHARCOAL, font: FONT, size: 22 })],
  });
}

function body(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 80 },
    children: [new TextRun({ text, font: FONT, size: 20, color: CHARCOAL, italics: !!opts.italics })],
  });
}

function fieldRow(label, fieldName, type) {
  return new TableRow({
    children: [
      new TableCell({
        width: { size: 4800, type: WidthType.DXA },
        margins: { top: 60, bottom: 60, left: 80, right: 80 },
        children: [new Paragraph({ children: [new TextRun({ text: label, font: FONT, size: 18, color: CHARCOAL })] })],
      }),
      new TableCell({
        width: { size: 4200, type: WidthType.DXA },
        margins: { top: 60, bottom: 60, left: 80, right: 80 },
        children: [new Paragraph({ children: [new TextRun({ text: tag(fieldName, type), font: FONT, size: 16, color: '555555' })] })],
      }),
    ],
  });
}

function fieldsTable(rows) {
  return new Table({
    width: { size: 9000, type: WidthType.DXA },
    columnWidths: [4800, 4200],
    borders: {
      top: { style: BorderStyle.SINGLE, size: 2, color: 'CCCCCC' },
      bottom: { style: BorderStyle.SINGLE, size: 2, color: 'CCCCCC' },
      left: { style: BorderStyle.SINGLE, size: 2, color: 'CCCCCC' },
      right: { style: BorderStyle.SINGLE, size: 2, color: 'CCCCCC' },
      insideHorizontal: { style: BorderStyle.SINGLE, size: 2, color: 'DDDDDD' },
      insideVertical: { style: BorderStyle.SINGLE, size: 2, color: 'DDDDDD' },
    },
    rows,
  });
}

const children = [];

children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 60 },
  children: [new TextRun({ text: 'CARE NET CONSULTANTS (PTY) LTD', bold: true, color: RED, font: FONT, size: 32 })],
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 40 },
  children: [new TextRun({ text: 'MEDICAL SURVEILLANCE PLAN: CLIENT ONBOARDING FORM', bold: true, color: CHARCOAL, font: FONT, size: 24 })],
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 200 },
  children: [new TextRun({ text: 'Digital intake, schema intake.v1. Your Partner in Workplace Health.', italics: true, color: CHARCOAL, font: FONT, size: 18 })],
}));
children.push(body('This form gathers the information Care Net Consultants (Pty) Ltd requires to design an accurate, client specific Medical Surveillance Plan for your organisation. Complete every section as fully as possible; where a section genuinely does not apply, leave it blank. Care Net designs your Plan based entirely on the information and documents you provide here and does not independently conduct your workplace risk assessment. Do not enter any employee identity number, name linked to a medical condition, or other personal information about an identifiable individual anywhere in this form.'));

for (const section of spec.sections) {
  children.push(heading(`${section.no}. ${section.title}`));
  if (section.intro) children.push(body(section.intro, { italics: true }));

  if (section.fields && section.fields.length) {
    children.push(fieldsTable(section.fields.map(f => fieldRow(
      f.label + (f.required ? ' (required)' : ''), f.name, f.type
    ))));
  }

  for (const rep of section.repeats || []) {
    children.push(subheading(rep.title));
    for (let i = 1; i <= rep.count; i++) {
      const rows = rep.fields.map(f => fieldRow(
        `${i}. ${f.label}${f.required_first && i === 1 ? ' (required)' : ''}`,
        `${rep.prefix}_${i}_${f.name}`, f.type
      ));
      children.push(fieldsTable(rows));
      children.push(new Paragraph({ spacing: { after: 60 }, children: [] }));
    }
  }
}

const doc = new Document({
  styles: { default: { document: { run: { font: FONT, size: 20, color: CHARCOAL } } } },
  sections: [{
    properties: {
      page: {
        size: { width: 11906, height: 16838 },
        margin: { top: 1080, bottom: 1080, left: 1080, right: 1080 },
      },
    },
    children,
  }],
});

// JSON Schema derivation for the webhook validator ------------------------------
const properties = {
  docuseal_submission_id: { type: 'string', minLength: 1 },
  schema_version: { const: spec.schema_version },
};
const required = ['docuseal_submission_id'];

function jsType(t) {
  if (t === 'number') return { type: ['string', 'number'] };
  if (t === 'checkbox') return { type: ['boolean', 'string'] };
  if (t === 'date') return { type: 'string' };
  if (t === 'file' || t === 'signature') return { type: ['string', 'object', 'array'] };
  return { type: 'string' };
}

for (const section of spec.sections) {
  for (const f of section.fields || []) {
    properties[f.name] = jsType(f.type);
    if (f.required) required.push(f.name);
  }
  for (const rep of section.repeats || []) {
    for (let i = 1; i <= rep.count; i++) {
      for (const f of rep.fields) {
        properties[`${rep.prefix}_${i}_${f.name}`] = jsType(f.type);
      }
    }
  }
}

const schema = {
  $id: 'cnc-msp-intake.v1',
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  type: 'object',
  additionalProperties: true,
  properties,
  required,
};

(async () => {
  const buf = await Packer.toBuffer(doc);
  fs.writeFileSync(path.join(__dirname, 'onboarding_form.docx'), buf);
  fs.writeFileSync(path.join(__dirname, 'schema.json'), JSON.stringify(schema, null, 2));
  const fieldCount = Object.keys(properties).length;
  console.log(`onboarding_form.docx written (${buf.length} bytes), schema.json with ${fieldCount} fields`);
})();
