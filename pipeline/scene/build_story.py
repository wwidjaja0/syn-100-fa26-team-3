"""Turn climate_shelter_pixel.blend into the two-day story run-through (no narrator).

blender -b --factory-startup climate_shelter_pixel.blend --python build_story.py [-- --render | --stills 1,300]

Day 1: wake, the PA speaker in the corner, open the shutters (heat floods in),
close them, inspect the PNW map, poke around, find mushrooms + papers, craft
and smoke the shroom cigarette, sleep. Day 2: worse heat, thunderstorm, peek
outside, pull the PA speaker down, fix the radio with it, tune the pirate
stations. Objects animate here; the video's cursor/UI/dither compositor
(post_story.py) is not part of this repo -- in the game, Godot does that live.
This script's job here is producing climate_shelter_story.blend, which
pipeline/godot/export_glb.py turns into assets/shelter.glb.
"""
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

# ---------------------------------------------------------------- new story props
story = bpy.data.collections.new('Story')
scene.collection.children.link(story)
OUTLINE_MAT = M['toon_outline']


def toon(name, rgb):
    """Copy of an existing toon material with a new base colour."""
    m = M['plaster_wall'].copy()
    m.name = name
    m.node_tree.nodes['Diffuse BSDF'].inputs['Color'].default_value = (*rgb, 1)
    return m


def glow(name, rgb, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new('ShaderNodeEmission')
    e.inputs['Color'].default_value = (*rgb, 1)
    e.inputs['Strength'].default_value = strength
    nt.links.new(e.outputs[0], nt.nodes.new('ShaderNodeOutputMaterial').inputs['Surface'])
    return m


def add_outline(o, thickness=0.016):
    o.data.materials.append(OUTLINE_MAT)
    md = o.modifiers.new('ToonOutline', 'SOLIDIFY')
    md.thickness, md.offset = thickness, 1.0
    md.use_flip_normals = md.use_even_offset = True
    md.use_rim = False
    md.material_offset = len(o.data.materials) - 1


def mesh_obj(name, bm, mat, loc=(0, 0, 0), parent=None, outline=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    story.objects.link(o)
    me.materials.append(mat)
    o.location = loc
    o.parent = parent
    if outline:
        add_outline(o)
    return o


def cube(name, loc, size, mat, **kw):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    return mesh_obj(name, bm, mat, loc, **kw)


def cone(name, loc, r1, r2, depth, mat, segs=14, **kw):
    """Along local +Z, r1 at -depth/2 and r2 at +depth/2."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    return mesh_obj(name, bm, mat, loc, **kw)


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.1
    story.objects.link(e)
    e.location = loc
    e.parent = parent
    e.rotation_mode = 'XYZ'
    return e


# --- PA speaker horn bolted to the corner post, wired along the ceiling beam
horn_mat, dark_mat = toon('pa_horn', (0.58, 0.60, 0.50)), toon('pa_mouth', (0.07, 0.07, 0.08))
steel_mat, cable_mat = toon('pa_bracket', (0.30, 0.31, 0.33)), toon('pa_cable', (0.05, 0.05, 0.05))
led_mat = glow('pa_led', (1.0, 0.08, 0.04), 8.0)
SPK_MOUNT = Vector((HALF_W + 0.04, WALL_Y - 0.14, 2.68))
spk_rig = empty('speaker_rig', SPK_MOUNT)
cube('pa_wall_plate', (0, 0.01, 0), (0.05, 0.02, 0.2), steel_mat, parent=spk_rig)
cube('pa_arm', (0, -0.08, -0.02), (0.04, 0.16, 0.04), steel_mat, parent=spk_rig)
aim = empty('speaker_aim', (0, -0.19, -0.06), parent=spk_rig)
aim.rotation_mode = 'QUATERNION'
aim.rotation_quaternion = Vector((-0.86, -0.42, -0.28)).normalized().to_track_quat('Z', 'Y')
spk_parts = [
    cube('pa_yoke', (0, 0, -0.02), (0.27, 0.035, 0.035), steel_mat, parent=aim),
    cone('pa_driver', (0, 0, -0.12), 0.11, 0.11, 0.18, toon('pa_driver', (0.20, 0.21, 0.20)), parent=aim),
    cone('pa_horn', (0, 0, 0.17), 0.07, 0.30, 0.44, horn_mat, segs=16, parent=aim),
    cone('pa_mouth', (0, 0, 0.385), 0.27, 0.27, 0.012, dark_mat, segs=16, parent=aim, outline=False),
    cube('pa_led', (0.0, 0.113, -0.14), (0.035, 0.025, 0.035), led_mat, parent=aim, outline=False),
]
spk_parts += [o for o in story.objects if o.name in ('pa_wall_plate', 'pa_arm')]
bpy.context.view_layer.update()
driver_back = aim.matrix_world @ Vector((0, 0, -0.21))
beam_pt = Vector((driver_back.x, WALL_Y - 0.25, 2.93))
cable_pivot = empty('pa_cable_pivot', beam_pt)
drop = beam_pt - driver_back
bmc = bmesh.new()
bmesh.ops.create_cone(bmc, cap_ends=True, segments=6, radius1=0.012, radius2=0.012, depth=1.0)
bmesh.ops.translate(bmc, vec=(0, 0, -0.5), verts=bmc.verts)
cable = mesh_obj('pa_cable_drop', bmc, cable_mat, (0, 0, 0), parent=cable_pivot)
cable.scale.z = drop.length
cable_pivot.rotation_mode = 'QUATERNION'
cable_tip = cube('pa_cable_tip', (0, 0, -1.0), (0.03, 0.03, 0.05), toon('pa_copper', (0.85, 0.42, 0.15)),
                 parent=cable, outline=False)
cable_tip.scale = (1, 1, 1 / max(drop.length, 1e-3))
cube('pa_beam_cable', ((beam_pt.x - HALF_W) / 2, WALL_Y - 0.258, 2.975), (beam_pt.x + HALF_W, 0.016, 0.016), cable_mat,
     outline=False)
for cx in (4.4, 2.8, 1.0, -0.8, -2.6, -4.4):
    cube(f'pa_cable_clip_{cx}', (cx, WALL_Y - 0.262, 2.975), (0.03, 0.02, 0.04), steel_mat, outline=False)

# --- the Pacific Northwest map pinned to the back wall
MAP_META = json.loads((HERE / 'map_meta.json').read_text())
MAP_C, MAP_W = Vector((0.78, WALL_Y - 0.012, 2.06)), 0.70
MAP_H = MAP_W * MAP_META['sheet'][1] / MAP_META['sheet'][0]
map_mat = toon('pnw_map', (1, 1, 1))
tex = map_mat.node_tree.nodes.new('ShaderNodeTexImage')
tex.image = bpy.data.images.load(str(HERE / 'map_texture.png'))
tex.image.pack()
tex.interpolation = 'Linear'
map_mat.node_tree.links.new(tex.outputs['Color'], map_mat.node_tree.nodes['Diffuse BSDF'].inputs['Color'])
bm = bmesh.new()
uv = bm.loops.layers.uv.new()
vs = [bm.verts.new((sx * MAP_W / 2, 0, sz * MAP_H / 2)) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
face = bm.faces.new(vs)
for loop, co in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
    loop[uv].uv = co
map_obj = mesh_obj('pnw_map', bm, map_mat, MAP_C, outline=False)
pin_mat = toon('map_pin', (0.75, 0.12, 0.08))
map_parts = [map_obj] + [cube(f'map_pin_{k}', MAP_C + Vector((sx * (MAP_W / 2 - 0.03), -0.012, sz * (MAP_H / 2 - 0.03))),
                              (0.025, 0.02, 0.025), pin_mat, outline=False)
                         for k, (sx, sz) in enumerate(((-1, 1), (1, 1), (-1, -1), (1, -1)))]

# --- dried mushrooms jar replaces a tin on the cabinet's top shelf
tin = next(o for o in cab_closed.objects if o.name.startswith('supply_tin_or_canister_0015'))
bpy.context.view_layer.update()
tin_lo = Vector(min(((tin.matrix_world @ Vector(c)) for c in tin.bound_box), key=lambda v: v.z))
tin_c = sum(((tin.matrix_world @ Vector(c)) for c in tin.bound_box), Vector()) / 8
show(tin, False)
JAR = Vector((tin_c.x, tin_c.y, tin_lo.z))
jar_parts = [
    cone('jar_glass', JAR + Vector((0, 0, 0.09)), 0.075, 0.075, 0.18, toon('jar_glass', (0.55, 0.68, 0.60))),
    cone('jar_mushrooms', JAR + Vector((0, -0.01, 0.07)), 0.068, 0.068, 0.12, toon('jar_mushrooms', (0.42, 0.26, 0.13)),
         outline=False),
    cone('jar_lid', JAR + Vector((0, 0, 0.195)), 0.07, 0.07, 0.035, toon('jar_lid', (0.55, 0.14, 0.08))),
    cube('jar_label', JAR + Vector((0, -0.075, 0.09)), (0.09, 0.008, 0.06), toon('jar_label', (0.88, 0.80, 0.60)),
         outline=False),
]

# --- rolling papers on the bench, right of the lantern
BENCH_TOP = 0.971
PAPERS = Vector((3.62, 1.22, BENCH_TOP))
papers_parts = [
    cube('papers_booklet', PAPERS + Vector((0, 0, 0.016)), (0.17, 0.11, 0.032), toon('papers_cover', (0.80, 0.35, 0.10))),
    cube('papers_sheet', PAPERS + Vector((0, 0.02, 0.04)), (0.14, 0.05, 0.02), toon('papers_sheet', (0.95, 0.92, 0.84)),
         outline=False),
]
for o in papers_parts:
    o.rotation_euler.z = math.radians(-12)

# --- broken radio: speaker pulled out, wires hanging, dead display
radio_root = bpy.data.objects['02_emergency_weather_radio']
radio_meshes = [o for o in radio_root.children_recursive if o.type == 'MESH']
grill = [o for o in radio_meshes if 'speaker_grill_bar' in o.name or 'speaker_panel' in o.name]
panel = next(o for o in grill if 'speaker_panel' in o.name)
hole = panel.copy()
hole.data = panel.data.copy()
hole.name = 'radio_speaker_hole'
hole.data.materials[0] = toon('radio_hole', (0.012, 0.010, 0.010))
story.objects.link(hole)
hole.parent = panel.parent
hole.matrix_world = panel.matrix_world.copy()
bpy.context.view_layer.update()
pc = sum((panel.matrix_world @ Vector(c) for c in panel.bound_box), Vector()) / 8
wires = [cube('radio_wire_red', pc + Vector((-0.03, -0.06, -0.02)), (0.012, 0.09, 0.012), toon('wire_red', (0.8, 0.1, 0.05)),
              outline=False),
         cube('radio_wire_yel', pc + Vector((0.04, -0.05, -0.05)), (0.012, 0.07, 0.012), toon('wire_yel', (0.9, 0.75, 0.1)),
              outline=False)]
wires[0].rotation_euler = (0.5, 0, 0.6)
wires[1].rotation_euler = (-0.7, 0, -0.4)
lcd_emit = [m.node_tree.nodes['Emission'] for m in M if m.name.startswith('mat_lcd_')
            and m.node_tree and m.node_tree.nodes.get('Emission')]

# ---------------------------------------------------------------- hinge rigs
def centre(o):
    return sum((o.matrix_world @ Vector(c) for c in o.bound_box), Vector()) / 8


def rig(meshes, pivot_meshes, split_x, name):
    hinges = {}
    for side in (-1, 1):
        pins = [centre(o) for o in pivot_meshes if (centre(o).x - split_x) * side > 0]
        p = sum(pins, Vector()) / len(pins)
        e = bpy.data.objects.new(f'{name}_hinge_{"L" if side < 0 else "R"}', None)
        e.empty_display_type = 'SINGLE_ARROW'
        e.location = (p.x, p.y, p.z)
        e.rotation_mode = 'XYZ'
        meshes[0].users_collection[0].objects.link(e)
        hinges[side] = e
    bpy.context.view_layer.update()
    for o in meshes:
        side = -1 if centre(o).x < split_x else 1
        mw = o.matrix_world.copy()
        o.parent = hinges[side]
        o.matrix_parent_inverse = hinges[side].matrix_world.inverted()
        o.matrix_world = mw
    return hinges


bpy.context.view_layer.update()
sh_meshes = [o for o in sh_closed.objects if o.type == 'MESH']
sh_hinges = rig(sh_meshes, [o for o in sh_meshes if 'heavy_hinge' in o.name], WIN_X, 'shutter')
CAB_X = 4.5
door_parts = ('removable_door_panel', 'door_vertical_plank_seam', 'door_inset_trim', 'door_pull', 'keyhole')
cab_meshes = [o for o in cab_closed.objects if o.type == 'MESH' and not o.hide_render]
doors = [o for o in cab_meshes if any(k in o.name for k in door_parts)]
door_hinges = rig(doors, [o for o in cab_meshes if 'hinge_pin' in o.name], CAB_X, 'cabinet')

# ---------------------------------------------------------------- camera (locked first-person, ortho)
ORTHO = 6.6
TILT = math.radians(8)
PIX = ORTHO / W
CX_L, CX_R = WIN_X, 2.6
cam_data = bpy.data.cameras.new('fp_cam')
cam_data.type = 'ORTHO'
cam_data.ortho_scale = ORTHO
cam_data.clip_end = 40
cam = bpy.data.objects.new('fp_cam', cam_data)
colls['Lights_Camera'].objects.link(cam)
cam.rotation_euler = (math.pi / 2 - TILT, 0, 0)
scene.camera = cam
LOOK_Y, LOOK_Z, DIST = WALL_Y, 1.55, 12


def cam_at(x):
    return Vector((x, LOOK_Y - DIST * math.cos(TILT), LOOK_Z + DIST * math.sin(TILT)))


# ---------------------------------------------------------------- easing + per-frame state
def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def out_back(t, s=1.2):
    t = min(max(t, 0.0), 1.0) - 1
    return 1 + (s + 1) * t ** 3 + s * t ** 2


def ramp(f, a, b, ease=smooth):
    return ease((f - a) / (b - a)) if b > a else float(f >= b)


SH_ANGLE, DOOR_ANGLE = math.radians(176), math.radians(105)


def shutter_cycle(f, opening, closing):
    if f < closing[0]:
        return ramp(f, *opening, ease=out_back)
    a, b = closing
    v = 1 - ramp(f, a, b, ease=lambda t: t ** 2.2)
    if f > b:
        v = 0.025 * math.exp(-(f - b) / 4) * abs(math.sin((f - b) * 0.9))
    return v


def shutter_open(f):
    if f < DAY2:
        return shutter_cycle(f, T['sh_open'], T['sh_close'])
    return shutter_cycle(f, T['sh_open2'], T['sh_close2'])


def door_open(f):
    return ramp(f, *T['cab_open'], ease=out_back)


PANS = [(T['pan1'], CX_R, CX_L), (T['pan2'], CX_L, CX_R), (T['pan3'], CX_R, CX_L), (T['pan4'], CX_L, CX_R)]


def cam_x(f):
    x = CX_R
    for (a, b), x0, x1 in PANS:
        if f >= a:
            x = x0 + (x1 - x0) * ramp(f, a, b)
    return CX_L + round((x - CX_L) / PIX) * PIX            # whole-pixel steps keep the art crisp


def flash(f):
    v = 0.0
    for s in STRIKES:
        if f >= s:
            v += math.exp(-(f - s) / 1.6)
        if f >= s + 4:
            v += 0.7 * math.exp(-(f - s - 4) / 2.0)
    return min(v, 1.4)


def speaker_pose(f):
    """(offset, euler) of the speaker rig: bolted, yanked, falling, lying on the floor."""
    a, b = T['spk_yank']
    if f < a:
        return Vector(), (0, 0, 0)
    if f < b:
        k = (f - a) / (b - a)
        amp = 0.03 + 0.10 * k
        return Vector((0, -0.02 * k, 0)), (amp * math.sin(f * 1.9), 0, amp * 0.8 * math.sin(f * 2.7 + 1))
    a, b = T['spk_fall']
    t = min((f - a) / (b - a), 1.0)
    drop = SPK_MOUNT.z - 0.30
    off = Vector((0.06 * t, -0.42 * t, -drop * t * t))
    if t >= 1:                                              # small bounce on landing
        k = f - b
        off.z += 0.05 * math.exp(-k / 2) * abs(math.sin(k * 1.4))
    return off, (1.7 * t, 0.6 * t, 0.3 * t)


def cable_swing(f):
    a = T['spk_fall'][0]
    if f < a:
        return None
    k = f - a
    return 0.55 * math.exp(-k / 18) * math.sin(k * 0.32)


# lights we animate
lantern = bpy.data.objects['lantern_glow']
cab_glow_data = bpy.data.lights.new('cabinet_interior', 'POINT')
cab_glow_data.color, cab_glow_data.shadow_soft_size = (1.0, 0.72, 0.42), 0.2
cab_glow = bpy.data.objects.new('cabinet_interior', cab_glow_data)
cab_glow.location = (CAB_X - 0.15, 0.75, 1.55)
colls['Lights_Camera'].objects.link(cab_glow)
radio_glow_data = bpy.data.lights.new('radio_glow', 'POINT')
radio_glow_data.color, radio_glow_data.shadow_soft_size = (0.45, 1.0, 0.70), 0.15
radio_glow = bpy.data.objects.new('radio_glow', radio_glow_data)
radio_glow.location = (pc.x + 0.25, pc.y - 0.35, pc.z + 0.05)
colls['Lights_Camera'].objects.link(radio_glow)
rim = bpy.data.objects.get('storm_moon_rim')
rim_e0 = rim.data.energy if rim else 0
storm_c0 = tuple(storm_light.data.color)
world_bg = scene.world.node_tree.nodes.get('Background') if scene.world and scene.world.use_nodes else None
world_c0 = tuple(world_bg.inputs['Color'].default_value) if world_bg else None

# storm sky: day 1 ramp (bright blue) and a day 2 ramp (bruised orange) mixed by a keyed factor
sky = M['storm_window_emit'].node_tree
noise = next(n for n in sky.nodes if n.bl_idname == 'ShaderNodeTexNoise')
noise.noise_dimensions = '4D'
ramp1 = next(n for n in sky.nodes if n.bl_idname == 'ShaderNodeValToRGB')
els = ramp1.color_ramp.elements
els[0].color = (0.03, 0.12, 0.40, 1)
els[-1].color = (0.80, 0.95, 1.0, 1)
for e in els:
    if 0.5 < e.position < 0.6:
        e.color = (0.10, 0.42, 0.95, 1)
ramp2 = sky.nodes.new('ShaderNodeValToRGB')
e2 = ramp2.color_ramp.elements
e2[0].position, e2[0].color = 0.30, (0.04, 0.012, 0.012, 1)
e2[1].position, e2[1].color = 0.80, (1.0, 0.62, 0.25, 1)
e2.new(0.55).color = (0.42, 0.10, 0.03, 1)
sky.links.new(noise.outputs['Fac'], ramp2.inputs['Fac'])
mix = sky.nodes.new('ShaderNodeMix')
mix.data_type = 'RGBA'
sock = {s.identifier: s for s in mix.inputs}
sky.links.new(ramp1.outputs['Color'], sock['A_Color'])
sky.links.new(ramp2.outputs['Color'], sock['B_Color'])
sky_emit = next(n for n in sky.nodes if n.bl_idname == 'ShaderNodeEmission')
sky.links.new(next(s for s in mix.outputs if s.identifier == 'Result_Color'), sky_emit.inputs['Color'])
mix_fac = sock['Factor_Float']
led_emit = led_mat.node_tree.nodes['Emission']

def key(idb, path, f, **kw):
    idb.keyframe_insert(path, frame=f, **kw)


fix = T['radio_fix']
for f in range(F_START, F_END + 1):
    so, do, fl = shutter_open(f), door_open(f), flash(f)
    day2 = f >= DAY2
    sh_hinges[-1].rotation_euler.z = -SH_ANGLE * so
    sh_hinges[1].rotation_euler.z = SH_ANGLE * so
    door_hinges[-1].rotation_euler.z = -DOOR_ANGLE * do
    door_hinges[1].rotation_euler.z = DOOR_ANGLE * do
    for o in (*sh_hinges.values(), *door_hinges.values()):
        key(o, 'rotation_euler', f, index=2)
    cam.location = cam_at(cam_x(f))
    key(cam, 'location', f)
    # window light: cool blue day 1, hot orange on day 2, white-blue lightning
    if day2:
        base = (1.0, 0.48, 0.22)
        storm_light.data.energy = 380 + 600 * min(so, 1.0) + 2600 * fl
        storm_light.data.color = tuple(base[i] + (0.85 - base[i]) * min(fl, 1) for i in range(3))
    else:
        storm_light.data.energy = 420 + 520 * min(so, 1.0)
        storm_light.data.color = storm_c0
    key(storm_light.data, 'energy', f)
    key(storm_light.data, 'color', f)
    if rim:
        rim.data.energy = rim_e0 * (1 + 4 * fl) if day2 else rim_e0
        key(rim.data, 'energy', f)
    cab_glow_data.energy = 160 * do
    key(cab_glow_data, 'energy', f)
    sky_emit.inputs['Strength'].default_value = 2.5 + (4.0 * fl if day2 else 0)
    key(sky_emit.inputs['Strength'], 'default_value', f)
    # PA "live" lamp: steady glow that breathes, dead once it is torn down
    led_emit.inputs['Strength'].default_value = (6 + 3 * math.sin(f * 0.21)) if f < T['spk_yank'][1] else 0.0
    key(led_emit.inputs['Strength'], 'default_value', f)
    # radio: dead LCD, one sputter when poked on day 1, alive once fixed
    if f >= fix:
        lcd = 3.0 * min((f - fix) / 6, 1) * (0.85 + 0.15 * math.sin(f * 0.9))
    else:
        k = f - T['radio_click1']
        lcd = {1: 2.0, 2: 1.2, 3: 0.0, 5: 1.5, 6: 0.4}.get(k, 0.0)
    for n in lcd_emit:
        n.inputs['Strength'].default_value = lcd
        key(n.inputs['Strength'], 'default_value', f)
    radio_glow_data.energy = 30 * min(max((f - fix) / 6, 0), 1)
    key(radio_glow_data, 'energy', f)
    # speaker torn down
    off, rot = speaker_pose(f)
    spk_rig.location = SPK_MOUNT + off
    spk_rig.rotation_euler = rot
    key(spk_rig, 'location', f)
    key(spk_rig, 'rotation_euler', f)
    sw = cable_swing(f)
    if sw is None:
        cable.scale.z = drop.length
        q = (-drop).normalized().to_track_quat('-Z', 'Y')
    else:
        cable.scale.z = drop.length + 0.22 * min((f - T['spk_fall'][0]) / 4, 1)
        q = Matrix.Rotation(sw, 4, 'X').to_quaternion()
    cable_pivot.rotation_quaternion = q
    cable_tip.scale.z = 1 / cable.scale.z
    key(cable, 'scale', f, index=2)
    key(cable_tip, 'scale', f, index=2)
    key(cable_pivot, 'rotation_quaternion', f)

# day 2 sky + ambience: switch ramps and warm the world while the screen is black
for f, v in ((DAY2 - 1, 0.0), (DAY2, 1.0)):
    mix_fac.default_value = v
    key(mix_fac, 'default_value', f)
    if world_bg:
        world_bg.inputs['Color'].default_value = world_c0 if v == 0 else (0.10, 0.035, 0.03, 1)
        key(world_bg.inputs['Color'], 'default_value', f)
noise.inputs['W'].default_value = 0
key(noise.inputs['W'], 'default_value', F_START)
noise.inputs['W'].default_value = 2.2 * DAY2 / 600
key(noise.inputs['W'], 'default_value', DAY2)
noise.inputs['W'].default_value = 2.2 * DAY2 / 600 + 3.0 * (F_END - DAY2) / 600
key(noise.inputs['W'], 'default_value', F_END)

# visibility switches: grabbed items vanish, the radio gets its speaker back


def vis(objs, f, visible):
    for o in objs:
        show(o, not visible)
        key(o, 'hide_render', f - 1); key(o, 'hide_viewport', f - 1)
        show(o, visible)
        key(o, 'hide_render', f); key(o, 'hide_viewport', f)


vis(jar_parts, T['jar_click'] + 1, False)
vis(papers_parts, T['papers_click'] + 1, False)
vis(spk_parts, T['spk_gone'], False)
vis([hole, *wires], fix, False)
vis(grill, fix, True)

# lantern flicker plus a flare when it is clicked
lantern.data.keyframe_insert('energy', frame=F_START)
e0 = lantern.data.energy
for f, mul in ((T['lantern_click'], 1.0), (T['lantern_click'] + 3, 2.6), (T['lantern_click'] + 30, 1.0)):
    lantern.data.energy = e0 * mul
    lantern.data.keyframe_insert('energy', frame=f)
lantern.data.energy = e0
fc = lantern.data.animation_data.action.fcurves[0]
nz = fc.modifiers.new('NOISE')
nz.scale, nz.strength, nz.phase = 2.5, 40, 3.7

for idb in [o for o in bpy.data.objects if o.animation_data and o.animation_data.action] + \
           [d for d in (*bpy.data.lights, *bpy.data.materials, *bpy.data.worlds)
            if getattr(d, 'animation_data', None) and d.animation_data.action] + \
           [n for n in (sky, *[m.node_tree for m in M if m.node_tree], *([scene.world.node_tree] if world_bg else []))
            if n.animation_data and n.animation_data.action]:
    for fcu in idb.animation_data.action.fcurves:
        if fcu.modifiers:
            continue
        for k in fcu.keyframe_points:
            stepped = idb is cam or 'hide' in fcu.data_path or 'Factor' in fcu.data_path \
                or fcu.data_path.startswith('nodes["Background"]')
            k.interpolation = 'CONSTANT' if stepped else 'LINEAR'

# ---------------------------------------------------------------- object masks (cryptomatte -> 3 RGB files x 6)
main_layer = scene.view_layers[0]
main_layer.use_pass_cryptomatte_object = True
if 'Mask' in scene.view_layers:
    scene.view_layers.remove(scene.view_layers['Mask'])


def kids(root_name):
    return [o.name for o in bpy.data.objects[root_name].children_recursive if o.type == 'MESH']


GROUPS = {
    'shutters': [o.name for o in sh_meshes],
    'cabinet': [o.name for o in cab_meshes if o not in jar_parts],
    'map': [o.name for o in map_parts],
    'speaker': [o.name for o in spk_parts],
    'radio': [o.name for o in radio_meshes] + [hole.name] + [w.name for w in wires],
    'jar': [o.name for o in jar_parts],
    'papers': [o.name for o in papers_parts],
    'bench': kids('01_wooden_workbench'),
    'sky': ['storm_window_emit'],
    'lantern': kids('10_emergency_lantern'),
    'instruments': kids('08_wall_weather_instruments'),
    'power': kids('04_portable_power_station'),
    'filter': kids('07_gravity_water_filter'),
    'crates': kids('09_supply_crates'),
    'sandbags': kids('06_sandbag_flood_barrier'),
    'flashlight': kids('11_flashlight'),
}
names = list(GROUPS)
MASK_FILES = [names[i:i + 3] for i in range(0, len(names), 3)]

scene.use_nodes = True
tree = scene.node_tree
tree.nodes.clear()
rl = tree.nodes.new('CompositorNodeRLayers'); rl.layer = main_layer.name
comp = tree.nodes.new('CompositorNodeComposite'); comp.location = (400, 200)
tree.links.new(rl.outputs['Image'], comp.inputs['Image'])
fo = tree.nodes.new('CompositorNodeOutputFile'); fo.location = (900, -300)
fo.base_path = str(ANIM / 'mask')
fo.format.file_format = 'PNG'
fo.format.color_mode = 'RGB'
fo.file_slots[0].path = 'm0_'
for j in range(1, len(MASK_FILES)):
    fo.file_slots.new(f'm{j}_')
for j, trio in enumerate(MASK_FILES):
    combine = tree.nodes.new('CompositorNodeCombineColor'); combine.location = (600, -300 - 300 * j)
    for i, key_name in enumerate(trio):
        cm = tree.nodes.new('CompositorNodeCryptomatteV2'); cm.location = (200, -200 - 300 * j - 100 * i)
        cm.source = 'RENDER'
        cm.scene = scene
        cm.layer_name = f'{main_layer.name}.CryptoObject'
        cm.matte_id = ','.join(GROUPS[key_name])
        tree.links.new(rl.outputs['Image'], cm.inputs['Image'])
        tree.links.new(cm.outputs['Matte'], combine.inputs[i])
    tree.links.new(combine.outputs['Image'], fo.inputs[j])

scene.frame_start, scene.frame_end = F_START, F_END
scene.render.fps = FPS
scene.eevee.taa_render_samples = 64
scene.render.filepath = str(ANIM / 'raw' / 'frame_')
scene.render.image_settings.file_format = 'PNG'


# ---------------------------------------------------------------- cursor path + UI layout (screen space, low-res px)
def screen(world, f):
    scene.frame_set(f)
    u, v, _ = world_to_camera_view(scene, cam, Vector(world))
    return (u * W, (1 - v) * H)


def group_pt(name, f, dz=0.0):
    scene.frame_set(f)
    objs = [bpy.data.objects[n] for n in GROUPS[name]]
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    c = sum(pts, Vector()) / len(pts)
    return screen(c + Vector((0, 0, dz)), f)


INV = [(196 + 22 * i, 245) for i in range(4)]          # inventory slot top-left, 20x20
INV_C = [(x + 10, y + 10) for x, y in INV]
MPW, MPH = MAP_META['size']
MAP_PANEL = ((W - MPW) // 2, (H - MPH) // 2 - 6)
CRAFT = dict(panel=(140, 62, 340, 168), a=(166, 92), b=(214, 92), out=(286, 92), btn=(196, 136, 266, 154))
RADIO = dict(panel=(40, 10, 440, 120), knob=(410, 44))


def ui_c(r):
    return ((r[0] + r[2]) / 2, (r[1] + r[3]) / 2)


def slot_c(p):
    return (p[0] + 12, p[1] + 12)


SH_L = (WIN_X - 0.45, 1.85, 1.45)
SKY = (WIN_X + 0.1, 2.0, 1.75)
SH_R_OPEN = (WIN_X + 1.49 + 0.72, 1.70, 1.40)
CAB = (CAB_X - 0.22, 1.30, 1.25)
map_pin = (MAP_PANEL[0] + MAP_META['pin'][0], MAP_PANEL[1] + MAP_META['pin'][1])
map_x = (MAP_PANEL[0] + MAP_META['close'][0], MAP_PANEL[1] + MAP_META['close'][1])
spk_pt = group_pt('speaker', T['spk_click'])
rk = RADIO['knob']
way = [  # (frame, screen xy | world xyz | group name)
    (1, (240, 150)), (110, (240, 150)), (140, 'speaker'), (176, 'speaker'), (190, (250, 120)), (260, (250, 120)),
    (285, SH_L), (310, SH_L), (350, SKY), (380, (SKY[0] + 0.3, SKY[1], SKY[2] - 0.2)), (420, SKY),
    (445, SH_R_OPEN), (470, SH_R_OPEN),
    (530, 'map'), (562, 'map'), (585, map_pin), (650, (map_pin[0] + 3, map_pin[1] + 2)), (688, map_x), (705, map_x),
    (722, 'filter'), (738, 'filter'), (754, 'crates'), (768, 'crates'), (784, 'sandbags'), (798, 'sandbags'),
    (870, (240, 140)),
    (893, 'radio'), (915, 'radio'), (935, 'instruments'), (950, 'instruments'), (962, 'lantern'), (985, 'lantern'),
    (998, CAB), (1015, CAB),
    (1058, 'jar'), (1080, 'jar'), (1105, 'papers'), (1126, 'papers'), (1150, 'bench'), (1166, 'bench'),
    (1180, INV_C[0]), (1192, INV_C[0]), (1200, INV_C[1]), (1212, INV_C[1]), (1224, ui_c(CRAFT['btn'])),
    (1238, ui_c(CRAFT['btn'])), (1252, slot_c(CRAFT['out'])), (1262, slot_c(CRAFT['out'])),
    (1290, INV_C[0]), (1304, INV_C[0]), (1340, (250, 160)),
    (1600, (240, 150)), (1675, (240, 150)),
    (1695, SH_L), (1712, SH_L), (1752, SKY), (1790, (SKY[0] - 0.3, SKY[1], SKY[2] + 0.1)), (1812, SH_R_OPEN),
    (1840, SH_R_OPEN), (1885, (260, 120)), (1955, (260, 120)),
    (1975, spk_pt), (2000, spk_pt), (2030, (330, 200)), (2052, INV_C[0]), (2064, INV_C[0]),
    (2085, 'radio'), (2100, 'radio'), (2112, rk), (F_END, rk),
]


def resolve(f, p):
    if isinstance(p, str):
        return group_pt(p, f)
    return p if len(p) == 2 else screen(p, f)


way = [(f, resolve(f, p)) for f, p in way]


def cursor(f):
    for (fa, pa), (fb, pb) in zip(way, way[1:]):
        if fa <= f <= fb:
            t = smooth((f - fa) / (fb - fa)) if fb > fa else 1
            return (pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t)
    return way[-1][1]


points = {  # screen positions post_story needs, with the cam_px they were measured at
    'jar': (group_pt('jar', T['jar_click']), T['jar_click']),
    'papers': (group_pt('papers', T['papers_click']), T['papers_click']),
    'speaker_floor': (group_pt('speaker', T['spk_gone'] - 2), T['spk_gone'] - 2),
    'radio_hole': (screen(pc, T['radio_click1']), T['radio_click1']),
    'window': (screen((WIN_X, WALL_Y, 1.53), T['sh_click1']), T['sh_click1']),
}

timeline = {
    'size': [W, H], 'fps': FPS, 'frames': [F_START, F_END], 'T': T, 'strikes': STRIKES, 'clicks': CLICKS,
    'mask_files': MASK_FILES, 'inv': INV, 'map_panel': MAP_PANEL, 'craft': CRAFT, 'radio': RADIO,
    'points': {k: {'xy': v[0], 'cam_px': round((cam_x(v[1]) - CX_L) / PIX)} for k, v in points.items()},
    'per_frame': {f: {'cursor': cursor(f), 'cam_px': round((cam_x(f) - CX_L) / PIX),
                      'shutter': shutter_open(f), 'flash': flash(f)}
                  for f in range(F_START, F_END + 1)},
}
ANIM.mkdir(exist_ok=True)
(ANIM / 'timeline.json').write_text(json.dumps(timeline))
scene.frame_set(F_START)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE / 'climate_shelter_story.blend'))
print('Saved story scene + timeline')

if '--frames' in argv:
    a = argv.index('--frames')
    scene.frame_start, scene.frame_end = int(argv[a + 1]), int(argv[a + 2])
if '--stills' in argv:
    raw = scene.render.filepath
    for f in map(int, argv[argv.index('--stills') + 1].split(',')):
        scene.frame_set(f)
        scene.render.filepath = f'{raw}{f:04d}.png'
        bpy.ops.render.render(write_still=True)
    scene.render.filepath = raw
if '--render' in argv:
    bpy.ops.render.render(animation=True)
    print('STORY RENDER DONE')
