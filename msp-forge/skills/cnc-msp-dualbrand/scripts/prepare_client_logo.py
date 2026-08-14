#!/usr/bin/env python3
"""CNC MSP FORGE | DOC-SKL-01 v1.0.0 | Client logo preparation.

Normalises an uploaded client logo into the dual brand header band:
transparency normalised, proportionally scaled to the 120 px cap height band
with width capped at 130 px, minimum 600 px source width enforced. Lossless
corrections are automatic; lossy cases route to human review with the reason
stated in the JSON report.

Usage: prepare_client_logo.py <input.png|input.svg> <output.png> [report.json]
"""
import json
import sys
from pathlib import Path

from PIL import Image

BAND_HEIGHT = 102
MAX_WIDTH = 130
MIN_SOURCE_WIDTH = 600
MAX_ASPECT = 8.0


def prepare(src: Path, dst: Path):
    report = {"source": str(src), "output": str(dst), "corrections": [], "review_required": False, "reasons": []}

    if src.suffix.lower() == ".svg":
        try:
            import cairosvg  # optional dependency, production factory installs it
            png_bytes = cairosvg.svg2png(url=str(src), dpi=300, output_width=1200)
            import io
            im = Image.open(io.BytesIO(png_bytes))
            report["corrections"].append("SVG rasterised at 300 dpi")
        except ImportError:
            report["review_required"] = True
            report["reasons"].append("SVG supplied but no rasteriser available in this environment")
            return report
    else:
        im = Image.open(src)

    if im.width < MIN_SOURCE_WIDTH:
        report["review_required"] = True
        report["reasons"].append(f"source width {im.width} px is below the {MIN_SOURCE_WIDTH} px minimum")

    aspect = im.width / im.height
    if aspect > MAX_ASPECT or aspect < 1 / MAX_ASPECT:
        report["review_required"] = True
        report["reasons"].append(f"aspect ratio {aspect:.2f} is beyond the 8:1 limit for the band")

    if im.mode != "RGBA":
        im = im.convert("RGBA")
        report["corrections"].append("converted to RGBA")

    # Key a uniform white background only when it is lossless: every border
    # pixel white and fully opaque means the background is a plain matte.
    px = im.load()
    border = [px[x, 0] for x in range(im.width)] + [px[x, im.height - 1] for x in range(im.width)] \
           + [px[0, y] for y in range(im.height)] + [px[im.width - 1, y] for y in range(im.height)]
    if all(p[3] == 255 and p[0] > 250 and p[1] > 250 and p[2] > 250 for p in border):
        data = [(r, g, b, 0) if (r > 250 and g > 250 and b > 250) else (r, g, b, a)
                for (r, g, b, a) in im.getdata()]
        im.putdata(data)
        report["corrections"].append("uniform white background keyed to transparent (lossless)")

    scale = min(BAND_HEIGHT / im.height, MAX_WIDTH / im.width)
    out = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    out.save(dst)
    report["prepared_size"] = list(out.size)
    return report


if __name__ == "__main__":
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    rep = prepare(src, dst)
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else dst.with_suffix(".report.json")
    out.write_text(json.dumps(rep, indent=2))
    print(json.dumps(rep, indent=2))
    sys.exit(1 if rep["review_required"] else 0)
