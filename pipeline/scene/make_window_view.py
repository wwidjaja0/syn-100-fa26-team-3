"""Render the view out of the cabin's window: a panorama from a real Pacific Northwest summit.

python3 make_window_view.py [--site saddle] [--preview out.png]
    ->  window_view.png, window_view_depth.png, window_view_meta.json

The cabin sits on top of a coastal mountain. This ray-marches real terrain around the summit
(AWS Terrain Tiles, the open "terrarium" elevation tiles: SRTM / GMTED / ETOPO1, public, including
the sea floor) into a cylindrical panorama: forested ridges falling away to the coast, the beach
and surf line, the Pacific out to the horizon (with the Earth's curvature). Nothing is painted.

The sky is left transparent: in the game the animated storm (toon.gdshader's storm_sky) shows
through, and the same sky colour hazes the distance, so the view follows day 1's blue storm and
day 2's orange one. So the PNG's channels are:
  rgb    the land / sea colour without haze (sRGB)
  alpha  how much of it shows through the haze: 1 close by, falling with distance; 0 is sky
and window_view_depth.png, for the weather (scripts/room/weather.gd: fog filling the valleys and the
sea below the summit, thicker or thinner haze):
  red    distance, log scale: 0 at DEPTH_NEAR_M (and the firs), 1 at FAR_M and the sky
  green  the ground's height, 0..DEPTH_TOP_M (the firs: the summit's)
  blue   1 on water

Downloaded tiles are cached in data/terrain_cache/ (git-ignored). make_ui_assets.py copies the
result into ui/. toon.gdshader (kind 3) reads it through window_view_meta.json's numbers, which
room_materials.gd passes on.
"""
import argparse, io, json, math, urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
CACHE = HERE / 'data' / 'terrain_cache'
TILE_URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'

# summit (lat, lon), the heading the window faces (degrees from north) and a note.
SITES = {
    'saddle': (45.9626, -123.6886, 262.0, 'Saddle Mountain, Oregon: the Columbia bar, Seaside, Tillamook Head'),
    'neahkahnie': (45.7445, -123.9375, 185.0, 'Neahkahnie Mountain, Oregon: the coast running south past Nehalem Bay'),
    'marys': (44.5045, -123.5527, 270.0, "Marys Peak, Oregon: the Coast Range's highest, the sea beyond"),
    'colonel_bob': (47.4815, -123.7556, 255.0, 'Colonel Bob, Olympic Mountains: Lake Quinault, the Pacific'),
}

ZOOM = 11                     # ~55 m per DEM pixel at these latitudes
RADIUS_M = 75_000.0           # terrain loaded this far out (the sea runs on to the horizon past it)
FAR_M = 120_000.0             # rays end here
EYE_ABOVE = 14.0              # m: the window above the summit's highest ground
SUMMIT_SEARCH_M = 250.0       # m: look this far around a site's point for its top
EARTH_R = 6_371_000.0
REFRACTION = 0.13

W, H = 1280, 440              # panorama pixels
HFOV = 160.0                  # degrees across, centred on the heading
PITCH_TOP, PITCH_BOTTOM = 20.0, -35.0

DEPTH_NEAR_M = 15.0           # window_view_depth.png's red channel: log distance from here to FAR_M
DEPTH_TOP_M = 1000.0          # ... and its green: height above the sea, up to this
HAZE_M = 30_000.0             # distance over which the haze takes ~63% of a colour
SEA_HAZE_M = 90_000.0
SEA_MIN_SHOW = 0.35           # the sea never hazes away completely, so the horizon reads

# colours (linear) before lighting. The game's 40-colour palette (assets/palette.json) has no
# greens: the forest is its dark teals, the sea its blues, the beach its creams.
FOREST_NEAR = np.array([0.010, 0.050, 0.065])
FOREST_FAR = np.array([0.018, 0.070, 0.110])
CLEARING = np.array([0.050, 0.100, 0.090])
ROCK = np.array([0.10, 0.10, 0.11])
SNOW = np.array([0.70, 0.74, 0.80])
SAND = np.array([0.45, 0.33, 0.17])
SEA = np.array([0.012, 0.100, 0.200])
SEA_FAR = np.array([0.030, 0.160, 0.280])
SURF = np.array([0.38, 0.72, 0.67])
FIR = np.array([0.006, 0.018, 0.030])          # the near trees' silhouettes
FIR_TOP_DEG = -16.0           # the firs' tips, straight towards the coast...
SITES_HEADING_COAST = 195.0   # ...which lies this way (degrees from north)
SUN = np.array([-0.55, -0.35, 0.76])            # east, north, up: soft light from the south-west


# ---------------------------------------------------------------- terrain
def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n
    return x, y


def fetch_tile(z, x, y):
    path = CACHE / f'{z}_{x}_{y}.png'
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(TILE_URL.format(z=z, x=x, y=y), headers={'User-Agent': 'terrain-panorama'})
        path.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    rgb = np.asarray(Image.open(path).convert('RGB'), dtype=np.float64)
    return rgb[..., 0] * 256.0 + rgb[..., 1] + rgb[..., 2] / 256.0 - 32768.0


class Terrain:
    """an elevation mosaic in Web Mercator tile pixels, sampled bilinearly by lat/lon"""

    def __init__(self, lat, lon):
        self.lat0, self.lon0 = lat, lon
        dlat = RADIUS_M / 111_320.0
        dlon = RADIUS_M / (111_320.0 * math.cos(math.radians(lat)))
        x0, y0 = tile_xy(lat + dlat, lon - dlon, ZOOM)
        x1, y1 = tile_xy(lat - dlat, lon + dlon, ZOOM)
        self.tx0, self.ty0 = int(x0), int(y0)
        nx, ny = int(x1) - self.tx0 + 1, int(y1) - self.ty0 + 1
        print(f'terrain: {nx * ny} tiles at zoom {ZOOM}')
        self.h = np.zeros((ny * 256, nx * 256))
        for j in range(ny):
            for i in range(nx):
                self.h[j * 256:(j + 1) * 256, i * 256:(i + 1) * 256] = fetch_tile(ZOOM, self.tx0 + i, self.ty0 + j)
        water = self.h <= 0.5
        self.water = water.astype(np.float64)
        # land near water, for the beach: a few dilations of the water mask
        near = water.copy()
        for _ in range(3):
            near = near | np.roll(near, 1, 0) | np.roll(near, -1, 0) | np.roll(near, 1, 1) | np.roll(near, -1, 1)
        self.shore = (near & ~water).astype(np.float64)
        land = ~water
        coast = land.copy()
        for _ in range(2):
            coast = coast | np.roll(coast, 1, 0) | np.roll(coast, -1, 0) | np.roll(coast, 1, 1) | np.roll(coast, -1, 1)
        self.surf = (coast & water).astype(np.float64)
        # slope normals (east, north, up) from the mosaic, in metres
        px_m = 40_075_016.0 * math.cos(math.radians(lat)) / (256 * 2 ** ZOOM)
        land_h = np.maximum(self.h, 0.0)
        for _ in range(3):                                    # soften the DEM's 55 m facets
            land_h = (land_h + np.roll(land_h, 1, 0) + np.roll(land_h, -1, 0) + np.roll(land_h, 1, 1) + np.roll(land_h, -1, 1)) / 5.0
        gy, gx = np.gradient(land_h, px_m)
        n = np.stack([-gx, gy, np.ones_like(gx)], -1)         # rows run south, so north is -row
        self.normal = n / np.linalg.norm(n, axis=-1, keepdims=True)

    def pixel(self, lat, lon):
        n = 2 ** ZOOM
        x = (lon + 180.0) / 360.0 * n
        y = (1.0 - np.arcsinh(np.tan(np.radians(lat))) / np.pi) / 2.0 * n
        return (x - self.tx0) * 256.0, (y - self.ty0) * 256.0

    def sample(self, grid, px, py):
        hgt, wid = grid.shape[:2]
        inside = (px >= 0) & (py >= 0) & (px < wid - 1) & (py < hgt - 1)
        px = np.clip(px, 0, wid - 1.001)
        py = np.clip(py, 0, hgt - 1.001)
        x0 = px.astype(int)
        y0 = py.astype(int)
        fx = px - x0
        fy = py - y0
        if grid.ndim == 3:
            fx = fx[..., None]
            fy = fy[..., None]
        top = grid[y0, x0] * (1 - fx) + grid[y0, x0 + 1] * fx
        bot = grid[y0 + 1, x0] * (1 - fx) + grid[y0 + 1, x0 + 1] * fx
        return top * (1 - fy) + bot * fy, inside


# ---------------------------------------------------------------- render
def _hash(x, y):
    """a repeatable 0..1 value per whole (x, y) cell"""
    x = np.floor(x)
    y = np.floor(y)
    return np.modf(np.sin(x * 12.9898 + y * 78.233) * 43758.5453)[0] % 1.0


def render(site):
    lat, lon, heading, note = SITES[site]
    print(f'{site}: {note}')
    t = Terrain(lat, lon)

    # the eye: just above the highest ground within SUMMIT_SEARCH_M of the site's point (the listed
    # coordinates are only roughly on top), so no nearby ground rises above the window
    n, e = np.meshgrid(np.arange(-SUMMIT_SEARCH_M, SUMMIT_SEARCH_M + 1, 20.0), np.arange(-SUMMIT_SEARCH_M, SUMMIT_SEARCH_M + 1, 20.0))
    keep = n ** 2 + e ** 2 <= SUMMIT_SEARCH_M ** 2
    clat = lat + n[keep] / 111_320.0
    clon = lon + e[keep] / (111_320.0 * math.cos(math.radians(lat)))
    hs, _ = t.sample(t.h, *t.pixel(clat, clon))
    top = int(np.argmax(hs))
    lat, lon = float(clat[top]), float(clon[top])
    eye_h = float(hs[top]) + EYE_ABOVE
    print(f'summit {lat:.4f}, {lon:.4f}; eye at {eye_h:.0f} m')

    yaw = np.radians(heading + (np.arange(W) + 0.5) / W * HFOV - HFOV / 2.0)          # per column
    pitch = np.radians(PITCH_TOP - (np.arange(H) + 0.5) / H * (PITCH_TOP - PITCH_BOTTOM))  # per row, top first
    dist = np.geomspace(15.0, FAR_M, 3200)                                            # per sample

    north = np.cos(yaw)[:, None] * dist[None, :]
    east = np.sin(yaw)[:, None] * dist[None, :]
    slat = lat + north / 111_320.0
    slon = lon + east / (111_320.0 * math.cos(math.radians(lat)))
    px, py = t.pixel(slat, slon)
    h, inside = t.sample(t.h, px, py)
    h = np.where(inside, h, 0.0)                    # past the loaded terrain: open sea
    ground = np.maximum(h, 0.0)
    drop = dist ** 2 / (2.0 * EARTH_R) * (1.0 - REFRACTION)
    ang = np.arctan2(ground - eye_h - drop[None, :], dist[None, :])                    # (W, samples)
    reach = np.maximum.accumulate(ang, axis=1)

    rgb = np.zeros((H, W, 3))
    alpha = np.zeros((H, W))
    depth = np.zeros((H, W, 3))
    depth[..., 0] = 1.0                             # sky: as far as it gets
    for c in range(W):
        idx = np.searchsorted(reach[c], pitch[::-1])[::-1]       # first sample reaching each row
        hit = idx < dist.size
        rows = np.nonzero(hit)[0]
        k = idx[rows]
        d = dist[k]
        pxx, pyy = px[c, k], py[c, k]
        water, _ = t.sample(t.water, pxx, pyy)
        shore, _ = t.sample(t.shore, pxx, pyy)
        surf, _ = t.sample(t.surf, pxx, pyy)
        nrm, _ = t.sample(t.normal, pxx, pyy)
        ins = inside[c, k]
        water = np.where(ins, water, 1.0)
        hh = ground[c, k]

        far = np.clip(d / 40_000.0, 0, 1)[:, None]
        forest = FOREST_NEAR * (1 - far) + FOREST_FAR * far
        # tree crowns: a speckle of lighter and darker greens, fading out with distance
        # crown cells shrink with distance in steps of two, so they stay a few pixels across
        cells = 14.0 * np.exp2(np.floor(np.log2(np.clip(3_000.0 / d, 1.0, 256.0))))
        crown = _hash(pxx * cells, pyy * cells) - 0.5
        forest = forest * (1.0 + 0.6 * crown * np.clip(1 - d / 8_000.0, 0, 1))[:, None]
        # lower, flatter ground near the sea is pasture and dune grass
        flat = np.clip(nrm[:, 2] * 8.0 - 7.0, 0, 1) * np.clip(1 - hh / 60.0, 0, 1)
        forest = forest + (CLEARING - forest) * flat[:, None]
        land = forest
        land = land + (ROCK - land) * np.clip((hh - 1100) / 400, 0, 1)[:, None]
        land = land + (SNOW - land) * np.clip((hh - 1700) / 300, 0, 1)[:, None]
        land = land + (SAND - land) * (np.clip(shore * 2.0, 0, 1) * (hh < 12))[:, None]
        light = 0.45 + 0.75 * np.clip(nrm @ (SUN / np.linalg.norm(SUN)), 0, 1)
        land = land * light[:, None]

        sea = SEA + (SEA_FAR - SEA) * np.clip(d / 60_000.0, 0, 1)[:, None]
        sea = sea + (SURF - sea) * (np.clip(surf * 1.5, 0, 1) * np.clip(1 - d / 30_000.0, 0, 1))[:, None]
        col = land * (1 - water[:, None]) + sea * water[:, None]

        haze = np.where(water > 0.5, np.maximum(np.exp(-d / SEA_HAZE_M), SEA_MIN_SHOW), np.exp(-d / HAZE_M))
        rgb[rows, c] = col
        alpha[rows, c] = np.clip(haze, 0.02, 1.0)
        depth[rows, c, 0] = np.log(d / DEPTH_NEAR_M) / math.log(FAR_M / DEPTH_NEAR_M)
        depth[rows, c, 1] = np.clip(hh / DEPTH_TOP_M, 0, 1)
        depth[rows, c, 2] = water > 0.5

    firs(rgb, alpha, pitch, heading, depth, eye_h)
    srgb = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.power(np.clip(rgb, 0, None), 1 / 2.4) - 0.055)
    img = np.dstack([np.clip(srgb, 0, 1) * 255, alpha * 255]).round().astype(np.uint8)
    depth_img = Image.fromarray((np.clip(depth, 0, 1) * 255).round().astype(np.uint8), 'RGB')
    meta = {'site': site, 'note': note, 'lat': lat, 'lon': lon, 'heading_deg': heading, 'eye_m': round(eye_h),
            'hfov_deg': HFOV, 'pitch_top_deg': PITCH_TOP, 'pitch_bottom_deg': PITCH_BOTTOM,
            'depth_near_m': DEPTH_NEAR_M, 'depth_far_m': FAR_M, 'depth_top_m': DEPTH_TOP_M}
    return Image.fromarray(img, 'RGBA'), depth_img, meta


def firs(rgb, alpha, pitch, heading, depth, eye_h):
    """the tops of the firs just below the summit, as dark silhouettes along the bottom of the view.
    They stand lower straight ahead (the coast) and taller towards the sides."""
    rng = np.random.default_rng(7)
    col_deg = HFOV / W
    pitch_deg = np.degrees(pitch)
    yaw = -HFOV / 2.0
    while yaw < HFOV / 2.0:
        side = min(abs(yaw - (SITES_HEADING_COAST - heading)) / 60.0, 1.0)
        top = FIR_TOP_DEG + side * 8.0 + rng.uniform(-1.5, 1.5)
        half = rng.uniform(0.9, 1.6)                          # degrees: half the tree's width at 1 degree down
        tiers = rng.uniform(0.7, 1.1)                         # degrees between branch tiers
        c0 = int((yaw + HFOV / 2.0 - half * 12) / col_deg)
        c1 = int((yaw + HFOV / 2.0 + half * 12) / col_deg)
        for c in range(max(c0, 0), min(c1, W)):
            dx = abs((c + 0.5) * col_deg - HFOV / 2.0 - yaw)
            down = top - pitch_deg                            # degrees below the tree's tip
            saw = 0.55 + 0.45 * np.mod(down / tiers, 1.0)     # branch tiers: wide at each tier's foot
            inside = (down > 0) & (dx < down * 0.32 * saw * half)
            rgb[inside, c] = FIR
            alpha[inside, c] = 1.0
            depth[inside, c] = (0.0, min(eye_h / DEPTH_TOP_M, 1.0), 0.0)
        yaw += rng.uniform(1.2, 3.0)


def preview(img):
    """the panorama over a plain storm-blue sky, with the haze, to look at"""
    a = np.asarray(img).astype(np.float64) / 255.0
    sky = np.array([0.30, 0.55, 0.85])
    col = a[..., :3] * a[..., 3:] + sky * (1 - a[..., 3:])
    return Image.fromarray((col * 255).astype(np.uint8), 'RGB')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--site', default='neahkahnie', choices=sorted(SITES))
    ap.add_argument('--preview', help='also save a flattened preview here')
    ap.add_argument('--out', default=str(HERE / 'window_view.png'))
    args = ap.parse_args()
    img, depth_img, meta = render(args.site)
    img.save(args.out)
    depth_img.save(args.out.replace('.png', '_depth.png'))
    if args.out == str(HERE / 'window_view.png'):
        (HERE / 'window_view_meta.json').write_text(json.dumps(meta, indent=1) + '\n')
    if args.preview:
        preview(img).save(args.preview)
    print('wrote', args.out)
