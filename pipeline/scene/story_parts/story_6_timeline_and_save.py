# Part of pipeline/scene/build_story.py, which runs the parts in order in one shared
# namespace: names defined in earlier parts are used here as-is. Run build_story.py, not this.
#
# Saves climate_shelter_story.blend (what pipeline/godot/export_glb.py reads), plus the video-only
# cursor path, UI layout and timeline.json; with -- --render / --stills, renders the video frames.

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
