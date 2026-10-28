"""Bake the pixel UI kit into files Godot can load.

python3 pipeline/godot/make_ui_assets.py      (reads pipeline/scene)

  ui/pixel_font.png + .fnt   the 5x7 font from pixui.py as a BMFont
  ui/cursor_arrow.png, ui/cursor_hand.png
  ui/icon_<item>.png         12x12 item icons
  ui/map_panel.png + map_meta.json, assets/palette.json
"""
import json, shutil, sys
from pathlib import Path
import numpy as np
from PIL import Image

GODOT = Path(__file__).resolve().parents[2]   # repo root = the Godot project
PIXEL = GODOT / 'pipeline' / 'scene'
sys.path.insert(0, str(PIXEL))
import pixui                      # noqa: E402
from pixui import SPRITES         # noqa: E402

UI = GODOT / 'ui'
UI.mkdir(exist_ok=True)

# ---------------------------------------------------------------- font atlas
chars = sorted(pixui.FONT)
cell_w, cell_h, cols = 8, 8, 16
rows = (len(chars) + cols - 1) // cols
atlas = np.zeros((rows * cell_h, cols * cell_w, 4), np.uint8)
lines = [f'info face="pixel5x7" size=7 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=0,0',
         f'common lineHeight=9 base=7 scaleW={atlas.shape[1]} scaleH={atlas.shape[0]} pages=1 packed=0',
         'page id=0 file="pixel_font.png"',
         f'chars count={len(chars) * 2 - chars.count(" ")}']
for i, ch in enumerate(chars):
    g = pixui.FONT[ch]
    x, y = (i % cols) * cell_w, (i // cols) * cell_h
    atlas[y:y + g.shape[0], x:x + g.shape[1]][g] = 255
    entries = [ch] if ch.lower() == ch else [ch, ch.lower()]       # lowercase draws as caps, like pixui
    for c in entries:
        lines.append(f'char id={ord(c)} x={x} y={y} width={g.shape[1]} height={g.shape[0]} xoffset=0 yoffset=0 '
                     f'xadvance={g.shape[1] + 1} page=0 chnl=15')
lines[3] = f'chars count={len(lines) - 4}'
Image.fromarray(atlas, 'RGBA').save(UI / 'pixel_font.png')
(UI / 'pixel_font.fnt').write_text('\n'.join(lines) + '\n')

# ---------------------------------------------------------------- cursors + icons
INK = (14, 5, 5, 255)
for name, (rows_, hot) in SPRITES.items():
    w = max(len(r) for r in rows_)
    im = np.zeros((len(rows_), w, 4), np.uint8)
    for r, row in enumerate(rows_):
        for c, ch in enumerate(row):
            if ch == 'X':
                im[r, c] = INK
            elif ch == 'W':
                im[r, c] = (255, 255, 255, 255)
    Image.fromarray(im, 'RGBA').save(UI / f'cursor_{name}.png')
for name, rows_ in pixui.ICONS.items():
    im = np.zeros((12, 12, 4), np.uint8)
    for r, row in enumerate(rows_):
        for c, ch in enumerate(row):
            if ch != '.':
                im[r, c] = (*(int(v * 255 + 0.5) for v in pixui.ICON_COLORS[ch]), 255)
    Image.fromarray(im, 'RGBA').save(UI / f'icon_{name}.png')

shutil.copy(PIXEL / 'map_panel.png', UI / 'map_panel.png')
shutil.copy(PIXEL / 'map_meta.json', UI / 'map_meta.json')
shutil.copy(PIXEL / 'palette.json', GODOT / 'assets' / 'palette.json')
(UI / 'cursor_hotspots.json').write_text(json.dumps({k: v[1] for k, v in SPRITES.items()}))
print('ui assets ->', UI)
