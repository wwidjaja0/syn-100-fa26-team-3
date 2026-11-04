"""Draw the workbench cutting mat as pixel art. It is the crafting view's build grid.

python3 make_mat.py  ->  mat_texture.png (mat texture for Blender, 4x nearest upscale)
                         mat_meta.json   (mat size + grid; export_glb.py copies it into scene_meta.json)

The crafting view looks straight down at the mat with PX_PER_CM screen pixels per cm, so one
texel here is exactly one 480x270 screen pixel there and the grid lines land on whole pixels.
"""
import json
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent

PX_PER_CM = 4            # crafting view scale: 480 px = 1.2 m
CELL = 20                # px per grid cell (5 cm), the size of an inventory slot
COLS, ROWS = 12, 7       # build grid, 60 x 35 cm
BORDER = 10              # px of ruler margin around the grid (2.5 cm)
W = 2 * BORDER + COLS * CELL + 1        # +1: the closing grid line
H = 2 * BORDER + ROWS * CELL + 1

# strong blues: the warm pendant light (1.0, 0.70, 0.38) takes most of the green and red
# back out, and the post shader snaps what is left to palette.json's blues
MAT = (24, 86, 214)
MARGIN = (20, 72, 190)
RIM = (14, 44, 130)
LINE = (120, 170, 255)
TICK = (160, 200, 255)


def draw():
    img = Image.new('RGB', (W, H), MARGIN)
    px = img.load()
    g0x, g0y, g1x, g1y = BORDER, BORDER, BORDER + COLS * CELL, BORDER + ROWS * CELL
    for y in range(g0y, g1y + 1):
        for x in range(g0x, g1x + 1):
            px[x, y] = MAT
    for c in range(COLS + 1):                              # grid lines
        for y in range(g0y, g1y + 1):
            px[g0x + c * CELL, y] = LINE
    for r in range(ROWS + 1):
        for x in range(g0x, g1x + 1):
            px[x, g0y + r * CELL] = LINE
    # ruler ticks in the margin: every cm, longer every 5 cm (in line with the grid)
    for x in range(g0x, g1x + 1, PX_PER_CM):
        n = 4 if (x - g0x) % CELL == 0 else 2
        for k in range(1, n + 1):
            px[x, g0y - k] = TICK
            px[x, g1y + k] = TICK
    for y in range(g0y, g1y + 1, PX_PER_CM):
        n = 4 if (y - g0y) % CELL == 0 else 2
        for k in range(1, n + 1):
            px[g0x - k, y] = TICK
            px[g1x + k, y] = TICK
    for x in range(W):                                     # 1 px rim
        px[x, 0] = px[x, H - 1] = RIM
    for y in range(H):
        px[0, y] = px[W - 1, y] = RIM
    return img


if __name__ == '__main__':
    draw().resize((W * 4, H * 4), Image.NEAREST).save(HERE / 'mat_texture.png')
    meta = {'px': [W, H], 'px_per_cm': PX_PER_CM, 'size_m': [W / (PX_PER_CM * 100), H / (PX_PER_CM * 100)],
            'cell_px': CELL, 'cols': COLS, 'rows': ROWS, 'grid_origin_px': [BORDER, BORDER]}
    (HERE / 'mat_meta.json').write_text(json.dumps(meta, indent=1))
    print('mat', W, 'x', H, 'px =', meta['size_m'], 'm')
