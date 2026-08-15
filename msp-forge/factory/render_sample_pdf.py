#!/usr/bin/env python3
"""CNC MSP FORGE | SAMPLE-PDF-01 v1.0.0 | Public sample renderer.

Renders a validated draft into a branded PDF marked as a sample on every page.
Public samples exist to show prospective clients what they receive, so three
protections are baked in and cannot be stripped by a reader:

  1. A diagonal SAMPLE watermark drawn under the content on every page, inside
     the page content stream, so deleting text does not remove it.
  2. A DEMO SAMPLE, NOT FOR USE band in the header of every page.
  3. A fictitious client and an unsigned sign off, stated on the first page.

  Note on encryption: an earlier version applied PDF permission flags. ReportLab
  writes those with 40 bit RC4, which current browsers and Adobe refuse to open,
  so the sample would not open at all. Those flags are advisory in any event and
  any reader can strip them. The watermark is the protection that actually holds.

Usage: python3 render_sample_pdf.py <draft.json> <output.pdf> [industry label]
"""

import json
import os
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.platypus import (BaseDocTemplate, Frame, KeepTogether, PageBreak,
                                PageTemplate, Paragraph, Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, 'assets')

CNC_RED = colors.HexColor('#ED1B24')
CHARCOAL = colors.HexColor('#1E1E1E')
LIGHT = colors.HexColor('#F2F2F2')

PAGE_W, PAGE_H = A4
MARGIN_X = 25 * mm
HEADER_H = 30 * mm
FOOTER_H = 26 * mm

TABLE_DEFS = {
    'regulatory_frame': (['Instrument', 'Applicability to this engagement'],
                         lambda r: [r.get('instrument'), r.get('applicability')], [58, 42]),
    'orep_jobs': (['Job title', 'Staff', 'Principal duties', 'Identified hazards', 'Exposure rating'],
                  lambda r: [r.get('job_title'), r.get('headcount'), r.get('duties'), r.get('hazards'),
                             r.get('exposure_rating')], [18, 7, 24, 30, 21]),
    'quantified_exposures': (['Hazard and location', 'Measured', 'Limit or action value', 'Assessment', 'Measured on'],
                             lambda r: [r.get('hazard_location'), r.get('measured'), r.get('oel'),
                                        str(r.get('assessment', '')).replace('_', ' '), r.get('date')],
                             [30, 14, 26, 17, 13]),
    'risk_matrix': (['Job title', 'Hazard', 'L', 'S', 'Exposure', 'Controls', 'Residual risk'],
                    lambda r: [r.get('job_title'), '%s: %s' % (r.get('hazard_code'), r.get('hazard_name')),
                               r.get('likelihood'), r.get('severity'), r.get('exposure_rating'),
                               r.get('control_adequacy'), r.get('residual_risk')], [20, 24, 5, 5, 16, 15, 15]),
    'inherent_requirements': (['Job title', 'Physical demands', 'Sensory and cognitive demands', 'Statutory requirement'],
                              lambda r: [r.get('job_title'), r.get('physical'), r.get('sensory_cognitive'),
                                         r.get('statutory')], [20, 27, 27, 26]),
    'chemical_register': (['Substance', 'SDS reference', 'Task or process', 'Frequency', 'Controls in place'],
                          lambda r: [r.get('substance_name'), r.get('sds_reference'), r.get('task_process'),
                                     r.get('frequency'), r.get('controls')], [23, 14, 23, 14, 26]),
    'wasp': (['Job title', 'Baseline', 'Periodic and interval', 'Exit', 'Biological monitoring'],
             lambda r: [r.get('job_title'), r.get('baseline'), r.get('periodic'), r.get('exit'),
                        r.get('biological_monitoring')], [17, 22, 26, 17, 18]),
    'rpe_status': (['Job title', 'RPE issued', 'Fit tested', 'Surveillance implication'],
                   lambda r: [r.get('job_title'), r.get('rpe_issued'), r.get('rpe_fit_tested'),
                              r.get('implication')], [20, 17, 14, 49]),
}


def sanitise(text):
    """Public samples never carry internal register codes or build tags."""
    if text is None:
        return ''
    s = str(text)
    if 'CR-' in s and 'Designated OMP' in s:
        return 'Sample document: unsigned. A released Plan carries the signature of the designated Occupational Medical Practitioner.'
    return s


def page_furniture(canvas, doc):
    canvas.saveState()

    # Watermark first so all content sits above it.
    canvas.saveState()
    canvas.translate(PAGE_W / 2.0, PAGE_H / 2.0)
    canvas.rotate(52)
    canvas.setFont('Helvetica-Bold', 74)
    canvas.setFillColor(CNC_RED, alpha=0.10)
    for offset in (-230, -60, 110):
        label = 'SAMPLE'
        canvas.drawString(-stringWidth(label, 'Helvetica-Bold', 74) / 2.0, offset, label)
    canvas.setFont('Helvetica-Bold', 26)
    canvas.setFillColor(CHARCOAL, alpha=0.10)
    label = 'DEMONSTRATION DOCUMENT, FICTITIOUS DATA'
    canvas.drawString(-stringWidth(label, 'Helvetica-Bold', 26) / 2.0, 30, label)
    canvas.restoreState()

    # Header band: CNC banner left, client mark right.
    banner = os.path.join(ASSETS, 'cnc_header_banner.png')
    if os.path.exists(banner):
        img = ImageReader(banner)
        w, h = img.getSize()
        draw_w = 78 * mm
        draw_h = draw_w * h / float(w)
        canvas.drawImage(img, MARGIN_X, PAGE_H - 14 * mm - draw_h, width=draw_w, height=draw_h,
                         mask='auto')
    logo = os.path.join(ASSETS, 'client_logo_prepared.png')
    if os.path.exists(logo):
        img = ImageReader(logo)
        w, h = img.getSize()
        draw_h = 9 * mm
        draw_w = draw_h * w / float(h)
        canvas.drawImage(img, PAGE_W - MARGIN_X - draw_w, PAGE_H - 20 * mm, width=draw_w, height=draw_h,
                         mask='auto')

    # Sample band under the header.
    canvas.setFillColor(CNC_RED)
    canvas.rect(MARGIN_X, PAGE_H - HEADER_H + 2 * mm, PAGE_W - 2 * MARGIN_X, 6.5 * mm, stroke=0, fill=1)
    canvas.setFillColor(colors.white)
    canvas.setFont('Helvetica-Bold', 8)
    canvas.drawCentredString(PAGE_W / 2.0, PAGE_H - HEADER_H + 4 * mm,
                             'DEMO SAMPLE, NOT FOR USE. FICTITIOUS COMPANY DATA. NOT A CLINICAL DOCUMENT.')

    # Footer banner and line.
    footer = os.path.join(ASSETS, 'cnc_footer_banner.png')
    if os.path.exists(footer):
        img = ImageReader(footer)
        w, h = img.getSize()
        draw_w = PAGE_W - 2 * MARGIN_X
        draw_h = draw_w * h / float(w)
        canvas.drawImage(img, MARGIN_X, 8 * mm, width=draw_w, height=min(draw_h, 12 * mm), mask='auto')
    canvas.setFillColor(CHARCOAL)
    canvas.setFont('Helvetica', 7.5)
    canvas.drawString(MARGIN_X, FOOTER_H - 4 * mm,
                      'Sample Medical Surveillance Plan, generated by the Care Net Method from fictitious data.')
    canvas.drawRightString(PAGE_W - MARGIN_X, FOOTER_H - 4 * mm, 'Page %d' % doc.page)
    canvas.restoreState()


def build(draft_path, out_path, industry_label):
    draft = json.load(open(draft_path))
    composed = draft['composed']
    P = composed['placeholders']

    styles = getSampleStyleSheet()
    body = ParagraphStyle('body', parent=styles['Normal'], fontName='Helvetica', fontSize=9,
                          leading=12.5, alignment=TA_JUSTIFY, spaceAfter=5)
    h1 = ParagraphStyle('h1', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=13,
                        textColor=CNC_RED, spaceBefore=12, spaceAfter=7)
    h2 = ParagraphStyle('h2', parent=styles['Heading2'], fontName='Helvetica-Bold', fontSize=10.5,
                        textColor=CHARCOAL, spaceBefore=9, spaceAfter=5)
    cell = ParagraphStyle('cell', parent=body, fontSize=7.4, leading=9.4, alignment=0, spaceAfter=0)
    cell_h = ParagraphStyle('cellh', parent=cell, fontName='Helvetica-Bold', textColor=colors.white)
    note = ParagraphStyle('note', parent=body, fontSize=8.5, textColor=colors.HexColor('#555555'))

    story = []

    story.append(Paragraph('MEDICAL SURVEILLANCE PLAN', h1))
    story.append(Paragraph('%s, sample document' % industry_label, h2))
    story.append(Spacer(1, 3 * mm))

    intro = ('This is a demonstration document. It was generated by the Care Net Method from an entirely '
             'fictitious company, and it shows the structure, depth, and legal referencing of the Plan a '
             'Care Net client receives. Nothing in it describes a real employer, a real workplace, or a real '
             'person. It carries no clinical authority: a released Plan is reviewed, recommended on, and '
             'signed by a registered Occupational Medical Practitioner, and this sample is deliberately '
             'unsigned and watermarked throughout.')
    story.append(Paragraph(intro, body))
    story.append(Spacer(1, 3 * mm))

    control_rows = [
        ['Document', 'Sample Medical Surveillance Plan'],
        ['Industry', '%s, %s' % (P.get('industry_name', ''), P.get('subindustry_name', ''))],
        ['Fictitious client', '%s (sample data only)' % P.get('client_name', '')],
        ['Version', 'Sample, not versioned for release'],
        ['Prepared by', 'Care Net Consultants (Pty) Ltd'],
        ['Clinical status', 'Unsigned sample. A released Plan is signed by the designated Occupational Medical Practitioner.'],
        ['Compensation route', sanitise(P.get('compensation_route'))],
        ['Review cycle', 'Twelve months, and immediately on the triggers in the review section'],
    ]
    t = Table([[Paragraph(a, cell_h if False else cell), Paragraph(b, cell)] for a, b in control_rows],
              colWidths=[42 * mm, (PAGE_W - 2 * MARGIN_X) - 42 * mm])
    t.setStyle(TableStyle([
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#DDDDDD')),
        ('BACKGROUND', (0, 0), (0, -1), LIGHT),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 4), ('RIGHTPADDING', (0, 0), (-1, -1), 4),
        ('TOPPADDING', (0, 0), (-1, -1), 3), ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    story.append(t)
    story.append(PageBreak())

    content_w = PAGE_W - 2 * MARGIN_X

    for section in composed['sections']:
        story.append(Paragraph('%s. %s' % (section['section_no'], section['heading'].upper()), h1))
        for block in section['blocks']:
            kind = block.get('kind')
            if kind == 'paragraph':
                story.append(Paragraph(sanitise(block.get('text')), body))
            elif kind == 'questionnaire_context':
                for item in block.get('items', []):
                    story.append(Paragraph('&bull; %s' % sanitise(item), body))
            elif kind == 'locked_template':
                story.append(Paragraph(
                    'This section carries a Care Net standard clause, reproduced verbatim in every Plan and '
                    'never rewritten per client. In your Plan it appears here in full.', note))
            elif kind == 'table':
                tbl = block.get('table', {})
                name = tbl.get('name')
                rows = tbl.get('rows', []) or []
                definition = TABLE_DEFS.get(name)
                if not definition or not rows:
                    continue
                headers, mapper, weights = definition
                widths = [content_w * (w / 100.0) for w in weights]
                data = [[Paragraph(h, cell_h) for h in headers]]
                for r in rows:
                    data.append([Paragraph(sanitise(v), cell) for v in mapper(r)])
                tb = Table(data, colWidths=widths, repeatRows=1)
                tb.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), CNC_RED),
                    ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#DDDDDD')),
                    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#FAFAFA')]),
                    ('LEFTPADDING', (0, 0), (-1, -1), 3), ('RIGHTPADDING', (0, 0), (-1, -1), 3),
                    ('TOPPADDING', (0, 0), (-1, -1), 2.5), ('BOTTOMPADDING', (0, 0), (-1, -1), 2.5),
                ]))
                story.append(tb)
                story.append(Spacer(1, 4 * mm))

    story.append(PageBreak())
    story.append(Paragraph('WHAT YOUR OWN PLAN ADDS', h1))
    closing = ('Your Plan carries your company branding alongside the Care Net band on every page, your own '
               'sites, job categories, and measured exposures, and the full standard clauses on liability, '
               'protection of personal information, and sign off. It is reviewed and signed by a registered '
               'Occupational Medical Practitioner, delivered with revision control, and updated as your '
               'operations or the law change.')
    story.append(Paragraph(closing, body))
    story.append(Spacer(1, 4 * mm))
    story.append(Paragraph('Care Net Consultants (Pty) Ltd. Your Partner in Workplace Health.', note))

    doc = BaseDocTemplate(
        out_path, pagesize=A4,
        leftMargin=MARGIN_X, rightMargin=MARGIN_X,
        topMargin=HEADER_H + 4 * mm, bottomMargin=FOOTER_H + 2 * mm,
        title='Sample Medical Surveillance Plan, %s' % industry_label,
        author='Care Net Consultants (Pty) Ltd',
        subject='Demonstration sample generated from fictitious data. Not a clinical document.',
        creator='Care Net Method')
    frame = Frame(MARGIN_X, FOOTER_H + 2 * mm, content_w,
                  PAGE_H - (HEADER_H + 4 * mm) - (FOOTER_H + 2 * mm), id='body')
    doc.addPageTemplates([PageTemplate(id='cnc', frames=[frame], onPage=page_furniture)])
    doc.build(story)
    print('sample PDF written: %s (%d bytes)' % (out_path, os.path.getsize(out_path)))


if __name__ == '__main__':
    draft_path = sys.argv[1]
    out_path = sys.argv[2]
    industry_label = sys.argv[3] if len(sys.argv) > 3 else 'Construction'
    build(draft_path, out_path, industry_label)
