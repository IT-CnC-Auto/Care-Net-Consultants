#!/usr/bin/env python3
"""Build the designer asset manifest from the pages' asset specification blocks.

CNC HSF FORGE | build contract section 6 | Version 1.0 | 23/09/2026

Every page in vercel/*.html carries one block

    <script type="application/json" id="cnc-asset-spec">
      {"page": "...", "assets": [{"id": ..., "block": ..., "purpose": ...,
        "type": ..., "formats": [...], "width": ..., "height": ...,
        "ratio": ..., "max_kb": ..., "colour": ..., "alt": ...,
        "file_name": ..., "delivery": ..., "status": ..., "notes": ...}]}
    </script>

and marks each slot on the page with data-asset="<id>". This script reads
every block and writes, from the repository root (msp-forge):

    DESIGNER-ASSETS.md          per page tables plus a combined checklist
    vercel/design/assets.json   the same data for tools

It prints a warning for every data-asset slot with no specification entry,
every specification entry with no slot, and every entry that breaks the
asset contract (unknown type or status, missing fields, delivery outside
img.carenetcdn.com or /assets/, and so on). Numbering is from 1 and
follows the same rules as /js/cnc-design-assets.js, so the numbers in the
manifest match the labels a designer sees with ?design=1.

Usage:
    python3 hsf/build_asset_manifest.py              write both outputs
    python3 hsf/build_asset_manifest.py --dry-run    report only, write nothing
    python3 hsf/build_asset_manifest.py --strict     exit 1 if there is any warning
    python3 hsf/build_asset_manifest.py --root DIR   use another msp-forge checkout

Standard library only. Output is deterministic (no timestamps), so a rerun
with no page changes leaves both files unchanged.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SPEC_ID = "cnc-asset-spec"
FIELDS = ["id", "block", "purpose", "type", "formats", "width", "height", "ratio",
          "max_kb", "colour", "alt", "file_name", "delivery", "status", "notes"]
REQUIRED = ["id", "block", "purpose", "type", "formats", "file_name", "delivery", "status"]
TYPES = ["photo", "illustration", "icon", "logo", "pattern", "video", "og_image", "document"]
TYPE_TITLES = {
    "photo": "Photographs", "illustration": "Illustrations", "icon": "Icons", "logo": "Logos",
    "pattern": "Patterns", "video": "Video", "og_image": "Social sharing images",
    "document": "Documents", "unknown": "Type not set",
}
STATUSES = ["existing", "needed"]
KNOWN_FORMATS = {"webp", "avif", "jpg", "jpeg", "png", "svg", "gif", "mp4", "webm",
                 "pdf", "ico", "docx", "xlsx", "json"}
RASTER_TYPES = {"photo", "illustration", "og_image", "video", "pattern"}
DELIVERY_OK = re.compile(r"^(https://)?img\.carenetcdn\.com/|^/assets/")
RATIO_OK = re.compile(r"^\d+(\.\d+)?:\d+(\.\d+)?$")
PROSE_FIELDS = ["block", "purpose", "alt", "notes", "colour"]

# Slots written by page scripts (markup built in JavaScript) are found here too.
SCRIPT_SLOT_PATTERNS = [
    re.compile(r"""data-asset\s*=\s*\\?["']([^"'\\]+)\\?["']"""),
    re.compile(r"""\.dataset\.asset\s*=\s*["']([^"']+)["']"""),
    re.compile(r"""setAttribute\(\s*["']data-asset["']\s*,\s*["']([^"']+)["']"""),
]
# Slots whose id is computed in script (for example data-asset="' + slug + '").
# Their ids cannot be read without running the page, so entries with no
# static slot on such a page are reported with a pointer to ?design=1.
SCRIPT_DYNAMIC_PATTERNS = [
    re.compile(r"""data-asset\s*=\s*\\?["']\s*["'`]\s*\+"""),
    re.compile(r"""data-asset\s*=\s*\\?["']\$\{"""),
    re.compile(r"""\.dataset\.asset\s*=\s*(?!["'][^"']+["'])"""),
    re.compile(r"""setAttribute\(\s*["']data-asset["']\s*,\s*(?!["'][^"']+["']\s*\))"""),
]


class PageParser(HTMLParser):
    """Collects the spec block(s) and every data-asset slot of one page."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.specs: list[dict] = []
        self.slots: list[dict] = []
        self.dynamic_slots = False
        self._script: dict | None = None

    def handle_starttag(self, tag, attrs):
        a = {k: (v if v is not None else "") for k, v in attrs}
        line = self.getpos()[0]
        if "data-asset" in a:
            self.slots.append({"id": a["data-asset"].strip(), "tag": tag, "line": line, "source": "markup"})
        if tag == "script":
            self._script = {
                "is_spec": a.get("id") == SPEC_ID,
                "type": a.get("type", "").strip().lower(),
                "line": line,
                "buf": [],
            }

    def handle_data(self, data):
        if self._script is not None:
            self._script["buf"].append(data)

    def handle_endtag(self, tag):
        if tag != "script" or self._script is None:
            return
        s = self._script
        self._script = None
        text = "".join(s["buf"])
        if s["is_spec"]:
            self.specs.append({"text": text, "type": s["type"], "line": s["line"]})
            return
        if any(p.search(text) for p in SCRIPT_DYNAMIC_PATTERNS):
            self.dynamic_slots = True
        for pat in SCRIPT_SLOT_PATTERNS:
            for m in pat.finditer(text):
                val = m.group(1).strip()
                # Skip template placeholders such as ' + id + ' or ${id}.
                if not val or "${" in val or "+" in val or "<" in val:
                    continue
                self.slots.append({"id": val, "tag": "script", "line": s["line"], "source": "script"})


def is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def check_asset(page: str, n: int, a: dict, warn) -> None:
    """Warn about anything in one entry that breaks the asset contract."""
    aid = a.get("id")
    where = f'{page}: asset {n} "{aid}"'
    for f in REQUIRED:
        v = a.get(f)
        if v is None or v == "" or v == []:
            warn(f"{where} has no {f}.")
    t = a.get("type")
    if t not in (None, "") and t not in TYPES:
        warn(f'{where} has type "{t}"; expected one of {", ".join(TYPES)}.')
    st = a.get("status")
    if st not in (None, "") and st not in STATUSES:
        warn(f'{where} has status "{st}"; expected existing or needed.')
    fm = a.get("formats")
    if fm not in (None, "", []):
        if not isinstance(fm, list) or not all(isinstance(x, str) and x.strip() for x in fm):
            warn(f"{where} formats must be a list of format names such as [\"webp\", \"jpg\"].")
        else:
            odd = [x for x in fm if x.lower().lstrip(".") not in KNOWN_FORMATS]
            if odd:
                warn(f"{where} lists formats this manifest does not recognise: {', '.join(odd)}.")
    for f in ("width", "height"):
        v = a.get(f)
        if v is not None and (not is_int(v) or v <= 0):
            warn(f"{where} {f} must be a whole number of pixels or null.")
    if t in RASTER_TYPES and (a.get("width") is None or a.get("height") is None):
        warn(f"{where} is a {t} with no width or height in pixels.")
    r = a.get("ratio")
    if r not in (None, "") and (not isinstance(r, str) or not RATIO_OK.match(r)):
        warn(f'{where} ratio "{r}" should read like 16:9.')
    mk = a.get("max_kb")
    if mk is not None and (not is_num(mk) or mk <= 0):
        warn(f"{where} max_kb must be a positive number of kilobytes or null.")
    dv = a.get("delivery")
    if isinstance(dv, str) and dv and not DELIVERY_OK.match(dv):
        warn(f'{where} delivery "{dv}" should start with img.carenetcdn.com/ or /assets/.')
    fn = a.get("file_name")
    if isinstance(fn, str) and fn and (re.search(r"\s", fn) or "/" in fn or "\\" in fn):
        warn(f'{where} file_name "{fn}" should be a bare file name with no spaces or folders.')
    for f in PROSE_FIELDS:
        v = a.get(f)
        if not isinstance(v, str):
            continue
        if "\u2014" in v or "\u2013" in v:
            warn(f"{where} {f} contains an em or en dash; the house style never uses them.")
        elif re.search(r"\s-\s", v):
            warn(f"{where} {f} uses a hyphen as punctuation; rephrase without it.")
        if re.search(r"\bcompliant\b", v, re.IGNORECASE):
            warn(f'{where} {f} uses the word "compliant"; the house style never claims it.')


def read_page(path: Path, rel: str, warn) -> dict:
    parser = PageParser()
    try:
        parser.feed(path.read_text(encoding="utf-8"))
        parser.close()
    except (UnicodeDecodeError, OSError) as e:
        warn(f"{rel}: could not be read ({e}).")
        return {"file": rel, "page": None, "spec_found": False, "assets": [], "slots_without_spec": []}

    page = {"file": rel, "page": None, "spec_found": False, "spec_line": None,
            "builds_slots_in_script": parser.dynamic_slots,
            "assets": [], "slots_without_spec": []}
    spec = None
    if not parser.specs:
        warn(f'{rel}: no asset specification block (script id "{SPEC_ID}").')
    else:
        if len(parser.specs) > 1:
            warn(f"{rel}: {len(parser.specs)} asset specification blocks; only the first is read.")
        block = parser.specs[0]
        page["spec_line"] = block["line"]
        if block["type"] != "application/json":
            warn(f'{rel}: the asset specification block should have type="application/json".')
        try:
            spec = json.loads(block["text"])
        except json.JSONDecodeError as e:
            warn(f"{rel}: the asset specification block is not valid JSON ({e.msg}, line {block['line'] + e.lineno - 1}).")
        if spec is not None and not isinstance(spec, dict):
            warn(f'{rel}: the asset specification block must be an object with "page" and "assets".')
            spec = None

    entries: list[dict] = []
    if spec is not None:
        page["spec_found"] = True
        page["page"] = spec.get("page") if isinstance(spec.get("page"), str) else None
        if not page["page"]:
            warn(f'{rel}: the specification has no "page" name.')
        raw = spec.get("assets")
        if not isinstance(raw, list):
            warn(f'{rel}: the specification has no "assets" list.')
            raw = []
        seen: set[str] = set()
        # Same skipping rules as cnc-design-assets.js so the numbers agree.
        for i, a in enumerate(raw, start=1):
            if not isinstance(a, dict):
                warn(f"{rel}: entry {i} is not an object and was skipped.")
                continue
            aid = "" if a.get("id") is None else str(a.get("id")).strip()
            if not aid:
                warn(f"{rel}: entry {i} has no id and was skipped.")
                continue
            if aid in seen:
                warn(f'{rel}: the id "{aid}" appears more than once; only the first entry is used.')
                continue
            seen.add(aid)
            entries.append({"n": len(entries) + 1, "id": aid, "data": a})

    slot_counts: dict[str, int] = {}
    slot_order: list[str] = []
    for s in parser.slots:
        if not s["id"]:
            warn(f"{rel}: line {s['line']}: a data-asset attribute is empty.")
            continue
        if s["id"] not in slot_counts:
            slot_order.append(s["id"])
            slot_counts[s["id"]] = 0
        slot_counts[s["id"]] += 1

    ids = {e["id"] for e in entries}
    for sid in slot_order:
        if sid not in ids:
            first = next(s for s in parser.slots if s["id"] == sid)
            how = "in page script" if first["source"] == "script" else f"<{first['tag']}>"
            warn(f'{rel}: slot "{sid}" ({how}, line {first["line"]}) has no specification entry.')
            page["slots_without_spec"].append(sid)

    for e in entries:
        a = e["data"]
        check_asset(rel, e["n"], a, warn)
        if e["id"] not in slot_counts:
            if parser.dynamic_slots:
                warn(f'{rel}: asset {e["n"]} "{e["id"]}" has no slot in the markup. The page builds some '
                     f'data-asset slots in script, so confirm this one with ?design=1.')
            else:
                warn(f'{rel}: asset {e["n"]} "{e["id"]}" has no slot on the page (no element with data-asset="{e["id"]}").')
        out = {"n": e["n"]}
        for f in FIELDS:
            out[f] = e["id"] if f == "id" else a.get(f)
        for k in a:
            if k not in FIELDS:
                out[k] = a[k]
        out["slot_count"] = slot_counts.get(e["id"], 0)
        page["assets"].append(out)
    return page


# ------------------------------------------------------------------ writers

def cell(v) -> str:
    if v is None or v == "" or v == []:
        return ""
    if isinstance(v, list):
        v = ", ".join(str(x) for x in v)
    elif isinstance(v, (dict, bool)):
        v = json.dumps(v, ensure_ascii=False)
    s = re.sub(r"\s+", " ", str(v)).strip()
    return s.replace("\\", "\\\\").replace("|", "\\|")


def code(v) -> str:
    s = cell(v)
    return f"`{s}`" if s else ""


def size(a: dict) -> str:
    w, h = a.get("width"), a.get("height")
    if w is None and h is None:
        return ""
    return f"{w if w is not None else 'any'} \u00d7 {h if h is not None else 'any'}"


def title_of(p: dict) -> str:
    return p["page"] or p["file"]


def build_markdown(pages: list[dict], warnings: list[str], totals: dict) -> str:
    L: list[str] = []
    L.append("# Care Net designer asset list")
    L.append("")
    L.append("Generated by `hsf/build_asset_manifest.py` from the asset specification block on every page in "
             "`vercel/*.html`. Do not edit this file by hand: change the block on the page and run "
             "`python3 hsf/build_asset_manifest.py` again. The same data is in `vercel/design/assets.json`.")
    L.append("")
    L.append("## How to use this list")
    L.append("")
    L.append("1. Open any page with `?design=1` at the end of the address (or `#design`). Every asset slot "
             "is outlined and numbered, and a panel lists each asset's full specification with a button "
             "that copies it as JSON.")
    L.append("2. The numbers in this list match the numbers on the page.")
    L.append("3. Supply every format listed for an asset, at the pixel size shown, and keep each file at or "
             "under its maximum size.")
    L.append("4. Name each file exactly as shown under File name and deliver it to the path under Delivery.")
    L.append("5. Alt text is written by Care Net. It is listed so the picture matches the words that "
             "describe it.")
    L.append("6. Status Needed means the asset does not exist yet. Existing means it is live and is listed "
             "for reference.")
    L.append("")
    L.append("## Summary")
    L.append("")
    L.append(f"{totals['pages']} pages read, {totals['pages_with_spec']} with a specification block. "
             f"{totals['assets']} assets in total: {totals['needed']} needed, {totals['existing']} existing. "
             f"{totals['warnings']} warnings.")
    L.append("")
    L.append("| No. | Page | File | Assets | Needed | Existing |")
    L.append("| --- | --- | --- | --- | --- | --- |")
    for i, p in enumerate(pages, start=1):
        need = sum(1 for a in p["assets"] if a.get("status") == "needed")
        have = sum(1 for a in p["assets"] if a.get("status") == "existing")
        name = cell(title_of(p)) if p["spec_found"] else "No specification block yet"
        L.append(f"| {i} | {name} | `{p['file']}` | {len(p['assets'])} | {need} | {have} |")
    L.append("")

    L.append("## Pages")
    L.append("")
    for i, p in enumerate(pages, start=1):
        if not p["spec_found"]:
            L.append(f"### {i}. `{p['file']}`")
            L.append("")
            L.append("This page has no asset specification block yet.")
            L.append("")
            continue
        L.append(f"### {i}. {cell(title_of(p))} (`{p['file']}`)")
        L.append("")
        if not p["assets"]:
            L.append("The specification lists no assets.")
            L.append("")
        else:
            L.append("| No. | ID | Block | Purpose | Type | Formats | Size (px) | Ratio | Max KB | Colour | "
                     "Alt text | File name | Delivery | Status | Notes |")
            L.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
            for a in p["assets"]:
                notes = cell(a.get("notes"))
                if a["slot_count"] == 0:
                    notes = (notes + " " if notes else "") + (
                        "**No slot in the markup; the page builds some slots in script, so check with ?design=1.**"
                        if p.get("builds_slots_in_script") else "**No slot on the page yet.**")
                L.append("| " + " | ".join([
                    str(a["n"]), code(a["id"]), cell(a.get("block")), cell(a.get("purpose")),
                    cell(a.get("type")), cell(a.get("formats")), size(a), cell(a.get("ratio")),
                    cell(a.get("max_kb")), cell(a.get("colour")), cell(a.get("alt")),
                    code(a.get("file_name")), code(a.get("delivery")),
                    "Needed" if a.get("status") == "needed" else ("Existing" if a.get("status") == "existing" else cell(a.get("status"))),
                    notes,
                ]) + " |")
            L.append("")
        if p["slots_without_spec"]:
            L.append("Slots marked on this page with no specification entry: "
                     + ", ".join(f"`{cell(s)}`" for s in p["slots_without_spec"]) + ".")
            L.append("")

    def line_for(p: dict, a: dict) -> str:
        bits = []
        s = size(a)
        if s:
            bits.append(s + " px")
        if a.get("ratio"):
            bits.append(cell(a["ratio"]))
        if a.get("formats"):
            bits.append(cell(a["formats"]))
        if a.get("max_kb") is not None:
            bits.append(f"at most {cell(a['max_kb'])} KB")
        spec = "; ".join(bits)
        fn = code(a.get("file_name")) or "file name not set"
        dv = code(a.get("delivery")) or "delivery path not set"
        return (f"{fn} for {cell(title_of(p))} (`{p['file']}`), asset {a['n']} {code(a['id'])}"
                + (f": {spec}" if spec else "") + f". Deliver to {dv}.")

    def grouped(status: str) -> list[tuple[str, list[tuple[dict, dict]]]]:
        groups: dict[str, list] = {}
        for p in pages:
            for a in p["assets"]:
                if a.get("status") != status:
                    continue
                t = a.get("type") if a.get("type") in TYPES else "unknown"
                groups.setdefault(t, []).append((p, a))
        order = TYPES + ["unknown"]
        return [(t, groups[t]) for t in order if t in groups]

    L.append("## Combined checklist: assets still needed")
    L.append("")
    need_groups = grouped("needed")
    if not need_groups:
        L.append("Nothing is marked as needed.")
        L.append("")
    k = 0
    for t, items in need_groups:
        L.append(f"### {TYPE_TITLES[t]}")
        L.append("")
        for p, a in items:
            k += 1
            L.append(f"{k}. [ ] {line_for(p, a)}")
        L.append("")

    L.append("## Existing assets (for reference)")
    L.append("")
    have_groups = grouped("existing")
    if not have_groups:
        L.append("No asset is marked as existing.")
        L.append("")
    k = 0
    for t, items in have_groups:
        L.append(f"### {TYPE_TITLES[t]}")
        L.append("")
        for p, a in items:
            k += 1
            L.append(f"{k}. {line_for(p, a)}")
        L.append("")

    other = [(p, a) for p in pages for a in p["assets"] if a.get("status") not in STATUSES]
    if other:
        L.append("## Assets with no status")
        L.append("")
        for i, (p, a) in enumerate(other, start=1):
            L.append(f"{i}. {line_for(p, a)}")
        L.append("")

    L.append("## Warnings")
    L.append("")
    if not warnings:
        L.append("None.")
    else:
        for i, w in enumerate(warnings, start=1):
            L.append(f"{i}. {cell(w)}")
    L.append("")
    return "\n".join(L)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Build DESIGNER-ASSETS.md and vercel/design/assets.json "
                                             "from the asset specification blocks in vercel/*.html.")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                    help="the msp-forge folder (default: the parent of this script's folder)")
    ap.add_argument("--dry-run", action="store_true", help="report only; write nothing")
    ap.add_argument("--strict", action="store_true", help="exit with status 1 if there is any warning")
    args = ap.parse_args(argv)

    root = args.root.resolve()
    web = root / "vercel"
    if not web.is_dir():
        print(f"ERROR: {web} is not a folder.", file=sys.stderr)
        return 2

    warnings: list[str] = []

    def warn(msg: str) -> None:
        warnings.append(msg)
        print(f"WARNING: {msg}", file=sys.stderr)

    pages = [read_page(p, p.name, warn) for p in sorted(web.glob("*.html"))]

    totals = {
        "pages": len(pages),
        "pages_with_spec": sum(1 for p in pages if p["spec_found"]),
        "assets": sum(len(p["assets"]) for p in pages),
        "needed": sum(1 for p in pages for a in p["assets"] if a.get("status") == "needed"),
        "existing": sum(1 for p in pages for a in p["assets"] if a.get("status") == "existing"),
        "warnings": len(warnings),
    }

    manifest = {
        "schema": "cnc-asset-manifest/1",
        "generated_by": "hsf/build_asset_manifest.py",
        "source": "vercel/*.html, script#cnc-asset-spec and [data-asset] slots",
        "totals": totals,
        "pages": [{k: v for k, v in p.items() if k != "spec_line"} for p in pages],
        "warnings": warnings,
    }
    md = build_markdown(pages, warnings, totals)

    print(f"{totals['pages']} pages, {totals['pages_with_spec']} with a specification block, "
          f"{totals['assets']} assets ({totals['needed']} needed, {totals['existing']} existing), "
          f"{totals['warnings']} warnings.")

    if not args.dry_run:
        out_md = root / "DESIGNER-ASSETS.md"
        out_json = web / "design" / "assets.json"
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_md.write_text(md, encoding="utf-8")
        out_json.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {out_md.relative_to(root)} and {out_json.relative_to(root)}.")
    else:
        print("Dry run: nothing written.")

    return 1 if (args.strict and warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
