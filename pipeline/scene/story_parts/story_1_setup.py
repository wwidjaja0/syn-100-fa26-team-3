# Part of pipeline/scene/build_story.py, which runs the parts in order in one shared
# namespace: names defined in earlier parts are used here as-is. Run build_story.py, not this.
#
# Setup: imports and constants, the story clock (T: when each beat happens, in 24 fps frames),
# freezing the shutters/cabinet toggles, and extending the room for the camera pans.
# The game needs this part.

import bpy, bmesh, math, sys, json
from pathlib import Path
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view

HERE = Path(bpy.data.filepath).parent
ANIM = HERE / 'story'
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
scene = bpy.context.scene
W, H = scene.render.resolution_x, scene.render.resolution_y
FPS = 24
WALL_Y, WIN_X, HALF_W = 2.0, -1.5, 5.2
M = bpy.data.materials
colls = bpy.data.collections

# ---------------------------------------------------------------- the story clock (frames @ 24 fps)
T = dict(
    title1=(1, 40), wake1=(40, 110),
    pan1=(190, 260), sh_click1=300, sh_open=(302, 350), sh_click2=455, sh_close=(457, 505),
    map_click=560, map_close=700,
    pan2=(800, 870), radio_click1=905, lantern_click=970,
    cab_click=1005, cab_open=(1007, 1043), jar_click=1075, papers_click=1120,
    bench_click=1160, craft_a=1188, craft_b=1208, craft_btn=1232, craft_take=1258,
    use_click=1300, sleep=(1400, 1460), title2=(1470, 1525), wake2=(1530, 1600),
    pan3=(1615, 1675), sh_click3=1705, sh_open2=(1707, 1750), sh_click4=1825, sh_close2=(1827, 1870),
    pan4=(1885, 1955), spk_click=1985, spk_yank=(1987, 2005), spk_fall=(2005, 2020), spk_gone=2024,
    inv_spk_click=2060, radio_fix=2095, radio_ui=(2105, 2600),
    stations=[(2115, 2240), (2255, 2380), (2395, 2520)], fade=(2535, 2595),
)
F_START, F_END = 1, 2600
STRIKES = [1585, 1640, 1722, 1758, 1790, 1850, 1930, 2010, 2090, 2170, 2262, 2345, 2440, 2500, 2560]
CLICKS = [T[k] for k in ('sh_click1', 'sh_click2', 'map_click', 'map_close', 'radio_click1', 'lantern_click',
                         'cab_click', 'jar_click', 'papers_click', 'bench_click', 'craft_a', 'craft_b',
                         'craft_btn', 'craft_take', 'use_click', 'sh_click3', 'sh_click4', 'spk_click',
                         'inv_spk_click', 'radio_fix')]
DAY2 = T['title2'][0]

# ---------------------------------------------------------------- freeze the toggle states
sh_closed, sh_stowed = colls['Shutters_Closed'], colls['Shutters_Stowed']
cab_open, cab_closed = colls['Cabinet_Open'], colls['Cabinet_Closed']
for c in (sh_closed, sh_stowed, cab_open, cab_closed):
    for o in c.objects:
        o.driver_remove('hide_viewport')
        o.driver_remove('hide_render')
storm_light = bpy.data.objects['storm_window']
storm_light.data.driver_remove('energy')


def show(o, visible):
    o.hide_viewport = o.hide_render = not visible


for o in sh_closed.objects:
    show(o, True)
for o in sh_stowed.objects:
    show(o, o.name.startswith('window_'))
for o in cab_closed.objects:
    show(o, True)
for o in list(cab_open.objects):
    keep = 'supply_tin' in o.name
    show(o, keep)
    if keep:
        mw = o.matrix_world.copy()
        cab_open.objects.unlink(o)
        cab_closed.objects.link(o)
        o.parent = None
        o.matrix_world = mw

bpy.context.view_layer.update()  # objects hidden in the source file carry stale matrices
for o in cab_closed.objects:
    if 'cabinet_shell' in o.name:
        bm = bmesh.new(); bm.from_mesh(o.data)
        rot = o.matrix_world.to_3x3()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if (rot @ f.normal).normalized().y < -0.9], context='FACES_ONLY')
        bm.to_mesh(o.data); bm.free()
    if 'inset_dark_interior' in o.name:
        o.matrix_world = Matrix.Translation((0, 0.53, 0)) @ o.matrix_world
bpy.data.objects['07_gravity_water_filter'].location.y -= 0.45

# ---------------------------------------------------------------- room extension for the pans
room = colls['Room']


def box(name, loc, size, mat, coll=room):
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bm.to_mesh(me); bm.free()
    o.location = loc
    me.materials.append(mat)
    return o


EXT = 7.2
box('back_wall_ext', ((HALF_W + EXT) / 2, WALL_Y + 0.1, 1.6), (EXT - HALF_W, 0.2, 3.2), M['plaster_wall'])
box('upper_wall', ((EXT - HALF_W) / 2, WALL_Y + 0.1, 3.55), (EXT + HALF_W, 0.2, 0.7), M['plaster_wall'])
box('baseboard_ext', ((HALF_W + EXT) / 2, WALL_Y - 0.02, 0.08), (EXT - HALF_W, 0.06, 0.16), M['timber_beam'])
box('ceiling_beam_ext', ((HALF_W + EXT) / 2, WALL_Y - 0.12, 3.05), (EXT - HALF_W, 0.25, 0.25), M['timber_beam'])
x, i = HALF_W + 0.1, 100
while x < EXT:
    box(f'floor_plank_{i}', (x + 0.15, 0.5, -0.03), (0.29, 3.2, 0.06), M[f'floor_plank_{(i * 7) % 4}'])
    x += 0.3
    i += 1
box('subfloor', (1.0, 0.5, -0.09), (2 * EXT + 2, 3.4, 0.05), M['timber_beam'])
box('corner_post', (HALF_W + 0.1, WALL_Y - 0.06, 1.55), (0.18, 0.14, 3.1), M['timber_beam'])
