"""Write scenes/main.tscn from assets/scene_meta.json (lights + camera from the Blender scene).

WorldVP and MaskVP don't set a world_3d of their own: both render the scene's own World3D (so they
share it, and the editor's 3D view shows the room). Their cameras register with their SubViewport,
so the root viewport draws no 3D itself.

python3 pipeline/godot/make_main_scene.py

Run once after an export to seed the scene; after that main.tscn is the source of
truth and can be tweaked in the editor (re-running overwrites it).
"""
import json, math
from pathlib import Path

GODOT = Path(__file__).resolve().parents[2]   # repo root = the Godot project
meta = json.loads((GODOT / 'assets' / 'scene_meta.json').read_text())
PI2 = math.pi ** 2


def srgb(c):
    """Blender light colours are linear; Godot's Color properties are sRGB."""
    return [12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055 for v in c[:3]]


def col(c):
    return 'Color(%.4f, %.4f, %.4f, 1)' % tuple(srgb(c))


def norm(v):
    n = math.sqrt(sum(a * a for a in v)) or 1
    return [a / n for a in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def xform(pos, fwd=None, tilt_deg=None):
    """Transform3D text. Lights shine down -Z, so Z = -fwd."""
    if tilt_deg is not None:
        t = math.radians(-tilt_deg)
        X, Y, Z = [1, 0, 0], [0, math.cos(t), math.sin(t)], [0, -math.sin(t), math.cos(t)]
    elif fwd is None:
        X, Y, Z = [1, 0, 0], [0, 1, 0], [0, 0, 1]
    else:
        Z = norm([-a for a in fwd])
        up = [0, 1, 0] if abs(Z[1]) < 0.99 else [1, 0, 0]
        X = norm(cross(up, Z))
        Y = cross(Z, X)
    rows = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2], *pos]
    return 'Transform3D(' + ', '.join('%.5f' % v for v in rows) + ')'


cam = meta['camera']
cam_pos = [cam['x_right'], cam['pos_y'], cam['pos_z']]
cam_common = (f'transform = {xform(cam_pos, tilt_deg=cam["tilt_deg"])}\nprojection = 1\nkeep_aspect = 0\n'
              f'size = {cam["ortho_width"]}\nnear = 0.1\nfar = 40.0\n')

lights = []
for L in meta['lights']:
    name, kind, e = L['name'], L['type'], L['energy']
    # only the key light casts shadows: Godot's Compatibility renderer (the web build) adds each
    # shadowed light in sRGB space in its own pass, which over-brightens when several stack up
    shadow = name == 'pendant_key'
    if kind == 'POINT':
        body = (f'[node name="{name}" type="OmniLight3D" parent="WorldVP/Lights"]\n'
                f'transform = {xform(L["pos"])}\nlight_color = {col(L["color"])}\n'
                f'light_energy = {abs(e) / (4 * PI2):.4f}\nlight_size = {L["radius"]:.3f}\n'
                f'omni_range = {16.0 if shadow else 9.0}\nomni_attenuation = 2.0\n')
    elif kind == 'AREA':
        body = (f'[node name="{name}" type="SpotLight3D" parent="WorldVP/Lights"]\n'
                f'transform = {xform(L["pos"], L["dir"])}\nlight_color = {col(L["color"])}\n'
                f'light_energy = {e / PI2:.4f}\nlight_size = {min(L["size"], 1.0):.3f}\n'
                f'spot_range = 14.0\nspot_attenuation = 2.0\nspot_angle = 80.0\nspot_angle_attenuation = 1.0\n')
    else:
        body = (f'[node name="{name}" type="DirectionalLight3D" parent="WorldVP/Lights"]\n'
                f'transform = {xform(L["pos"], L["dir"])}\nlight_color = {col(L["color"])}\n'
                f'light_energy = {e / math.pi:.4f}\n')
    if shadow:
        body += 'shadow_enabled = true\n'
    lights.append(body)

wc = meta['world_color']
tscn = f'''[gd_scene load_steps=9 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]
[ext_resource type="PackedScene" path="res://assets/shelter.glb" id="2_room"]
[ext_resource type="Shader" path="res://shaders/post.gdshader" id="3_post"]
[ext_resource type="Script" path="res://scripts/ui/overlay.gd" id="4_ui"]
[ext_resource type="Script" path="res://scripts/ui/pause_menu.gd" id="5_pause"]
[ext_resource type="Script" path="res://scripts/ui/start_menu.gd" id="6_start"]

[sub_resource type="Environment" id="Environment_world"]
background_mode = 1
background_color = {col(wc)}
ambient_light_source = 2
ambient_light_color = {col(wc)}
ambient_light_energy = 1.0
reflected_light_source = 1
tonemap_mode = 0

[sub_resource type="Environment" id="Environment_mask"]
background_mode = 1
background_color = Color(0, 0, 0, 1)
ambient_light_source = 1
reflected_light_source = 1
tonemap_mode = 0

[sub_resource type="ShaderMaterial" id="ShaderMaterial_post"]
shader = ExtResource("3_post")

[node name="Main" type="Node"]
script = ExtResource("1_main")

[node name="WorldVP" type="SubViewport" parent="."]
size = Vector2i(480, 270)
render_target_update_mode = 4

[node name="Room" parent="WorldVP" instance=ExtResource("2_room")]

[node name="Camera" type="Camera3D" parent="WorldVP"]
{cam_common}cull_mask = 524287
current = true

[node name="WorldEnvironment" type="WorldEnvironment" parent="WorldVP"]
environment = SubResource("Environment_world")

[node name="Lights" type="Node3D" parent="WorldVP"]

''' + '\n'.join(lights) + f'''
[node name="MaskVP" type="SubViewport" parent="."]
size = Vector2i(480, 270)
render_target_update_mode = 4

[node name="MaskCam" type="Camera3D" parent="MaskVP"]
{cam_common}cull_mask = 1048575
environment = SubResource("Environment_mask")
current = true

[node name="Screen" type="TextureRect" parent="."]
material = SubResource("ShaderMaterial_post")
offset_right = 480.0
offset_bottom = 270.0
mouse_filter = 2

[node name="UI" type="CanvasLayer" parent="."]

[node name="Overlay" type="Control" parent="UI"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("4_ui")

[node name="PauseMenu" type="Control" parent="UI"]
process_mode = 3
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("5_pause")

[node name="StartMenu" type="Control" parent="UI"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("6_start")
'''
(GODOT / 'scenes' / 'main.tscn').write_text(tscn)
print('wrote scenes/main.tscn with', len(lights), 'lights')
