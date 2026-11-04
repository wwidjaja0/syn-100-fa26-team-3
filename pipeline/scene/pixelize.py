"""Render the current scene at low res, then snap it to the "Before the Surge"
palette with ordered dithering and nearest-neighbour upscale.

From the Blender GUI: Scripting tab > open text 'pixelize.py' > Run Script.
Writes render_lowres.png and render_pixel.png next to the .blend.
"""
import bpy
import numpy as np
from pathlib import Path

UPSCALE = 4
DITHER = 0.045       # 0 = flat bands, higher = more checkerboard texture
SATURATION = 1.25
CONTRAST = 1.08

# 40 colours sampled from the reference key art (median cut)
PALETTE = [
    (14, 5, 5),
    (27, 17, 18),
    (21, 40, 53),
    (32, 30, 33),
    (63, 31, 14),
    (64, 45, 50),
    (22, 49, 64),
    (86, 44, 29),
    (30, 80, 102),
    (109, 51, 28),
    (23, 62, 79),
    (171, 70, 30),
    (69, 63, 76),
    (28, 73, 87),
    (238, 139, 33),
    (76, 131, 150),
    (99, 68, 50),
    (165, 221, 214),
    (170, 97, 52),
    (126, 86, 78),
    (131, 63, 34),
    (249, 228, 177),
    (99, 161, 173),
    (36, 100, 119),
    (235, 100, 23),
    (240, 205, 143),
    (69, 104, 121),
    (23, 53, 71),
    (35, 113, 148),
    (181, 127, 109),
    (245, 168, 49),
    (121, 183, 196),
    (239, 180, 94),
    (20, 52, 76),
    (153, 194, 182),
    (119, 115, 127),
    (20, 53, 80),
    (25, 79, 122),
    (68, 83, 99),
    (35, 52, 90),
]

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5


def pixelize(src, dst, upscale=UPSCALE):
    img = bpy.data.images.load(str(src), check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
    bpy.data.images.remove(img)

    # punch up colour like the key art
    lum = px @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    px = lum[..., None] + (px - lum[..., None]) * SATURATION
    px = (px - 0.5) * CONTRAST + 0.5

    # ordered dither then nearest palette colour (weighted RGB distance)
    yy, xx = np.mgrid[0:h, 0:w]
    px = px + BAYER4[yy % 4, xx % 4][..., None] * DITHER
    pal = np.array(PALETTE, dtype=np.float32) / 255.0
    wts = np.array([2.0, 4.0, 3.0], dtype=np.float32)
    d = (((px[:, :, None, :] - pal[None, None]) ** 2) * wts).sum(-1)
    out = pal[d.argmin(-1)]

    out = np.repeat(np.repeat(out, upscale, 0), upscale, 1)
    H, W = out.shape[:2]
    rgba = np.concatenate([out, np.ones((H, W, 1), np.float32)], -1)
    res = bpy.data.images.new('pixel_out', W, H, alpha=False)
    res.pixels.foreach_set(rgba.ravel())
    res.filepath_raw = str(dst)
    res.file_format = 'PNG'
    res.save()
    bpy.data.images.remove(res)
    print('Wrote pixel-art render:', dst)


def render_and_pixelize(suffix=''):
    scene = bpy.context.scene
    base = Path(bpy.data.filepath).parent if bpy.data.filepath else Path(scene.render.filepath).parent
    low = base / f'render_lowres{suffix}.png'
    scene.render.filepath = str(low)
    bpy.ops.render.render(write_still=True)
    pixelize(low, base / f'render_pixel{suffix}.png')


def render_all_states():
    """One pixel render per cabinet/shutter combination, then restore the toggles."""
    scene = bpy.context.scene
    saved = scene['cabinet_open'], scene['shutters_closed']
    for cab in (True, False):
        for sh in (True, False):
            scene['cabinet_open'], scene['shutters_closed'] = cab, sh
            scene.frame_set(scene.frame_current)  # re-evaluate the state drivers
            render_and_pixelize(f"_cabinet-{'open' if cab else 'closed'}_shutters-{'closed' if sh else 'stowed'}")
    scene['cabinet_open'], scene['shutters_closed'] = saved
    scene.frame_set(scene.frame_current)


if __name__ == '__main__':
    render_and_pixelize()  # current toggle state; call render_all_states() for every combination
