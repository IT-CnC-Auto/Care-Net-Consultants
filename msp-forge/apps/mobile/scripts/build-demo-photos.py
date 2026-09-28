"""Bee-Inspect | drawn demonstration photos for the demo companies.

Every picture is a simple drawing, clearly marked "DEMONSTRATION PHOTO" and
"FICTITIOUS", in the style of the P4 demonstration photos in assets/demo/.
No real place, person or company is shown. The SHA 256 of each file is
printed; src/backend/demo-seed.ts carries the same values and a test checks
that they match the files.

Run from msp-forge/:  python3 apps/mobile/scripts/build-demo-photos.py
Needs Pillow.
"""
import hashlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

APP = Path(__file__).resolve().parent.parent
OUT = APP / 'assets' / 'demo'
FONT = str(APP / 'assets' / 'fonts' / 'BebasNeue-Regular.ttf')
INK = (17, 17, 17)
GOLD = (240, 163, 43)
W, H = 960, 720


def frame(caption, bg):
    im = Image.new('RGB', (W, H), bg)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, W, 96), fill=INK)
    d.rectangle((0, H - 70, W, H), fill=INK)
    d.text((24, 18), 'DEMONSTRATION PHOTO', font=ImageFont.truetype(FONT, 64), fill=GOLD)
    d.text((24, H - 58), 'FICTITIOUS: ' + caption.upper(), font=ImageFont.truetype(FONT, 36), fill=(255, 255, 255))
    return im, d


def conveyor():
    im, d = frame('Conveyor tail pulley, guard not refitted', (206, 214, 222))
    d.rectangle((0, 520, W, 650), fill=(120, 110, 96))
    d.polygon([(80, 380), (700, 300), (700, 330), (80, 410)], fill=(40, 40, 40))
    d.ellipse((640, 250, 800, 410), fill=(90, 90, 96), outline=INK, width=6)
    d.ellipse((700, 310, 740, 350), fill=(30, 30, 30))
    for x in (160, 330, 500):
        d.rectangle((x, 400, x + 14, 520), fill=(150, 150, 156))
    d.rectangle((760, 440, 900, 510), fill=(230, 190, 40), outline=INK, width=4)
    d.text((770, 452), 'GUARD', font=ImageFont.truetype(FONT, 44), fill=INK)
    return im


def lab():
    im, d = frame('Specimen reception, spill kit hook empty', (226, 232, 236))
    d.rectangle((0, 470, W, 650), fill=(200, 204, 208))
    d.rectangle((60, 380, 620, 470), fill=(245, 245, 245), outline=(150, 150, 150), width=4)
    for x in (100, 200, 300):
        d.rectangle((x, 320, x + 50, 380), fill=(210, 230, 250), outline=(120, 140, 170), width=3)
    d.rectangle((720, 180, 880, 360), outline=(120, 120, 120), width=5)
    d.line((800, 200, 800, 240), fill=(90, 90, 90), width=8)
    d.text((732, 300), 'SPILL KIT', font=ImageFont.truetype(FONT, 40), fill=(150, 30, 30))
    return im


def racking():
    im, d = frame('High bay racking, damaged upright', (220, 222, 214))
    d.rectangle((0, 560, W, 650), fill=(130, 130, 124))
    for x in (100, 380, 660):
        d.rectangle((x, 120, x + 22, 560), fill=(30, 90, 170))
    for y in (220, 340, 460):
        d.rectangle((100, y, 682, y + 16), fill=(230, 120, 30))
        for x in (140, 420):
            d.rectangle((x, y - 70, x + 180, y), fill=(190, 160, 110), outline=(120, 90, 50), width=3)
    d.polygon([(380, 470), (402, 470), (420, 520), (398, 520)], fill=(30, 90, 170))
    d.ellipse((350, 450, 450, 560), outline=(200, 30, 30), width=6)
    return im


def chemicals():
    im, d = frame('Farm chemical store, unlabelled sprays on the shelf', (214, 206, 190))
    d.rectangle((0, 560, W, 650), fill=(140, 120, 96))
    for y in (220, 360, 500):
        d.rectangle((80, y, 880, y + 14), fill=(110, 80, 50))
    for i, x in enumerate(range(110, 860, 110)):
        colour = [(40, 120, 60), (200, 170, 40), (60, 90, 160), (160, 60, 60)][i % 4]
        d.rectangle((x, 150, x + 60, 220), fill=colour, outline=INK, width=2)
        d.rectangle((x + 10, 290, x + 55, 360), fill=(240, 240, 240), outline=INK, width=2)
    d.ellipse((560, 260, 700, 380), outline=(200, 30, 30), width=6)
    return im


def main():
    for name, fn in [('demo-photo-conveyor.jpg', conveyor), ('demo-photo-lab.jpg', lab), ('demo-photo-racking.jpg', racking), ('demo-photo-chemicals.jpg', chemicals)]:
        path = OUT / name
        fn().save(path, 'JPEG', quality=72, optimize=True)
        data = path.read_bytes()
        print(name, len(data), hashlib.sha256(data).hexdigest())


if __name__ == '__main__':
    main()
