"""Export the story room to Godot.

blender -b --factory-startup pipeline/scene/climate_shelter_story.blend --python pipeline/godot/export_glb.py

Takes the story scene at frame 1 (shutters shut, cabinet closed, speaker on the
wall, radio broken), drops the baked animation, regroups every interactable
under a `grp_<name>` node, flattens the toon node trees into plain glTF
materials (Godot swaps in its own toon shader by material name/colour), bakes
the inverted-hull outlines into the meshes, and writes:

  assets/shelter.glb       the room
  assets/scene_meta.json   lights, camera rig, start-hidden nodes, group list
"""
import bpy, json, math
from pathlib import Path
from mathutils import Vector

GODOT = Path(__file__).resolve().parents[2]   # repo root = the Godot project
OUT = GODOT / 'assets'
scene = bpy.context.scene
scene.frame_set(1)
objs = bpy.data.objects
WALL_Y, WIN_X, HALF_W = 2.0, -1.5, 5.2


def to_godot(v):
    """Blender Z-up -> Godot Y-up (what the glTF exporter does)."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


# ---------------------------------------------------------------- freeze frame 1
for o in objs:
    o.animation_data_clear()
    if o.type == 'LIGHT':
        o.data.animation_data_clear()
for m in bpy.data.materials:
    m.animation_data_clear()
    if m.node_tree:
        m.node_tree.animation_data_clear()

# nodes the game switches on later stay in the file, hidden at start
LATER = [o for o in objs if o.type == 'MESH' and ('speaker_grill_bar' in o.name or 'speaker_panel' in o.name)
         and o.parent and o.parent.name.startswith('02_emergency_weather_radio')]
later_names = {o.name for o in LATER}
for o in list(objs):
    if o.type in ('CAMERA',):
        objs.remove(o)
    elif o.hide_render and o.name not in later_names:
        objs.remove(o)
for o in LATER:
    o.hide_render = o.hide_viewport = False
for c in bpy.data.collections:
    c.hide_render = c.hide_viewport = False

# ---------------------------------------------------------------- groups (mirrors build_story.GROUPS)
def kids(root):
    return [o for o in objs[root].children_recursive if o.type == 'MESH'] if root in objs else []


def named(*prefixes):
    return [o for o in objs if o.type == 'MESH' and o.name.startswith(prefixes)]


story = bpy.data.collections['Story']
radio = kids('02_emergency_weather_radio') + named('radio_speaker_hole', 'radio_wire_')
GROUPS = {
    'shutters': [o for o in bpy.data.collections['Shutters_Closed'].all_objects if o.type == 'MESH'],
    'cabinet': [o for o in bpy.data.collections['Cabinet_Closed'].all_objects if o.type == 'MESH'],
    'map': named('pnw_map', 'map_pin_'),
    'speaker': [o for o in objs['speaker_rig'].children_recursive if o.type == 'MESH'],
    'radio': radio,
    'jar': named('jar_'),
    'papers': named('papers_'),
    'bench': kids('01_wooden_workbench'),
    'sky': named('storm_window_emit'),
    'lantern': kids('10_emergency_lantern'),
    'instruments': kids('08_wall_weather_instruments'),
    'power': kids('04_portable_power_station'),
    'filter': kids('07_gravity_water_filter'),
    'crates': kids('09_supply_crates'),
    'sandbags': kids('06_sandbag_flood_barrier'),
    'flashlight': kids('11_flashlight'),
}
taken = set()
for name in GROUPS:                                  # an object belongs to the first group that lists it
    GROUPS[name] = [o for o in GROUPS[name] if o.name not in taken]
    taken |= {o.name for o in GROUPS[name]}

bpy.context.view_layer.update()
group_roots = {}
for name, members in GROUPS.items():
    mset = set(members)
    g = objs.new(f'grp_{name}', None)
    scene.collection.objects.link(g)
    roots = set()
    for m in members:
        a = m
        while a.parent and a.parent.type in ('EMPTY', 'MESH') and \
                all(d in mset for d in a.parent.children_recursive if d.type == 'MESH') and \
                (a.parent.type != 'MESH' or a.parent in mset):
            a = a.parent
        roots.add(a)
    for r in roots:
        mw = r.matrix_world.copy()
        r.parent = g
        r.matrix_parent_inverse.identity()
        r.matrix_world = mw
    group_roots[name] = sorted(r.name for r in roots)

# ---------------------------------------------------------------- flatten materials for glTF
def find(nt, idname):
    return next((n for n in nt.nodes if n.bl_idname == idname), None)


mat_info = {}
for m in bpy.data.materials:
    if not m.node_tree:
        continue
    nt = m.node_tree
    diff = find(nt, 'ShaderNodeBsdfDiffuse')
    emit = find(nt, 'ShaderNodeEmission')
    img = find(nt, 'ShaderNodeTexImage')
    info = {'kind': 'toon', 'color': [1, 1, 1], 'strength': 0.0}
    if m.name == 'toon_outline':
        info = {'kind': 'outline', 'color': list(emit.inputs['Color'].default_value)[:3], 'strength': 1.0}
    elif m.name == 'storm_window_emit':
        info = {'kind': 'sky', 'color': [0.1, 0.42, 0.95], 'strength': 2.5}
    elif diff:
        info['color'] = list(diff.inputs['Color'].default_value)[:3]
    elif emit:
        info = {'kind': 'emit', 'color': list(emit.inputs['Color'].default_value)[:3],
                'strength': emit.inputs['Strength'].default_value}
    mat_info[m.name] = info
    image = img.image if img else None
    nt.nodes.clear()
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(bsdf.outputs[0], out.inputs['Surface'])
    bsdf.inputs['Base Color'].default_value = (*info['color'], 1)
    bsdf.inputs['Roughness'].default_value = 1.0
    if info['kind'] in ('emit', 'outline', 'sky'):
        bsdf.inputs['Emission Color'].default_value = (*info['color'], 1)
        bsdf.inputs['Emission Strength'].default_value = info['strength']
    if image:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = image
        nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
        info['texture'] = True

# ---------------------------------------------------------------- lights + camera rig -> json
lights = []
for o in [o for o in objs if o.type == 'LIGHT']:
    d = o.data
    fwd = o.matrix_world.to_3x3() @ Vector((0, 0, -1))
    lights.append({'name': o.name, 'type': d.type, 'pos': to_godot(o.matrix_world.translation),
                   'dir': to_godot(fwd.normalized()), 'color': list(d.color), 'energy': d.energy,
                   'size': getattr(d, 'size', 0.0), 'radius': getattr(d, 'shadow_soft_size', 0.0)})
    objs.remove(o)

world = scene.world.node_tree.nodes.get('Background') if scene.world and scene.world.use_nodes else None
TILT, DIST, LOOK_Z = 8.0, 12.0, 1.55
meta = {
    'groups': list(GROUPS),
    'group_roots': group_roots,
    'start_hidden': sorted(later_names),
    'materials': mat_info,
    'lights': lights,
    'world_color': list(world.inputs['Color'].default_value)[:3] if world else [0, 0, 0],
    'camera': {'ortho_width': 6.6, 'tilt_deg': TILT, 'x_left': WIN_X, 'x_right': 2.6,
               'pos_y': LOOK_Z + DIST * math.sin(math.radians(TILT)),
               'pos_z': -(WALL_Y - DIST * math.cos(math.radians(TILT)))},
    'points': {'window': to_godot((WIN_X, WALL_Y, 1.53)),
               'speaker_mount': to_godot(objs['speaker_rig'].matrix_world.translation)},
}

OUT.mkdir(exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(OUT / 'shelter.glb'), export_format='GLB', export_apply=True,
                          export_lights=False, export_cameras=False, export_animations=False,
                          export_extras=True, export_yup=True, use_visible=False)
(OUT / 'scene_meta.json').write_text(json.dumps(meta, indent=1))
print('EXPORTED', {k: len(v) for k, v in GROUPS.items()})
