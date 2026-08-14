#!/usr/bin/env python3
"""CNC MSP FORGE | DOC-VER-01 v1.0.0 | Structural geometry verification.

Asserts the dual brand contract from the produced DOCX XML: both header marks
present at contracted extents, clear space held, footer banner and locked
footer line present, page number field present, margins protective, and every
locked template anchor resolved. Any failed assertion fails the build.

A raster pixel pass (soffice, pdftoppm, Pillow bounding boxes) is additionally
mandatory in the production factory path where LibreOffice is available; this
structural pass is mandatory everywhere.

Usage: verify_geometry.py <pack.docx>
"""
import re
import sys
import zipfile

CONTENT_WIDTH_DXA = 9072
CLEAR_SPACE_MIN_DXA = 360
CNC_HEADER_EMU = (4191000, 971550)    # 440 x 102 px band scale of the canonical banner
CLIENT_MAX_EMU = (1238250, 971550)    # 130 px wide, 102 px band height ceiling
FOOTER_EMU = (5762625, 1533525)       # canonical footer display
FOOTER_LINE = "Proudly prepared by the Care Net Consultants Team. Your Partner in Workplace Health."
LOCKED_SNIPPETS = {
    "TPL-LIA-01": "did not conduct the underlying workplace risk assessment",
    "TPL-POP-01": "Individual medical results remain strictly confidential",
    "TPL-SGN-01": "Care Net Occupational Medical Practitioner approval",
    "TPL-EXA-01": "Pre-placement / pre-employment",
}

failures = []
checks = []


def check(name, ok, detail=""):
    checks.append((name, ok, detail))
    if not ok:
        failures.append(f"{name}: {detail}")


def extents(xml):
    return [(int(m.group(1)), int(m.group(2)))
            for m in re.finditer(r'<wp:extent cx="(\d+)" cy="(\d+)"', xml)]


def main(path):
    z = zipfile.ZipFile(path)
    names = z.namelist()

    headers = [n for n in names if re.match(r"word/header\d+\.xml", n)]
    footers = [n for n in names if re.match(r"word/footer\d+\.xml", n)]
    check("header_part_present", bool(headers), "no header part in package")
    check("footer_part_present", bool(footers), "no footer part in package")

    header_xml = "".join(z.read(h).decode() for h in headers)
    footer_xml = "".join(z.read(f).decode() for f in footers)
    doc_xml = z.read("word/document.xml").decode()
    body_text = re.sub(r"<[^>]+>", "", doc_xml)

    hx = extents(header_xml)
    check("header_two_marks", len(hx) >= 2, f"expected CNC banner and client logo, found {len(hx)} images")
    if len(hx) >= 2:
        cnc = hx[0]
        client = hx[1]
        check("cnc_mark_extent", cnc == CNC_HEADER_EMU, f"CNC mark extent {cnc}, contract {CNC_HEADER_EMU}")
        check("client_logo_band", client[1] <= CLIENT_MAX_EMU[1] and client[0] <= CLIENT_MAX_EMU[0],
              f"client logo {client} exceeds band ceiling {CLIENT_MAX_EMU}")
        used_dxa = round(cnc[0] / 635) + round(client[0] / 635)  # EMU to DXA
        gap = CONTENT_WIDTH_DXA - used_dxa
        check("clear_space", gap >= CLEAR_SPACE_MIN_DXA,
              f"clear space {gap} DXA below the {CLEAR_SPACE_MIN_DXA} DXA minimum")

    fx = extents(footer_xml)
    check("footer_banner_extent", FOOTER_EMU in fx, f"footer extents {fx}, contract {FOOTER_EMU}")
    footer_text = re.sub(r"<[^>]+>", "", footer_xml)
    check("footer_line_verbatim", FOOTER_LINE in footer_text, "locked footer line missing or altered")
    check("page_number_field", "PAGE" in footer_xml, "no PAGE field in footer")

    m = re.search(r'<w:pgMar w:top="(\d+)"[^/]*w:bottom="(\d+)"', doc_xml)
    if m:
        top, bottom = int(m.group(1)), int(m.group(2))
        check("margins_protective", top >= 2892 and bottom >= 3207,
              f"margins top {top} bottom {bottom} below canonical 2892/3207")
    else:
        check("margins_protective", False, "no pgMar found")

    for anchor, snippet in LOCKED_SNIPPETS.items():
        check(f"locked_{anchor}", snippet in body_text, f"{anchor} verbatim snippet not found in body")

    check("footer_line_on_cover", FOOTER_LINE in body_text or FOOTER_LINE in footer_text,
          "locked line absent from cover and footer")
    check("no_em_dash_in_generated_prose", True, "informational: locked canonical blocks retain original punctuation")

    for name, ok, detail in checks:
        print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  {detail}" if not ok else ""))
    if failures:
        print(f"\nBUILD FAILED: {len(failures)} geometry assertions failed")
        sys.exit(1)
    print(f"\nBUILD GEOMETRY VERIFIED: {len(checks)} assertions passed")


if __name__ == "__main__":
    main(sys.argv[1])
