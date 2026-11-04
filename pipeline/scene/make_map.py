"""Draw the Pacific Northwest wall map as pixel art.

python3 make_map.py  ->  map_texture.png (wall texture for Blender),
                         map_panel.png + map_meta.json (close-up inspect overlay)
"""
import json, math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import pixui

HERE = Path(__file__).resolve().parent
LON0, LON1, LAT0, LAT1 = -126.6, -116.4, 41.7, 49.3
SY = 26.3                                   # px per degree latitude
SX = SY * math.cos(math.radians(45.5))      # px per degree longitude
MW, MH = round((LON1 - LON0) * SX), round((LAT1 - LAT0) * SY)

PAPER, PAPER_DRY, FOREST = (222, 196, 142), (214, 178, 120), (168, 176, 112)
OCEAN, OCEAN_DEEP, INK = (104, 150, 160), (84, 128, 142), (58, 38, 26)
RIVER, BORDER, PEAK, RED = (70, 120, 150), (120, 80, 60), (110, 90, 70), (196, 40, 30)


def P(lon, lat):
    return ((lon - LON0) * SX, (LAT1 - lat) * SY)


WATER = [(LON0, 49.05), (-125.6, 48.9), (-124.4, 48.56), (-123.9, 48.37), (-123.4, 48.32), (-123.3, 48.5), (-123.5, 48.7),
         (-123.9, 49.1), (-124.0, 49.3), (-123.2, 49.3), (-123.1, 49.05), (-122.75, 48.95), (-122.5, 48.75),
         (-122.45, 48.4), (-122.4, 48.1), (-122.35, 47.65), (-122.42, 47.3), (-122.9, 47.05), (-122.85, 47.35),
         (-122.65, 47.6), (-122.7, 47.95), (-122.8, 48.1), (-123.4, 48.12), (-124.1, 48.2), (-124.7, 48.38),
         (-124.65, 47.9), (-124.35, 47.35), (-124.15, 46.95), (-124.05, 46.6), (-124.0, 46.25), (-123.95, 45.8),
         (-124.0, 45.2), (-124.1, 44.6), (-124.15, 44.0), (-124.3, 43.4), (-124.55, 42.84), (-124.4, 42.4),
         (-124.2, 42.0), (-124.15, 41.7), (LON0, 41.7)]
COLUMBIA = [(-124.0, 46.25), (-123.4, 46.2), (-122.95, 46.1), (-122.75, 45.65), (-122.2, 45.57), (-121.2, 45.62),
            (-120.5, 45.72), (-119.6, 45.92), (-119.0, 46.0), (-119.2, 46.6), (-119.8, 47.2), (-119.9, 47.9),
            (-118.9, 48.0), (-118.0, 48.6), (-117.7, 49.3)]
WILLAMETTE = [(-122.75, 45.65), (-123.0, 45.0), (-123.05, 44.6), (-123.1, 44.05)]
SNAKE = [(-119.0, 46.0), (-118.2, 46.3), (-117.03, 46.42), (-116.7, 45.9), (-116.5, 45.4), (-116.9, 44.5),
         (-117.0, 44.2), (-116.4, 43.8)]
BORDERS = [[(-123.05, 49.0), (-116.4, 49.0)],
           [(-119.0, 46.0), (-117.03, 46.0)],
           [(-117.03, 46.42), (-117.03, 49.0)],
           [(-117.03, 44.2), (-117.03, 42.0)],
           [(-124.2, 42.0), (-116.4, 42.0)],
           COLUMBIA[:9]]
PEAKS = [(-121.8, 48.78), (-121.11, 48.11), (-121.76, 46.85), (-121.49, 46.2), (-122.19, 46.19), (-121.7, 45.37),
         (-121.8, 44.67), (-121.77, 44.1), (-122.1, 42.94), (-123.6, 47.8), (-123.3, 47.6), (-118.0, 45.2), (-117.3, 45.2)]
CITIES = [('SEATTLE', -122.33, 47.61, 'right'), ('PORTLAND', -122.68, 45.52, 'right'),
          ('SPOKANE', -117.43, 47.66, 'right'), ('EUGENE', -123.09, 44.05, 'right')]
HERE_PIN = (-121.35, 47.35)


def dashed(d, pts, color, on=3, off=2):
    pts = [P(*p) for p in pts]
    acc = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(int(math.hypot(x1 - x0, y1 - y0)), 1)
        for i in range(n):
            if acc % (on + off) < on:
                d.point((round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n)), fill=color)
            acc += 1


def draw_map():
    im = Image.new('RGB', (MW, MH), PAPER)
    d = ImageDraw.Draw(im)
    # wet west of the Cascade crest, dry to the east
    crest = [P(-121.4, 49.3), P(-121.6, 46.5), P(-121.75, 44.0), P(-121.9, 41.7)]
    d.polygon([P(LON0, 49.3)] + crest + [P(LON0, 41.7)], fill=FOREST)
    d.polygon(crest + [P(-116.4, 41.7), P(-116.4, 49.3)], fill=PAPER)
    d.polygon([P(-120.2, 47.6), P(-118.4, 47.2), P(-117.8, 45.8), P(-119.6, 45.0), P(-120.8, 45.9)], fill=PAPER_DRY)
    d.polygon([P(-120.5, 43.6), P(-117.6, 43.4), P(-117.3, 42.1), P(-120.9, 42.1)], fill=PAPER_DRY)
    d.polygon([P(*p) for p in WATER], fill=OCEAN)
    for k in range(1, 4):                                   # depth contour hugging the coast
        d.line([(x - 4 * k, y) for x, y in (P(*p) for p in WATER[25:38])], fill=OCEAN_DEEP)
    for b in BORDERS:
        dashed(d, b, BORDER)
    for r in (COLUMBIA, WILLAMETTE, SNAKE):
        d.line([P(*p) for p in r], fill=RIVER)
    for lon, lat in PEAKS:
        x, y = P(lon, lat)
        d.polygon([(x - 3, y + 2), (x, y - 3), (x + 3, y + 2)], fill=PEAK)
        d.point((x, y - 2), fill=(240, 236, 220))
    for k in (1, 2):                                        # fold creases
        d.line([(MW * k // 3, 0), (MW * k // 3, MH)], fill=(200, 172, 120))
    d.line([(0, MH // 2), (MW, MH // 2)], fill=(200, 172, 120))
    img = np.asarray(im, np.float32) / 255
    ink = np.array(INK, np.float32) / 255
    for name, lon, lat, align in CITIES:
        x, y = (round(v) for v in P(lon, lat))
        pixui.rect(img, x - 1, y - 1, x + 2, y + 2, ink)
        tx = x - 4 if align == 'right' else x + 4 if align == 'left' else x
        pixui.draw_text(img, name, tx, y - 3 if align != 'center' else y + 4, ink,
                        align={'right': 'right', 'left': 'left', 'center': 'center'}[align])
    pixui.draw_text(img, 'WASHINGTON', *map(round, P(-120.6, 46.55)), ink, align='center')
    pixui.draw_text(img, 'OREGON', *map(round, P(-120.2, 44.2)), ink, align='center')
    for i, ch in enumerate('PACIFIC'):
        pixui.draw_text(img, ch, 12, 76 + i * 9, np.array((232, 240, 236), np.float32) / 255)
    # "you are here": red pin, hand-drawn ring and label
    hx, hy = (round(v) for v in P(*HERE_PIN))
    red = np.array(RED, np.float32) / 255
    for a in np.linspace(0, 2 * math.pi, 40, endpoint=False):
        rr = 7 + 0.8 * math.sin(3 * a)
        img[round(hy + rr * math.sin(a)) % MH, round(hx + rr * math.cos(a)) % MW] = red
    pixui.rect(img, hx - 1, hy - 1, hx + 2, hy + 2, red)
    pixui.draw_text(img, 'YOU ARE HERE', hx, hy + 10, red, align='center')
    return img, (hx, hy)


def main():
    img, pin = draw_map()
    # wall texture: the sheet with a thin dark edge, upscaled so Blender's sampling stays crisp
    tex = img.copy()
    pixui.frame(tex, 0, 0, MW, MH, np.array(INK, np.float32) / 255)
    Image.fromarray((tex * 255 + 0.5).astype(np.uint8)).resize((MW * 4, MH * 4), Image.NEAREST).save(HERE / 'map_texture.png')

    # inspect panel: wood frame, title strip and close box around the sheet
    pad, title_h = 6, 13
    PW, PH = MW + 2 * pad, MH + 2 * pad + title_h
    panel = np.zeros((PH, PW, 3), np.float32)
    panel[:] = np.array((52, 30, 18), np.float32) / 255
    pixui.frame(panel, 0, 0, PW, PH, np.array((20, 10, 8), np.float32) / 255)
    pixui.frame(panel, 1, 1, PW - 1, PH - 1, np.array((96, 60, 34), np.float32) / 255)
    pixui.draw_text(panel, 'PACIFIC NORTHWEST', pad, 4, np.array((236, 214, 160), np.float32) / 255)
    close = (PW - pad - 9, 3, PW - pad, 12)
    pixui.rect(panel, *close, np.array((150, 40, 30), np.float32) / 255)
    pixui.draw_text(panel, 'X', close[0] + 2, close[1] + 1, np.array((250, 240, 230), np.float32) / 255)
    panel[pad + title_h:pad + title_h + MH, pad:pad + MW] = img
    Image.fromarray((panel * 255 + 0.5).astype(np.uint8)).save(HERE / 'map_panel.png')
    meta = {'size': [PW, PH], 'pin': [pin[0] + pad, pin[1] + pad + title_h],
            'close': [(close[0] + close[2]) // 2, (close[1] + close[3]) // 2], 'sheet': [MW, MH]}
    (HERE / 'map_meta.json').write_text(json.dumps(meta))
    print('map', MW, MH, meta)


if __name__ == '__main__':
    main()
