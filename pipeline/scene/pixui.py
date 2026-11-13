"""Tiny pixel-art UI kit: the source of the game's font, item icons and cursors.

A 5x7 bitmap font, item icons as character grids, and helpers that draw them
straight into float RGB numpy images (H, W, 3) at the low render resolution.
"""
import numpy as np

_G = {
    'A': ".###. #...# #...# ##### #...# #...# #...#",
    'B': "####. #...# #...# ####. #...# #...# ####.",
    'C': ".###. #...# #.... #.... #.... #...# .###.",
    'D': "####. #...# #...# #...# #...# #...# ####.",
    'E': "##### #.... #.... ####. #.... #.... #####",
    'F': "##### #.... #.... ####. #.... #.... #....",
    'G': ".###. #...# #.... #.### #...# #...# .####",
    'H': "#...# #...# #...# ##### #...# #...# #...#",
    'I': ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
    'J': "..### ...#. ...#. ...#. ...#. #..#. .##..",
    'K': "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
    'L': "#.... #.... #.... #.... #.... #.... #####",
    'M': "#...# ##.## #.#.# #.#.# #...# #...# #...#",
    'N': "#...# #...# ##..# #.#.# #..## #...# #...#",
    'O': ".###. #...# #...# #...# #...# #...# .###.",
    'P': "####. #...# #...# ####. #.... #.... #....",
    'Q': ".###. #...# #...# #...# #.#.# #..#. .##.#",
    'R': "####. #...# #...# ####. #.#.. #..#. #...#",
    'S': ".#### #.... #.... .###. ....# ....# ####.",
    'T': "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
    'U': "#...# #...# #...# #...# #...# #...# .###.",
    'V': "#...# #...# #...# #...# #...# .#.#. ..#..",
    'W': "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.",
    'X': "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
    'Y': "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
    'Z': "##### ....# ...#. ..#.. .#... #.... #####",
    '0': ".###. #...# #..## #.#.# ##..# #...# .###.",
    '1': "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
    '2': ".###. #...# ....# ...#. ..#.. .#... #####",
    '3': "####. ....# ....# .###. ....# ....# ####.",
    '4': "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
    '5': "##### #.... ####. ....# ....# #...# .###.",
    '6': "..##. .#... #.... ####. #...# #...# .###.",
    '7': "##### ....# ...#. ..#.. .#... .#... .#...",
    '8': ".###. #...# #...# .###. #...# #...# .###.",
    '9': ".###. #...# #...# .#### ....# ...#. .##..",
    '.': ".. .. .. .. .. ## ##",
    ',': ".. .. .. .. .# .# #.",
    "'": "# # . . . . .",
    '-': "... ... ... ### ... ... ...",
    ':': ".. ## ## .. ## ## ..",
    '?': ".###. #...# ....# ...#. ..#.. ..... ..#..",
    '!': "# # # # # . #",
    '(': ".# #. #. #. #. #. .#",
    ')': "#. .# .# .# .# .# #.",
    '/': "....# ...#. ...#. ..#.. .#... .#... #....",
    '+': "..... ..#.. ..#.. ##### ..#.. ..#.. .....",
    '=': "..... ..... ##### ..... ##### ..... .....",
    '%': "##..# ##.#. ...#. ..#.. .#... .#.## #..##",
    ' ': "... ... ... ... ... ... ...",
}
FONT = {k: np.array([[c == '#' for c in row] for row in v.split()], bool) for k, v in _G.items()}
LINE_H = 9


def text_width(s):
    return sum(FONT.get(c, FONT['?']).shape[1] + 1 for c in s.upper()) - 1 if s else 0


def draw_text(img, s, x, y, color, shadow=None, align='left'):
    """Blit text; `shadow` draws a 1px outline around every glyph pixel."""
    s = s.upper()
    if align == 'center':
        x -= text_width(s) // 2
    elif align == 'right':
        x -= text_width(s)
    H, W = img.shape[:2]
    cells = []
    cx = x
    for ch in s:
        g = FONT.get(ch, FONT['?'])
        ys, xs = np.nonzero(g)
        cells.append((ys + y, xs + cx))
        cx += g.shape[1] + 1
    if not cells:
        return
    ys = np.concatenate([c[0] for c in cells]); xs = np.concatenate([c[1] for c in cells])
    if shadow is not None:
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                yy, xx = ys + dy, xs + dx
                ok = (yy >= 0) & (yy < H) & (xx >= 0) & (xx < W)
                img[yy[ok], xx[ok]] = shadow
    ok = (ys >= 0) & (ys < H) & (xs >= 0) & (xs < W)
    img[ys[ok], xs[ok]] = color


def wrap(s, max_chars):
    lines, cur = [], ''
    for word in s.split():
        if cur and len(cur) + 1 + len(word) > max_chars:
            lines.append(cur)
            cur = word
        else:
            cur = f'{cur} {word}' if cur else word
    if cur:
        lines.append(cur)
    return lines


# ---------------------------------------------------------------- item icons (12x12)
ICON_COLORS = {
    'K': (0.06, 0.03, 0.03), 'W': (0.96, 0.94, 0.86), 'R': (0.62, 0.16, 0.10), 'G': (0.62, 0.74, 0.66),
    'B': (0.45, 0.28, 0.14), 'C': (0.90, 0.82, 0.62), 'O': (0.86, 0.42, 0.12), 'Y': (0.98, 0.80, 0.36),
    'T': (0.80, 0.55, 0.30), 'E': (1.00, 0.36, 0.10), 'S': (0.70, 0.70, 0.72), 'M': (0.40, 0.44, 0.36),
    'D': (0.16, 0.17, 0.16), 'L': (1.00, 0.20, 0.12),
}
ICONS = {
    'jar': ["..KKKKKKKK..",
            "..KRRRRRRK..",
            ".KKKKKKKKKK.",
            ".KGGGGGGGGK.",
            ".KGBBBGBBBK.",
            ".KBBBBBBBBK.",
            ".KGCBBCBBGK.",
            ".KGCGGCGBBK.",
            ".KBBBBBBBBK.",
            ".KGGBBBCGGK.",
            ".KGGGGGGGGK.",
            "..KKKKKKKK.."],
    'papers': ["............",
               "...KKKKKK...",
               "...KWWWWK...",
               ".KKKWWWWKKK.",
               ".KOOOOOOOOK.",
               ".KOYYYYYYOK.",
               ".KOYOOOOYOK.",
               ".KOYYYYYYOK.",
               ".KOOOOOOOOK.",
               ".KOOOOOOOOK.",
               ".KKKKKKKKKK.",
               "............"],
    'cig': ["..........S.",
            "........S...",
            ".........S..",
            "........S...",
            "............",
            "KKKKKKKKKKK.",
            "KTTWWWBWWEKK",
            "KTTWWBWWWEEK",
            "KKKKKKKKKKK.",
            "............",
            "............",
            "............"],
    'speaker': ["........KK..",
                "......KKMK..",
                "....KKMMMK..",
                "KKKKMMMMMK..",
                "KDDKMMMMMK..",
                "KDLKMMMMMK..",
                "KKKKMMMMMK..",
                "....KKMMMK..",
                "......KKMK..",
                "........KK..",
                "............",
                "............"],
    'battery': ["............",
                "............",
                "..KKK..KKK..",
                "..KLK..KSK..",
                "KKKKKKKKKKKK",
                "KDDDDDDDDDDK",
                "KYYYYYYYYYYK",
                "KYKYYYYYYYYK",
                "KYYYYYYYYYYK",
                "KDDDDDDDDDDK",
                "KKKKKKKKKKKK",
                "............"],
}
ITEM_NAMES = {'jar': 'DRIED MUSHROOMS', 'papers': 'ROLLING PAPERS', 'cig': 'SHROOM CIGARETTE', 'speaker': 'PA SPEAKER'}


def draw_icon(img, name, x, y, scale=1):
    """Top-left at (x, y)."""
    H, W = img.shape[:2]
    for r, row in enumerate(ICONS[name]):
        for c, ch in enumerate(row):
            if ch == '.':
                continue
            col = ICON_COLORS[ch]
            for sy in range(scale):
                for sx in range(scale):
                    px, py = x + c * scale + sx, y + r * scale + sy
                    if 0 <= px < W and 0 <= py < H:
                        img[py, px] = col


def rect(img, x0, y0, x1, y1, color):
    H, W = img.shape[:2]
    img[max(y0, 0):min(y1, H), max(x0, 0):min(x1, W)] = color


def frame(img, x0, y0, x1, y1, color, t=1):
    rect(img, x0, y0, x1, y0 + t, color); rect(img, x0, y1 - t, x1, y1, color)
    rect(img, x0, y0, x0 + t, y1, color); rect(img, x1 - t, y0, x1, y1, color)


def line(img, x0, y0, x1, y1, color, mask=None):
    H, W = img.shape[:2]
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n):
        t = i / max(n - 1, 1)
        px, py = int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t))
        if 0 <= px < W and 0 <= py < H and (mask is None or mask[py, px]):
            img[py, px] = color


# ---------------------------------------------------------------- cursors (X = ink, W = fill)
ARROW = ["X", "XX", "XWX", "XWWX", "XWWWX", "XWWWWX", "XWWWWWX", "XWWWWWWX", "XWWWWXXXX",
         "XWXWWX", "XX XWWX", "X  XWWX", "    XX"]
HAND = ["    XX", "   XWWX", "   XWWX", "   XWWX", "   XWWXXX", "   XWWXWWXX", " XXXWWXWWXWX",
        "XWWXWWWWWWWX", "XWWWWWWWWWWX", " XWWWWWWWWWX", "  XWWWWWWWX", "   XWWWWWWX", "   XXXXXXXX"]
SPRITES = {'arrow': (ARROW, (0, 0)), 'hand': (HAND, (4, 0))}   # rows, hotspot (col,row)
