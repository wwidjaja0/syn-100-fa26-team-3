"""Build a pixel-art / toon shelter scene from the climate_shelter_3d GLBs.

blender -b --factory-startup --python build_pixel_scene.py [-- --no-render]

Imports every asset, lays them out in a cutaway room (cabinet open/closed and
shutters closed/stowed are toggled by Scene custom properties), converts materials to
banded toon shading with inverted-hull outlines, lights it warm-inside /
storm-blue-outside, saves climate_shelter_pixel.blend, renders a low-res
frame and palette-maps + nearest-upscales it (see pixelize.py).
"""
import bpy, math, sys, json
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / 'props' / 'assets'
LOW_W, LOW_H, UPSCALE = 480, 270, 4

# ---------------------------------------------------------------- reset
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
depsgraph = bpy.context.evaluated_depsgraph_get


def new_coll(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or scene.collection).children.link(c)
    return c


props_coll = new_coll('Props')
# interaction states, switched by the scene's cabinet_open / shutters_closed checkboxes
cab_open = new_coll('Cabinet_Open', props_coll)
cab_closed = new_coll('Cabinet_Closed', props_coll)
sh_closed = new_coll('Shutters_Closed', props_coll)
sh_stowed = new_coll('Shutters_Stowed', props_coll)
room_coll = new_coll('Room')
light_coll = new_coll('Lights_Camera')


# ---------------------------------------------------------------- import
def import_asset(stem, coll):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ASSETS / f'{stem}.glb'), merge_vertices=True)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        coll.objects.link(o)
    root = [o for o in new if o.parent is None][0]
    root.name = stem
    return root, [o for o in new if o.type == 'MESH']


def world_bounds(meshes):
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def surface_height(lo, hi, accept):
    """Highest hit on the `accept` meshes under an XY footprint."""
    bpy.context.view_layer.update()
    dg = depsgraph()
    best = 0.0
    for fx in (0.15, 0.5, 0.85):
        for fy in (0.15, 0.5, 0.85):
            org = Vector((lo.x + (hi.x - lo.x) * fx, lo.y + (hi.y - lo.y) * fy, 10))
            hit, loc, _, _, obj, _ = scene.ray_cast(dg, org, Vector((0, 0, -1)))
            # step past anything that isn't the supporting surface
            while hit and obj not in accept:
                hit, loc, _, _, obj, _ = scene.ray_cast(dg, loc - Vector((0, 0, 1e-4)), Vector((0, 0, -1)))
            if hit:
                best = max(best, loc.z)
    return best


placed = {}


def place(stem, x, y_back=None, y=None, on_surface=None, rot_z=0.0, coll=props_coll):
    """x = centre x; y_back puts the prop's back face against y_back, else centre y."""
    root, meshes = import_asset(stem, coll)
    # GLBs were authored Z-up; undo the importer's Y-up -> Z-up conversion
    root.rotation_mode = 'XYZ'  # importer leaves nodes in quaternion mode
    root.rotation_euler = (math.radians(-90), 0, math.radians(rot_z))
    lo, hi = world_bounds(meshes)
    print('PLACED', stem, 'size', tuple(round(v, 2) for v in hi - lo))
    cx = (lo.x + hi.x) / 2
    root.location.x += x - cx
    if y_back is not None:
        root.location.y += y_back - hi.y
    elif y is not None:
        root.location.y += y - (lo.y + hi.y) / 2
    if on_surface:
        lo, hi = world_bounds(meshes)
        root.location.z += surface_height(lo, hi, set(placed[on_surface][1])) - lo.z
    placed[stem] = (root, meshes)
    return root, meshes


# ---------------------------------------------------------------- room
WALL_Y = 2.0


HALF_W = 5.2      # room spans x -HALF_W..HALF_W; wide enough for the stowed shutters
WIN_X = -1.5      # window / shutter centre


def box(name, loc, size, mat, coll=room_coll):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)
    return o


def base_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*rgb, 1)
    return m


plank_cols = [(0.30, 0.17, 0.09), (0.36, 0.21, 0.11), (0.27, 0.15, 0.08), (0.33, 0.19, 0.10)]
plank_mats = [base_mat(f'floor_plank_{i}', c) for i, c in enumerate(plank_cols)]
x = -HALF_W
i = 0
while x < HALF_W:
    box(f'floor_plank_{i:02d}', (x + 0.15, 0.5, -0.03), (0.29, 3.2, 0.06), plank_mats[(i * 7) % 4])
    x += 0.3
    i += 1
wall_mat = base_mat('plaster_wall', (0.62, 0.45, 0.27))
stone_mat = base_mat('stone_wall', (0.22, 0.24, 0.28))
beam_mat = base_mat('timber_beam', (0.22, 0.12, 0.06))
box('back_wall', (0, WALL_Y + 0.1, 1.6), (2 * HALF_W, 0.2, 3.2), wall_mat)
box('left_wall', (-HALF_W - 0.1, 0.5, 1.6), (0.2, 3.4, 3.2), stone_mat)
box('baseboard', (0, WALL_Y - 0.02, 0.08), (2 * HALF_W, 0.06, 0.16), beam_mat)
box('ceiling_beam', (0, WALL_Y - 0.12, 3.05), (2 * HALF_W, 0.25, 0.25), beam_mat)
# stone blocks on the left wall for texture
for row in range(8):
    for col in range(5):
        if (row + col) % 3 == 0:
            box(f'stone_{row}_{col}', (-HALF_W + 0.01, -0.8 + col * 0.65 + (row % 2) * 0.35, 0.2 + row * 0.38),
                (0.04, 0.6, 0.3), base_mat(f'stone_{row}_{col}', (0.30, 0.31, 0.35) if (row * col) % 2 else (0.17, 0.19, 0.23)))

# storm outside the window: glows around the closed shutters, fills the frame when stowed
storm_glow = base_mat('storm_window_emit', (0.3, 0.7, 1.0))
box('storm_window_emit', (WIN_X, WALL_Y - 0.004, 1.53), (3.2, 0.01, 1.12), storm_glow)
for name, loc, size in (('sill', (WIN_X, WALL_Y - 0.06, 0.94), (3.4, 0.12, 0.08)),
                        ('lintel', (WIN_X, WALL_Y - 0.03, 2.12), (3.4, 0.06, 0.08)),
                        ('jamb_l', (WIN_X - 1.66, WALL_Y - 0.03, 1.53), (0.08, 0.06, 1.2)),
                        ('jamb_r', (WIN_X + 1.66, WALL_Y - 0.03, 1.53), (0.08, 0.06, 1.2)),
                        ('mullion', (WIN_X, WALL_Y - 0.03, 1.53), (0.06, 0.04, 1.12)),
                        ('transom', (WIN_X, WALL_Y - 0.03, 1.53), (3.2, 0.04, 0.05))):
    box(f'window_{name}', loc, size, beam_mat, coll=sh_stowed)

# ---------------------------------------------------------------- props
BENCH_X = 2.75
place('05_storm_shutters_closed', WIN_X, y_back=WALL_Y, coll=sh_closed)
place('13_storm_shutters_stowed', WIN_X, y_back=WALL_Y, coll=sh_stowed)
place('06_sandbag_flood_barrier', WIN_X, y_back=WALL_Y - 0.05)
place('07_gravity_water_filter', -4.45, y_back=WALL_Y - 0.3)
place('09_supply_crates', -2.6, y=-0.55, rot_z=-8)
place('04_portable_power_station', 0.9, y=1.0, rot_z=12)
place('01_wooden_workbench', BENCH_X, y_back=WALL_Y - 0.05)
place('08_wall_weather_instruments', BENCH_X, y_back=WALL_Y)
# wall-mounted microfiche display, where the paper map used to hang (heights are in the model)
place('14_microfiche_reader', 0.78, y_back=WALL_Y)
place('12_supply_cabinet_open', 4.5, y_back=WALL_Y - 0.05, coll=cab_open)
place('03_supply_cabinet_closed', 4.5, y_back=WALL_Y - 0.05, coll=cab_closed)
# ham radio against the wall, right of the vice (not in front of it, or the vice hides its face)
# and under the left end of the weather-instrument board; its coax runs up beside the board
place('02_emergency_weather_radio', BENCH_X - 0.28, y_back=WALL_Y - 0.05, on_surface='01_wooden_workbench')
# the middle of the bench stays clear for the cutting mat (build_story.py), the crafting build grid:
# the lantern sits in the back-right corner and the flashlight rides on the power station
place('10_emergency_lantern', BENCH_X + 0.78, y=1.78, on_surface='01_wooden_workbench')
place('11_flashlight', 0.9, y=1.0, on_surface='04_portable_power_station', rot_z=12)

# ---------------------------------------------------------------- ceiling
# sloped board panels between rafters, rising toward the camera. The room camera looks 8 degrees
# down, so a ceiling only shows its underside if it climbs faster than that toward the front.
CEIL_SLOPE = math.radians(16)
CEIL_BACK_Z = 3.2                  # where the panels meet the top of the back wall
CEIL_FRONT_Y = -1.1                # front of the room (the floor's front edge)


def ceiling_z(y):
    return CEIL_BACK_Z + (WALL_Y - y) * math.tan(CEIL_SLOPE)


PENDANT_X = BENCH_X - 0.35         # left of the bench centre, clear of the crafting camera's swing
RAFTER_STEP = 0.9
ceil_len = (WALL_Y - CEIL_FRONT_Y) / math.cos(CEIL_SLOPE)
ceil_mid_y = (WALL_Y + CEIL_FRONT_Y) / 2
panel_mats = [base_mat('ceiling_board_a', (0.34, 0.21, 0.11)), base_mat('ceiling_board_b', (0.29, 0.17, 0.09))]
rafter_xs = [PENDANT_X + k * RAFTER_STEP for k in range(-9, 4) if -HALF_W < PENDANT_X + k * RAFTER_STEP < HALF_W]
edges = [-HALF_W] + rafter_xs + [HALF_W]
for i, (x0, x1) in enumerate(zip(edges, edges[1:])):
    o = box(f'ceiling_panel_{i:02d}', ((x0 + x1) / 2, ceil_mid_y, ceiling_z(ceil_mid_y) + 0.02),
            (x1 - x0 + 0.02, ceil_len, 0.04), panel_mats[i % 2])
    o.rotation_euler.x = -CEIL_SLOPE
for i, x in enumerate(rafter_xs):
    o = box(f'ceiling_rafter_{i:02d}', (x, ceil_mid_y, ceiling_z(ceil_mid_y) - 0.07),
            (0.10, ceil_len, 0.14), beam_mat)
    o.rotation_euler.x = -CEIL_SLOPE

# pendant lamp over the workbench, hung on a cord from the rafter above it
lamp_mat = base_mat('lamp_shade', (0.20, 0.24, 0.22))
LAMP_Y, LAMP_Z = 0.75, 2.55
bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.28, radius2=0.06, depth=0.22, location=(PENDANT_X, LAMP_Y, LAMP_Z))
shade = bpy.context.object; shade.name = 'pendant_shade'; shade.data.materials.append(lamp_mat)
bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.08, location=(PENDANT_X, LAMP_Y, LAMP_Z - 0.11))
bulb = bpy.context.object; bulb.name = 'pendant_bulb_emit'
cord_top = ceiling_z(LAMP_Y) - 0.13       # the rafter's underside
cord_len = cord_top - (LAMP_Z + 0.11)
bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.008, depth=cord_len, location=(PENDANT_X, LAMP_Y, LAMP_Z + 0.11 + cord_len / 2))
cord = bpy.context.object; cord.name = 'pendant_cord'; cord.data.materials.append(beam_mat)
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.05, depth=0.03, location=(PENDANT_X, LAMP_Y, cord_top - 0.015))
canopy = bpy.context.object; canopy.name = 'pendant_ceiling_cup'; canopy.data.materials.append(lamp_mat)
for o in (shade, bulb, cord, canopy):
    for c in o.users_collection:
        c.objects.unlink(o)
    room_coll.objects.link(o)

# ---------------------------------------------------------------- toon materials
OUTLINE = bpy.data.materials.new('toon_outline')
OUTLINE.use_nodes = True
nt = OUTLINE.node_tree
nt.nodes.clear()
em = nt.nodes.new('ShaderNodeEmission'); em.inputs['Color'].default_value = (0.018, 0.010, 0.012, 1)
out = nt.nodes.new('ShaderNodeOutputMaterial')
nt.links.new(em.outputs[0], out.inputs['Surface'])
OUTLINE.use_backface_culling = True

EMISSIVE = {'storm_window': ((0.25, 0.68, 1.0), 2.5), 'flame': ((1.0, 0.55, 0.15), 12), 'pendant_bulb': ((1.0, 0.75, 0.4), 15),
            'lcd': ((0.35, 0.95, 0.75), 3), 'display': ((0.35, 0.95, 0.75), 3),
            'lens': ((1.0, 0.92, 0.7), 4), 'screen': ((0.35, 0.95, 0.75), 3)}


BAND = 0.16  # brightness step in perceptual space; bigger = fewer, chunkier bands


def toonify(mat, base):
    """Diffuse -> Shader to RGB -> perceptual posterize -> emission."""
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    out = N('ShaderNodeOutputMaterial'); out.location = (900, 0)
    key = next((k for k in EMISSIVE if k in mat.name.lower()), None)
    if key:
        col, strength = EMISSIVE[key]
        e = N('ShaderNodeEmission'); e.inputs['Color'].default_value = (*col, 1); e.inputs['Strength'].default_value = strength
        nt.links.new(e.outputs[0], out.inputs['Surface'])
        return
    d = N('ShaderNodeBsdfDiffuse'); d.location = (-600, 0)
    d.inputs['Color'].default_value = base
    s2r = N('ShaderNodeShaderToRGB'); s2r.location = (-400, 0)
    nt.links.new(d.outputs[0], s2r.inputs[0])

    def math_node(op, a, b, loc):
        m = N('ShaderNodeMath'); m.operation = op; m.location = loc
        for sock, v in ((m.inputs[0], a), (m.inputs[1], b)):
            if isinstance(v, float):
                sock.default_value = v
            else:
                nt.links.new(v, sock)
        return m.outputs[0]

    # band the brightness only, keep the light's hue: out = lit * band(L) / L
    lum = N('ShaderNodeRGBToBW'); lum.location = (-200, -200)
    nt.links.new(s2r.outputs['Color'], lum.inputs[0])
    L = math_node('MAXIMUM', lum.outputs[0], 1e-4, (0, -200))
    p = math_node('POWER', L, 0.45, (150, -200))
    q = math_node('SNAP', p, BAND, (300, -200))
    q = math_node('MAXIMUM', q, BAND * 0.5, (450, -200))
    q = math_node('POWER', q, 1 / 0.45, (600, -200))
    ratio = math_node('DIVIDE', q, L, (750, -200))
    mix = N('ShaderNodeVectorMath'); mix.operation = 'SCALE'; mix.location = (750, 0)
    nt.links.new(s2r.outputs['Color'], mix.inputs[0])
    nt.links.new(ratio, mix.inputs['Scale'])
    e = N('ShaderNodeEmission'); e.location = (900, 0)
    nt.links.new(mix.outputs[0], e.inputs['Color'])
    out.location = (1100, 0)
    nt.links.new(e.outputs[0], out.inputs['Surface'])

for mat in list(bpy.data.materials):
    if mat is OUTLINE:
        continue
    base = (0.8, 0.8, 0.8, 1)
    if mat.use_nodes and mat.node_tree.nodes.get('Principled BSDF'):
        base = tuple(mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value)
    toonify(mat, base)
bulb_mat = bpy.data.materials.new('pendant_bulb_emit'); toonify(bulb_mat, (1, 1, 1, 1)); bulb.data.materials.append(bulb_mat)

# swirling storm clouds for the window instead of a flat glow
nt = storm_glow.node_tree
nt.nodes.clear()
N = nt.nodes.new
tc = N('ShaderNodeTexCoord')
noise = N('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 3.5
noise.inputs['Detail'].default_value = 6; noise.inputs['Distortion'].default_value = 2.5
ramp = N('ShaderNodeValToRGB')
els = ramp.color_ramp.elements
els[0].position, els[0].color = 0.35, (0.01, 0.05, 0.12, 1)
els[1].position, els[1].color = 0.75, (0.55, 0.95, 1.0, 1)
mid = els.new(0.55); mid.color = (0.05, 0.30, 0.55, 1)
e = N('ShaderNodeEmission'); e.inputs['Strength'].default_value = 2.5
out = N('ShaderNodeOutputMaterial')
nt.links.new(tc.outputs['Object'], noise.inputs['Vector'])
nt.links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
nt.links.new(ramp.outputs['Color'], e.inputs['Color'])
nt.links.new(e.outputs[0], out.inputs['Surface'])

# inverted-hull outlines on props + lamp (room boxes stay clean)
outlined = [o for o in props_coll.all_objects if o.type == 'MESH'] + [shade, cord]
for o in outlined:
    if not o.data.materials:
        o.data.materials.append(bpy.data.materials.new(o.name + '_mat'))
    o.data.materials.append(OUTLINE)
    m = o.modifiers.new('ToonOutline', 'SOLIDIFY')
    m.thickness = 0.016
    m.offset = 1.0
    m.use_flip_normals = True
    m.use_even_offset = True
    m.use_rim = False
    m.material_offset = len(o.data.materials) - 1
    o.visible_shadow = True

# ---------------------------------------------------------------- lights
def light(name, kind, loc, energy, color, target=None, **kw):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    for k, v in kw.items():
        setattr(ld, k, v)
    o = bpy.data.objects.new(name, ld)
    o.location = loc
    light_coll.objects.link(o)
    if target is not None:
        o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o


lantern_root, lantern_meshes = placed['10_emergency_lantern']
llo, lhi = world_bounds(lantern_meshes)
light('lantern_glow', 'POINT', ((llo.x + lhi.x) / 2, (llo.y + lhi.y) / 2, llo.z + (lhi.z - llo.z) * 0.45),
      90, (1.0, 0.55, 0.22), shadow_soft_size=0.05)
light('pendant_key', 'POINT', (PENDANT_X, 0.75, 2.3), 400, (1.0, 0.70, 0.38), shadow_soft_size=0.1)
light('cabinet_fill', 'POINT', (4.25, 0.1, 1.5), 110, (1.0, 0.62, 0.32), shadow_soft_size=0.3)
light('cool_front_fill', 'AREA', (-1.0, -3.0, 2.2), 160, (0.30, 0.55, 0.90), target=(0.0, 1.2, 0.8), size=5)
storm_light = light('storm_window', 'AREA', (WIN_X, WALL_Y - 0.4, 1.55), 420, (0.22, 0.60, 1.0),
                    target=(WIN_X - 0.4, -1.0, 0.0), size=2.8)
light('storm_moon_rim', 'SUN', (0, 0, 5), 1.6, (0.35, 0.65, 1.0), target=None, angle=math.radians(3))
bpy.data.objects['storm_moon_rim'].rotation_euler = (math.radians(55), 0, math.radians(-140))

world = bpy.data.worlds.new('storm_night')
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (0.012, 0.035, 0.06, 1)
bg.inputs['Strength'].default_value = 1.0

# ---------------------------------------------------------------- state toggles
# Scene Properties > Custom Properties: tick/untick to swap prop states live.
# Simple driver expressions, so they run without enabling Python auto-exec.
scene['cabinet_open'] = True
scene['shutters_closed'] = True


def drive(id_block, path, prop, expr):
    fc = id_block.driver_add(path)
    drv = fc.driver
    drv.type = 'SCRIPTED'
    var = drv.variables.new()
    var.name = 'v'
    var.targets[0].id_type = 'SCENE'
    var.targets[0].id = scene
    var.targets[0].data_path = f'["{prop}"]'
    drv.expression = expr


for coll, prop, expr in ((cab_open, 'cabinet_open', '1 - v'), (cab_closed, 'cabinet_open', 'v'),
                         (sh_closed, 'shutters_closed', '1 - v'), (sh_stowed, 'shutters_closed', 'v')):
    for o in coll.objects:
        drive(o, 'hide_viewport', prop, expr)
        drive(o, 'hide_render', prop, expr)
# open window floods the room with more storm light
drive(storm_light.data, 'energy', 'shutters_closed', '420 + 500 * (1 - v)')

# ---------------------------------------------------------------- camera
cam_data = bpy.data.cameras.new('pixel_cam')
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 10.6
cam = bpy.data.objects.new('pixel_cam', cam_data)
light_coll.objects.link(cam)
target = Vector((0.0, 0.8, 1.25))
az, el, dist = math.radians(14), math.radians(20), 20
cam.location = target + Vector((math.sin(az) * dist * math.cos(el), -math.cos(az) * dist * math.cos(el), math.sin(el) * dist))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = cam

# ---------------------------------------------------------------- render settings
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.eevee.taa_render_samples = 32
scene.eevee.use_shadows = True
scene.render.filter_size = 0.5          # minimal AA so pixels stay hard-edged
scene.render.resolution_x = LOW_W
scene.render.resolution_y = LOW_H
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGB'
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0.0
scene.render.filepath = str(HERE / 'render_lowres.png')

# keep the post-process script inside the .blend for re-rendering from the GUI
txt = bpy.data.texts.new('pixelize.py')
txt.from_string((HERE / 'pixelize.py').read_text())

bpy.ops.wm.save_as_mainfile(filepath=str(HERE / 'climate_shelter_pixel.blend'))

if '--no-render' not in sys.argv:
    sys.path.insert(0, str(HERE))
    import pixelize
    pixelize.render_all_states()
