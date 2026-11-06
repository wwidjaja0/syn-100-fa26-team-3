# Part of pipeline/scene/build_story.py, which runs the parts in order in one shared
# namespace: names defined in earlier parts are used here as-is. Run build_story.py, not this.
#
# Video only: easing curves and the per-frame state of everything that moves in the story video
# (shutters, heat, doors, camera pans, lightning, the speaker being torn down, the radio coming
# alive), keyed frame by frame, plus visibility switches (items picked up, the radio repaired).
# export_glb.py drops the animation and keeps frame 1, so this part also fixes the game's
# starting state (e.g. the radio grill hidden until it is repaired). Uses parts 1-3.

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
