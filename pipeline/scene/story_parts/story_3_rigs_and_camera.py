# Part of pipeline/scene/build_story.py, which runs the parts in order in one shared
# namespace: names defined in earlier parts are used here as-is. Run build_story.py, not this.
#
# Hinge rigs for the shutters and the cabinet doors (the empties the game rotates:
# shutter_hinge_L/R, cabinet_hinge_L/R) and the locked orthographic camera.
# The game needs the rigs; the camera is the video's (the game reads its numbers from
# scene_meta.json). Uses parts 1-2.

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
