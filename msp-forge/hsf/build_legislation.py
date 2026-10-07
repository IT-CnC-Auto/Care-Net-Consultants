#!/usr/bin/env python3
"""Build the data behind vercel/legislation.html (contract 12.7).

CNC HSF FORGE | HSF-LEG-BUILD-01 v1.0.0 | 24/09/2026

Reads
    hsf/legislation/backgrounds.json   plain words background per instrument
    hsf/sample-file/instruments.json   the kernel status of each instrument in
                                       this repository (status, scope, hold)
and writes
    vercel/hsf/legislation.js          window.CNC_LEGISLATION: every entry with
                                       its background and the static fallback
                                       status the page shows when the live
                                       register cannot be reached
    vercel/hsf/legislation-index.js    window.CNC_LEGISLATION_INDEX: slug and
                                       names only, for the links from the File
                                       pages to /legislation.html#<slug>

The page reads the live register (msp_public_instrument_register) and only
falls back to the status embedded here. Status keys, and the exact wording the
page shows for each:
    verified   Verified through the kernel's three checks
               (only a verified instrument whose scope covers health and safety)
    medical    Verified for medical surveillance; awaiting verification for
               health and safety provisions
    candidate  Candidate, awaiting verification
    held       Held from citation while a Gazette detail is confirmed

Contract section 7: the Noise Exposure Regulations, 2024 and the Physical
Agents Regulations, 2024 are named on static pages only once register item
HSF-7 is closed. While HSF7_CLOSED is False their entries keep their anchors
(so links resolve) but show a neutral heading instead of the name, and their
fallback status is "candidate", because the live kernel does not hold them yet.

The generator refuses to write if an instrument has no background, a
background has no instrument, a slug repeats, or any visible text breaks the
writing rules of contract 12.2.

Usage: python3 hsf/build_legislation.py [--check]
Standard library only; the output is deterministic.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKGROUNDS = ROOT / 'hsf' / 'legislation' / 'backgrounds.json'
INSTRUMENTS = ROOT / 'hsf' / 'sample-file' / 'instruments.json'
OUT_FULL = ROOT / 'vercel' / 'hsf' / 'legislation.js'
OUT_INDEX = ROOT / 'vercel' / 'hsf' / 'legislation-index.js'

# Register item HSF-7 (migration 042 not applied to the live project). Set to
# True only when the register records HSF-7 as closed.
HSF7_CLOSED = False
HSF7 = {
    'noise-exposure-regulations-2024': 'Noise exposure at work (new regulations)',
    'physical-agents-regulations-2024': 'Physical agents at work (new regulations)',
}

STATUS_TEXT = {
    'verified': "Verified through the kernel's three checks",
    'medical': 'Verified for medical surveillance; awaiting verification for health and safety provisions',
    'candidate': 'Candidate, awaiting verification',
    'held': 'Held from citation while a Gazette detail is confirmed',
}
SECTIONS = set('ABCDEFGHIJKLMNO')


def fallback_status(inst: dict) -> str:
    if inst.get('held'):
        return 'held'
    if inst.get('status') == 'verified':
        return 'verified' if inst.get('scope') in ('safety', 'both') else 'medical'
    return 'candidate'


def text_problems(label: str, text: str) -> list[str]:
    bad = []
    if re.search(r'[–—]| - ', text):
        bad.append('dash punctuation')
    if re.search(r'\bcompliant\b|guarantee', text, re.I):
        bad.append('"compliant" or "guarantee"')
    if re.search(r'SharePoint|GoHighLevel|Make\.com|Firebase|Supabase|MyClinic(?!Online)', text):
        bad.append('an internal platform name')
    if re.search(r'NIHL|Environmental Regulations for Workplaces', text):
        bad.append('a repealed instrument')
    stripped = re.sub(r'section (16\([12]\)|37\(2\))', '', text, flags=re.I)
    if re.search(r'\b(section|regulation|reg\.|annexure|gazette|GN)\s*R?\.?\s*\d', stripped, re.I):
        bad.append('a provision or Gazette number')
    if re.search(r'\bR\d{2,}\b', stripped):
        bad.append('a regulation notice number')
    return [label + ': ' + b for b in bad]


def aliases(*names: str) -> list[str]:
    """Names to link in page text: each name, and each name without its year."""
    out: list[str] = []
    for n in names:
        if not n:
            continue
        for v in (n, re.sub(r',\s*\d{4}$', '', n)):
            v = v.strip()
            # A kernel short name carrying a provision or notice number is never
            # shown on a page, so it is never a link target either.
            if len(v) < 4 or re.search(r'section \d|\bR\d{2,}', v):
                continue
            if v not in out:
                out.append(v)
    return out


def main() -> int:
    bg = json.loads(BACKGROUNDS.read_text(encoding='utf-8'))
    inst = json.loads(INSTRUMENTS.read_text(encoding='utf-8'))
    by_short = {i['short_name']: i for i in inst['instruments']}
    errors: list[str] = []

    seen_slug: set[str] = set()
    entries, index = [], []
    for b in bg['instruments']:
        slug, short = b['slug'], b['short_name']
        if not re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', slug):
            errors.append(slug + ': slug must be lower case words joined by hyphens')
        if slug in seen_slug:
            errors.append(slug + ': slug repeats')
        seen_slug.add(slug)
        k = by_short.get(short)
        if not k:
            errors.append(slug + ': no instrument in instruments.json has the short name ' + repr(short))
            continue
        withheld = (not HSF7_CLOSED) and slug in HSF7
        heading = HSF7[slug] if withheld else b['display_name']
        visible = [heading, b['what_it_covers'], b['who_it_applies_to']] + list(b['evidence_a_company_keeps'])
        for n, t in enumerate(visible):
            errors += text_problems(slug + ' text ' + str(n + 1), t)
        if not withheld:
            errors += text_problems(slug + ' name', b['display_name'])
        secs = [s for s in b.get('file_sections', []) if s in SECTIONS]
        if len(secs) != len(b.get('file_sections', [])):
            errors.append(slug + ': unknown File section')
        status = 'candidate' if withheld else fallback_status(k)
        entries.append({
            'slug': slug,
            'name': heading,
            'withheld': withheld,
            'short_name': short,
            'what_it_covers': b['what_it_covers'],
            'who_it_applies_to': b['who_it_applies_to'],
            'evidence': b['evidence_a_company_keeps'],
            'sections': secs,
            'fallback': {'status': status, 'verified_on': k.get('verified_on') if status in ('verified', 'medical') else None},
        })
        index.append({'slug': slug, 'names': aliases(b['display_name'], short)})

    shorts = {b['short_name'] for b in bg['instruments']}
    for i in inst['instruments']:
        if i['short_name'] not in shorts:
            errors.append('instrument ' + repr(i['short_name']) + ' has no background')

    # A name may only point at one instrument.
    owner: dict[str, str] = {}
    for e in index:
        for n in list(e['names']):
            if n in owner and owner[n] != e['slug']:
                errors.append('name ' + repr(n) + ' is shared by ' + owner[n] + ' and ' + e['slug'])
            owner[n] = e['slug']

    if errors:
        print('build_legislation.py refused to write:', file=sys.stderr)
        for e in errors:
            print('  ' + e, file=sys.stderr)
        return 1

    entries.sort(key=lambda e: e['name'].lower())
    data = {
        'version': bg['meta'].get('version'),
        'status': bg['meta'].get('status'),
        'hsf7_closed': HSF7_CLOSED,
        'status_text': STATUS_TEXT,
        'instruments': entries,
    }
    head = '/* Generated by hsf/build_legislation.py from hsf/legislation/backgrounds.json and hsf/sample-file/instruments.json. Do not edit. */\n'
    full = head + 'window.CNC_LEGISLATION=' + json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';\n'
    idx = head + 'window.CNC_LEGISLATION_INDEX=' + json.dumps(index, ensure_ascii=False, separators=(',', ':')) + ';\n'
    if '--check' in sys.argv:
        stale = [p.name for p, s in ((OUT_FULL, full), (OUT_INDEX, idx)) if not p.exists() or p.read_text(encoding='utf-8') != s]
        if stale:
            print('stale: ' + ', '.join(stale), file=sys.stderr)
            return 1
        print('legislation data is current')
        return 0
    OUT_FULL.write_text(full, encoding='utf-8')
    OUT_INDEX.write_text(idx, encoding='utf-8')
    counts: dict[str, int] = {}
    for e in entries:
        counts[e['fallback']['status']] = counts.get(e['fallback']['status'], 0) + 1
    print(f"{len(entries)} instruments written; fallback status {counts}; HSF-7 closed: {HSF7_CLOSED}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
