"""Draw the microfiche: a world map, read on the microfiche display.

python3 make_fiche.py  ->  fiche_blank.png        the world sheet as it starts: a blank outline map
                           fiche_world.png        the same sheet fully printed (land, sea, borders, rivers, cities)
                           fiche_blank_0/1.png,   the sheet at 1/4 and 1/2 scale, for zooming out (fewer labels)
                           fiche_world_0/1.png
                           fiche_detail_<id>.png  a 4x more detailed map of every area in data/stations.json
                                                  (the starting "revealed" areas and every station's patch)
                           fiche_thumb.png        whole-sheet overview for the reader's corner
                           globe_equirect.png     small full-world map for the display's idle globe
                           fiche_meta.json        projections: where a latitude/longitude lands on each image
make_ui_assets.py copies them into ui/.

The game (scripts/fiche.gd) shows the blank sheet and prints the full map only inside revealed
areas: the Pacific Northwest from the start, and a patch around every station reached over the
radio. Clicking a revealed area zooms into its detail map. Station marks are drawn on top in the game.

Everything is equirectangular. Geography is Natural Earth (public domain), compacted into
data/world_geo.json by fetch_geo.py.
"""
import json, unicodedata
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import pixui

HERE = Path(__file__).resolve().parent
DATA = HERE.parents[1] / 'data' / 'stations.json'
PX_PER_DEG = 10                              # world sheet
DETAIL_PX_PER_DEG = 40                       # zoomed detail maps (4x)
DETAIL_PAD_DEG = 0.75                        # detail maps reach a little past their reveal circle
LAT_TOP, LAT_BOTTOM = 80, -62                # the world sheet leaves out the empty poles
MARGIN = 14                                  # border with the sheet's grid index
THUMB_SCALE = 50                             # overview: 1 px per 5 degrees

# palette.json colours only: the UI is drawn after the palette snap
PAPER = (249, 228, 177)
LAND = (240, 205, 143)
SEA = (121, 183, 196)
DEEP = (99, 161, 173)
INK = (99, 68, 50)
DARK_INK = (63, 31, 14)
BORDER = (170, 97, 52)
STATE = (181, 127, 109)
RIVER = (76, 131, 150)
HOME_RED = (171, 70, 30)
BLANK_COAST = (181, 127, 109)
BLANK_GRID = (240, 205, 143)

HOME = (47.35, -121.35)                      # the shelter, in the Cascades east of Seattle
# coastal cities are labelled out over the sea, inland ones to the right
PNW_CITIES = [('SEATTLE', 47.61, -122.33, 'left'), ('PORTLAND', 45.52, -122.68, 'left'),
              ('VANCOUVER', 49.26, -123.12, 'left'), ('EUGENE', 44.05, -123.09, 'left'),
              ('SPOKANE', 47.66, -117.43, 'right'), ('BOISE', 43.61, -116.2, 'right')]
PEAKS = [('MT BAKER', 48.78, -121.8), ('MT RAINIER', 46.85, -121.76), ('MT ADAMS', 46.2, -121.49),
         ('MT ST HELENS', 46.19, -122.19), ('MT HOOD', 45.37, -121.7), ('MT BACHELOR', 43.98, -121.69),
         ('MT SHASTA', 41.41, -122.19), ('MT OLYMPUS', 47.8, -123.71)]


class Canvas:
    """An equirectangular raster: ppd pixels per degree, top-left at (lat_top, lon_left)."""
    def __init__(self, ppd, lat_top, lon_left, w, h):
        self.ppd, self.lat_top, self.lon_left, self.w, self.h = ppd, lat_top, lon_left, w, h

    def px(self, lat, lon):
        return ((lon - self.lon_left) * self.ppd, (self.lat_top - lat) * self.ppd)

    def meta(self):
        return {'px_per_deg': self.ppd, 'lat_top': self.lat_top, 'lon_left': self.lon_left, 'size': [self.w, self.h]}


def geo():
    return json.loads((HERE / 'data' / 'world_geo.json').read_text())


def fill(rings, cv, even_odd=True):
    """Rasterise rings to a mask (even-odd, so holes in the land rings come out as water)."""
    mask = np.zeros((cv.h, cv.w), bool)
    for ring in rings:
        pts = [cv.px(lat, lon) for lon, lat in ring]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        x0, y0 = max(int(min(xs)) - 1, 0), max(int(min(ys)) - 1, 0)
        x1, y1 = min(int(max(xs)) + 2, cv.w), min(int(max(ys)) + 2, cv.h)
        if x1 <= x0 or y1 <= y0:
            continue
        tile = Image.new('1', (x1 - x0, y1 - y0), 0)
        ImageDraw.Draw(tile).polygon([(x - x0, y - y0) for x, y in pts], fill=1)
        t = np.array(tile, bool)
        mask[y0:y1, x0:x1] = (mask[y0:y1, x0:x1] ^ t) if even_odd else (mask[y0:y1, x0:x1] | t)
    return mask


def stroke(lines, cv, width=1):
    im = Image.new('1', (cv.w, cv.h), 0)
    d = ImageDraw.Draw(im)
    for line in lines:
        d.line([cv.px(lat, lon) for lon, lat in line], fill=1, width=width)
    return np.array(im, bool)


def edge(mask):
    inner = mask & np.roll(mask, 1, 0) & np.roll(mask, -1, 0) & np.roll(mask, 1, 1) & np.roll(mask, -1, 1)
    return mask & ~inner


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        out = out | np.roll(out, 1, 0) | np.roll(out, -1, 0) | np.roll(out, 1, 1) | np.roll(out, -1, 1)
    return out


def graticule(img, cv, step, colour_at):
    """Dotted lines every `step` degrees; colour_at(y, x) picks the dot colour for what is under it."""
    lon = np.ceil(cv.lon_left / step) * step
    while True:
        x = round(cv.px(0, lon)[0])
        if x >= cv.w:
            break
        if x >= 0:
            for y in range(0, cv.h, 3):
                img[y, x] = colour_at(y, x)
        lon += step
    lat = np.floor(cv.lat_top / step) * step
    while True:
        y = round(cv.px(lat, 0)[1])
        if y >= cv.h:
            break
        if y >= 0:
            for x in range(0, cv.w, 3):
                img[y, x] = colour_at(y, x)
        lat -= step


def ascii_name(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode()
    s = s.split(',')[0].strip()
    return ''.join(c for c in s.upper() if c in pixui.FONT)


def printed(g, cv, river_rank, coast_band, grid_step, line_w=1):
    """The printed map on a canvas (no labels): sea, land, rivers, states, borders, coasts."""
    land, lakes = fill(g['land'], cv), fill(g['lakes'], cv, even_odd=False)
    land &= ~lakes
    m = np.zeros((cv.h, cv.w, 3), np.uint8)
    m[:] = DEEP
    m[~land & dilate(land, coast_band)] = SEA
    m[lakes] = SEA
    m[land] = LAND
    graticule(m, cv, grid_step, lambda y, x: STATE if land[y, x] else RIVER)
    ys, xs = np.mgrid[0:cv.h, 0:cv.w]
    m[stroke([l for r, l in g['rivers'] if r <= river_rank], cv, line_w) & land] = RIVER
    m[stroke(g['states'], cv) & land & ((xs + ys) % 2 == 0)] = STATE
    m[stroke(g['borders'], cv, line_w) & land & ((xs + ys) % 4 != 3)] = BORDER
    m[edge(land)] = INK
    m[edge(lakes)] = RIVER
    return m


def peaks(img, cv, ox=0, oy=0, size=3, names=False, taken=None):
    for name, lat, lon in PEAKS:
        x, y = (round(v) for v in cv.px(lat, lon))
        x, y = x + ox, y + oy
        if not (size <= x < img.shape[1] - size and size <= y < img.shape[0]):
            continue
        for dy in range(size):
            img[y - size + 1 + dy, x - dy:x + dy + 1] = INK
        if names and taken is not None:
            place_label(img, name, x, y, taken, sides=('right',), colour=INK)


def place_label(img, name, x, y, taken, sides=('right', 'left'), colour=DARK_INK, dot=False):
    """Put a label beside (x, y) unless every side would overlap one already placed."""
    tw = pixui.text_width(name)
    for side in sides:
        lx = x + 4 if side == 'right' else x - 3 - tw
        box = (lx - 1, y - 4, lx + tw + 1, y + 4)
        if box[0] < 0 or box[2] >= img.shape[1] or box[1] < 0 or box[3] >= img.shape[0]:
            continue
        if not any(box[0] < b[2] and b[0] < box[2] and box[1] < b[3] and b[1] < box[3] for b in taken):
            if dot:
                img[y - 1:y + 1, x - 1:x + 1] = DARK_INK
            pixui.draw_text(img, name, lx, y - 3, colour, shadow=PAPER)
            taken.append(box)
            return True
    return False


def home(img, cv, ox=0, oy=0, arm=3):
    """The shelter: a red cross, labelled underneath. Returns the label's box."""
    x, y = (round(v) for v in cv.px(*HOME))
    x, y = x + ox, y + oy
    for k in range(-arm, arm + 1):
        for w in (0, 1):
            img[y + k, x + k + w] = img[y + k, x - k + w] = HOME_RED
    tw = pixui.text_width('SHELTER')
    pixui.draw_text(img, 'SHELTER', x, y + arm + 3, HOME_RED, shadow=PAPER, align='center')
    return (x - tw // 2 - 1, y + arm + 2, x + tw // 2 + 1, y + arm + 11)


# ---------------------------------------------------------------- world sheet
# zoom levels of the world sheet, in px per degree: the reader can zoom out to the first two; the
# last is the main sheet (fiche_blank.png / fiche_world.png), the others fiche_<kind>_<level>.png
LEVELS = [2.5, 5, PX_PER_DEG]


def world_canvas(ppd):
    return Canvas(ppd, LAT_TOP, -180, round(360 * ppd), round((LAT_TOP - LAT_BOTTOM) * ppd))


WORLD = world_canvas(PX_PER_DEG)
W, H = WORLD.w + 2 * MARGIN, WORLD.h + 2 * MARGIN


def frame_and_index(sheet, cv, ink):
    """Border with the column (01..24, every 15 degrees) and row (A..J) index, like a fiche grid."""
    h, w = sheet.shape[:2]
    sheet[:MARGIN, :] = PAPER
    sheet[-MARGIN:, :] = PAPER
    sheet[:, :MARGIN] = PAPER
    sheet[:, -MARGIN:] = PAPER
    sheet[MARGIN - 2, MARGIN - 2:w - MARGIN + 2] = ink
    sheet[h - MARGIN + 1, MARGIN - 2:w - MARGIN + 2] = ink
    sheet[MARGIN - 2:h - MARGIN + 2, MARGIN - 2] = ink
    sheet[MARGIN - 2:h - MARGIN + 2, w - MARGIN + 1] = ink
    for i in range(24):
        x = MARGIN + round((i * 15 + 7.5) * cv.ppd)
        pixui.draw_text(sheet, f'{i + 1:02d}', x, 3, ink, align='center')
        pixui.draw_text(sheet, f'{i + 1:02d}', x, h - 10, ink, align='center')
    for r, top in enumerate(range(LAT_TOP, LAT_BOTTOM, -15)):
        mid = (top + max(top - 15, LAT_BOTTOM)) / 2
        y = MARGIN + round((LAT_TOP - mid) * cv.ppd) - 3
        pixui.draw_text(sheet, 'ABCDEFGHIJ'[r], 4, y, ink)
        pixui.draw_text(sheet, 'ABCDEFGHIJ'[r], w - 9, y, ink)


def world_blank(g, cv):
    """The sheet before anything is known: paper with faint coastlines and the grid."""
    land, lakes = fill(g['land'], cv), fill(g['lakes'], cv, even_odd=False)
    m = np.zeros((cv.h, cv.w, 3), np.uint8)
    m[:] = PAPER
    graticule(m, cv, 15, lambda y, x: BLANK_GRID)
    m[edge(land) | edge(lakes)] = BLANK_COAST
    sheet = np.zeros((cv.h + 2 * MARGIN, cv.w + 2 * MARGIN, 3), np.uint8)
    sheet[MARGIN:MARGIN + cv.h, MARGIN:MARGIN + cv.w] = m
    frame_and_index(sheet, cv, INK)
    return sheet


def world_printed(g, cv):
    """The printed sheet; zoomed-out levels carry fewer labels (only capitals at half scale, none below)."""
    sheet = np.zeros((cv.h + 2 * MARGIN, cv.w + 2 * MARGIN, 3), np.uint8)
    rivers = 6 if cv.ppd >= 10 else 3
    sheet[MARGIN:MARGIN + cv.h, MARGIN:MARGIN + cv.w] = printed(g, cv, rivers, max(2, round(cv.ppd)), 15)
    frame_and_index(sheet, cv, INK)
    if cv.ppd >= 10:
        peaks(sheet, cv, MARGIN, MARGIN)
    taken = [home(sheet, cv, MARGIN, MARGIN, arm=3 if cv.ppd >= 10 else 2)]
    if cv.ppd < 5:
        return sheet
    # cities: the PNW first, then the world's largest; a label is skipped if it would overlap another
    seen = set()
    if cv.ppd >= 10:
        for name, lat, lon, side in PNW_CITIES:
            x, y = (round(v) + MARGIN for v in cv.px(lat, lon))
            if place_label(sheet, name, x, y, taken, sides=(side,), dot=True):
                seen.add(name)
    for name, lat, lon, rank, cap in g['cities']:
        name = ascii_name(name)
        wanted = (rank <= 1 or (cap and rank <= 3)) if cv.ppd >= 10 else (rank == 0 and cap)
        if wanted and name not in seen:
            x, y = (round(v) + MARGIN for v in cv.px(lat, lon))
            if place_label(sheet, name, x, y, taken, dot=True):
                seen.add(name)
    return sheet


# ---------------------------------------------------------------- detail maps
def detail(g, area):
    """A 4x map around one revealed area: every river, towns, peaks named, a grid every degree."""
    r = area['radius_deg'] + DETAIL_PAD_DEG
    size = round(2 * r * DETAIL_PX_PER_DEG)
    cv = Canvas(DETAIL_PX_PER_DEG, area['lat'] + r, area['lon'] - r, size, size)
    img = printed(g, cv, river_rank=12, coast_band=24, grid_step=1, line_w=2)
    taken = []
    if cv.lon_left < HOME[1] < cv.lon_left + 2 * r and cv.lat_top - 2 * r < HOME[0] < cv.lat_top:
        taken.append(home(img, cv, arm=5))
    peaks(img, cv, size=5, names=True, taken=taken)
    seen = set()
    towns = [(n, la, lo) for n, la, lo, _ in PNW_CITIES]
    towns += [(ascii_name(t[0]), t[1], t[2]) for t in g['towns'] if t[3] <= 8]
    towns += [(ascii_name(c[0]), c[1], c[2]) for c in g['cities']]
    for name, lat, lon in towns:
        x, y = (round(v) for v in cv.px(lat, lon))
        if not name or name in seen or not (0 <= x < size and 0 <= y < size):
            continue
        if place_label(img, name, x, y, taken, dot=True):
            seen.add(name)
    return img, cv


# ---------------------------------------------------------------- small images
def thumb(g):
    cv = Canvas(PX_PER_DEG / THUMB_SCALE, LAT_TOP, -180, round(WORLD.w / THUMB_SCALE), round(WORLD.h / THUMB_SCALE))
    land = fill(g['land'], cv)
    t = np.zeros(land.shape + (3,), np.uint8)
    t[:] = DEEP
    t[land] = LAND
    return t


def globe(g):
    """Full-world map (lat 90..-90) for the idle globe on the display's screen."""
    cv = Canvas(256 / 360, 90, -180, 256, 128)
    land = fill(g['land'], cv)
    t = np.zeros(land.shape + (3,), np.uint8)
    t[:] = DEEP
    t[land] = LAND
    t[edge(land)] = INK
    return t


if __name__ == '__main__':
    g = geo()
    levels = []
    for i, ppd in enumerate(LEVELS):
        cv = world_canvas(ppd)
        suffix = '' if ppd == PX_PER_DEG else f'_{i}'
        Image.fromarray(world_blank(g, cv), 'RGB').save(HERE / f'fiche_blank{suffix}.png')
        Image.fromarray(world_printed(g, cv), 'RGB').save(HERE / f'fiche_world{suffix}.png')
        levels.append({'px_per_deg': ppd, 'blank': f'fiche_blank{suffix}.png', 'printed': f'fiche_world{suffix}.png',
                       'size': [cv.w + 2 * MARGIN, cv.h + 2 * MARGIN]})
    Image.fromarray(thumb(g), 'RGB').save(HERE / 'fiche_thumb.png')
    Image.fromarray(globe(g), 'RGB').save(HERE / 'globe_equirect.png')
    stations = json.loads(DATA.read_text())
    areas = list(stations['revealed']) + [dict(s, radius_deg=s.get('reveal_deg', 5)) for s in stations['stations']]
    for old in HERE.glob('fiche_detail_*.png'):
        old.unlink()
    details = {}
    for a in areas:
        img, cv = detail(g, a)
        Image.fromarray(img, 'RGB').save(HERE / f"fiche_detail_{a['id']}.png")
        details[a['id']] = cv.meta()
    meta = {'size': [W, H], 'origin_px': [MARGIN, MARGIN], 'px_per_deg': PX_PER_DEG,
            'lat_top': LAT_TOP, 'lat_bottom': LAT_BOTTOM, 'lon_left': -180, 'thumb_scale': THUMB_SCALE,
            'home': list(HOME), 'levels': levels, 'details': details}
    (HERE / 'fiche_meta.json').write_text(json.dumps(meta, indent=1))
    print('fiche', W, 'x', H, '| details:', ', '.join(f"{k} {v['size'][0]}px" for k, v in details.items()))
