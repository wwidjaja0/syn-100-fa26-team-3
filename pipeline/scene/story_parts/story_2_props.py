# Part of pipeline/scene/build_story.py, which runs the parts in order in one shared
# namespace: names defined in earlier parts are used here as-is. Run build_story.py, not this.
#
# The story props, built from Blender primitives: the PA speaker on its bracket, the paper wall
# map (video only; export_glb.py leaves it out of the game), the jar of dried mushrooms, the
# rolling papers, the cutting mat, and the broken radio (speaker pulled out, wires hanging).
# The game needs this part. Uses from part 1: scene, M, colls, HERE, WALL_Y, HALF_W, show().

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
    # thin parts get a thinner shell (see build_pixel_scene.py's outlines)
    md.thickness, md.offset = min(thickness, max(0.25 * min(o.dimensions), 0.003)), 1.0
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

# --- cutting mat on the bench: the crafting view's build grid (pixel art + sizes from make_mat.py)
MAT_META = json.loads((HERE / 'mat_meta.json').read_text())
MAT_W, MAT_D = MAT_META['size_m']
MAT_T = 0.004
MAT_C = Vector((3.08, 1.35, BENCH_TOP + MAT_T / 2))   # between the radio and the papers, clear of the lantern
mat_mat = toon('cutting_mat', (1, 1, 1))
tex = mat_mat.node_tree.nodes.new('ShaderNodeTexImage')
tex.image = bpy.data.images.load(str(HERE / 'mat_texture.png'))
tex.image.pack()
tex.interpolation = 'Closest'
mat_mat.node_tree.links.new(tex.outputs['Color'], mat_mat.node_tree.nodes['Diffuse BSDF'].inputs['Color'])
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1)
bmesh.ops.scale(bm, vec=(MAT_W, MAT_D, MAT_T), verts=bm.verts)
uv = bm.loops.layers.uv.new()
for face in bm.faces:
    for loop in face.loops:
        if face.normal.z > 0.5:          # the printed top: u left->right, v front->back (image top = wall side)
            loop[uv].uv = (loop.vert.co.x / MAT_W + 0.5, loop.vert.co.y / MAT_D + 0.5)
        else:                            # edges take the rim colour
            loop[uv].uv = (0.5 / MAT_META['px'][0], 0.5 / MAT_META['px'][1])
# no outline hull: outlined props are dimmed in Godot (PROP_DIRECT_LIGHT), and the texture has its own rim
mat_obj = mesh_obj('cutting_mat', bm, mat_mat, MAT_C, outline=False)

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
