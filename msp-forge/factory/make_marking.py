#!/usr/bin/env python3
"""CNC MSP FORGE | DOC-GEN-01 v1.2.0 | PLANNING ONLY page marking 13/10/2026

Draws the full page image render_pack.js places behind the content of every
page of an unsigned Plan: PLANNING ONLY three times on the diagonal, Care Net
red at 10 percent, the treatment of the public samples (render_sample_pdf.py,
52 degrees), sized so all three lines sit wholly inside the page. Transparent everywhere else, so text and tables stay legible.

Usage: py make_marking.py   (writes assets/marking_planning_only.png)
"""
import os
from PIL import Image, ImageDraw, ImageFont

DPI = 200
PT = DPI / 72.0
PAGE_W, PAGE_H = round(595.28 * PT), round(841.89 * PT)
LABEL = 'PLANNING ONLY'
RED = (237, 27, 36, 26)  # ED1B24 at 10 percent
FONT = os.path.join(os.environ.get('WINDIR', 'C:/Windows'), 'Fonts', 'arialbd.ttf')

font = ImageFont.truetype(FONT, round(54 * PT))
side = round((PAGE_W ** 2 + PAGE_H ** 2) ** 0.5) + 10
layer = Image.new('RGBA', (side, side), (0, 0, 0, 0))
draw = ImageDraw.Draw(layer)
w = draw.textlength(LABEL, font=font)
for offset in (-135, 0, 135):  # points from the page centre, along the normal
    draw.text(((side - w) / 2, side / 2 + offset * PT), LABEL, font=font, fill=RED, anchor='lm')
layer = layer.rotate(52, resample=Image.BICUBIC)
left, top = (side - PAGE_W) // 2, (side - PAGE_H) // 2
page = layer.crop((left, top, left + PAGE_W, top + PAGE_H))
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets', 'marking_planning_only.png')
# Every letter must sit inside the page with a margin: a clipped word reads as an accident.
alpha = page.getchannel('A')
box = alpha.getbbox()
margin = round(20 * PT)
assert box and box[0] >= margin and box[1] >= margin and box[2] <= PAGE_W - margin and box[3] <= PAGE_H - margin, box
page.save(out, optimize=True)
print(out, page.size, os.path.getsize(out), 'bytes')
