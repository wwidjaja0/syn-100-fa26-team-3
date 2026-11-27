extends Node
## Replaces every material in the imported room (assets/shelter.glb) with the toon shader
## (shaders/toon.gdshader).
##
## The room comes from Blender with plain glTF materials. assets/scene_meta.json says what each
## material really is, by its Blender name:
##   "toon"    lit, flat colour (optionally a texture: the cutting mat)
##   "emit"    glows (lamp bulb, lantern flame, PA status light, readouts)
##   "outline" the black inverted-hull shell around a prop
##   "sky"     the window: the view from the summit (ui/window_view*.png) under the weather (weather.gd)
## The microfiche display's screen ("mat_fiche_screen_*") is special-cased to a turning globe.
##
## One ShaderMaterial is made per (Blender material, object group, outlined?) combination, so the
## mask's group id and the prop dimming are plain uniforms. (Per-instance uniforms would be simpler,
## but they don't work on every renderer.) Scripts change a material later with set_param().

const TOON := preload("res://shaders/toon.gdshader")
const GLOBE := preload("res://ui/globe_equirect.png")
## the view out of the window: pipeline/scene/make_window_view.py's panorama, its depth and its numbers
const WINDOW_VIEW := preload("res://ui/window_view.png")
const WINDOW_DEPTH := preload("res://ui/window_view_depth.png")
const WINDOW_VIEW_META := "res://ui/window_view_meta.json"
## how much wider the view swings than a real window would (the camera is far back and orthographic,
## so true angles through the window would be a narrow telephoto slice)
const VIEW_ZOOM := 3.5
const VIEW_PITCH := -6.0                # degrees: where the window's centre looks (the horizon sits high)
## the camera x at which the window looks along the panorama's heading. The camera's range is
## mostly right of the window, so this sits left: panning right turns the view inland (east), and
## from the left end of the room it looks out over the sea.
const VIEW_AHEAD_X := -1.0
const VIEW_HAZE_M := 30000.0            # make_window_view.py's HAZE_M: what the panorama's alpha means
## the hole in the wall under the window is small: it sees a wider, lower slice of the same view, so
## the coast and the land still show through it
const HOLE_VIEW_ZOOM := 1.4
const HOLE_VIEW_PITCH := -11.0          # degrees
## In Blender the outline shells also shadowed the props inside them, which gave the video its dark,
## moody props; in Godot outlined props get only this share of direct light to match.
const PROP_DIRECT_LIGHT := 0.12
const GLOBE_GLOW := 1.4

## LEDs, by material name prefix: they glow in exactly the palette's LED green and red (the last two
## entries of assets/palette.json), and only they may be snapped to those (post.gdshader)
const STATUS_LIGHTS := {"mat_charge_led_": Color8(64, 224, 84), "mat_radio_led_": Color8(236, 40, 44)}
const OUTLINE_MAT := "toon_outline"   # the shells' Blender material (scene_meta.json kind "outline")

var _meta: Dictionary
var _outline_scale := 1.0
var _outline_px_m := 0.0
var _by_name := {}                      # Blender material name -> [every ShaderMaterial variant of it]


## build and assign the materials. group_of(mesh) gives a mesh's object group id (0 = none).
## compat: the Compatibility renderer wants colours sRGB-encoded (see toon.gdshader's srgb_io).
func setup(room: Node3D, meta: Dictionary, group_of: Callable, compat: bool) -> void:
	_meta = meta
	var variants := {}
	var hulls := {}                     # imported mesh -> its rebuilt copy (meshes can be shared)
	for mi: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
		var oi := _outline_surface(mi.mesh)
		if oi >= 0:
			if not hulls.has(mi.mesh):
				hulls[mi.mesh] = _scalable_hull(mi.mesh, oi)
			mi.mesh = hulls[mi.mesh]
		var gid: int = group_of.call(mi)
		var keys: Array[String] = []
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			keys.append(src.resource_name if src else "")
		var outlined := keys.any(func(k): return meta.materials.get(k, {}).get("kind") == "outline")
		for i in keys.size():
			var key := keys[i]
			var vkey := "%s|%d|%s" % [key, gid, outlined]
			if not variants.has(vkey):
				var m := _make(key, mi.get_active_material(i), compat)
				m.set_shader_parameter("group_id", gid)
				m.set_shader_parameter("direct_light", PROP_DIRECT_LIGHT if outlined else 1.0)
				variants[vkey] = m
				if not _by_name.has(key):
					_by_name[key] = []
				_by_name[key].append(m)
			mi.set_surface_override_material(i, variants[vkey])


## the outline shells' push for a camera: scale 1 in the room view, smaller as a close-up zooms in
## (room_camera.gd, every frame). px_m is the size of one screen pixel in metres.
func set_outline_zoom(scale: float, px_m: float) -> void:
	if scale == _outline_scale and px_m == _outline_px_m:
		return
	_outline_scale = scale
	_outline_px_m = px_m
	set_param(OUTLINE_MAT, "outline_scale", scale)
	set_param(OUTLINE_MAT, "outline_px_m", px_m)


## the index of a mesh's outline shell surface (scene_meta.json kind "outline"), or -1
func _outline_surface(mesh: Mesh) -> int:
	if mesh == null:
		return -1
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and _meta.materials.get(m.resource_name, {}).get("kind") == "outline":
			return i
	return -1


## The outline shells come from Blender as fixed geometry: the part grown by a few millimetres to
## 1.6 cm (pipeline/scene/build_pixel_scene.py). That suits the room view, but a close-up magnifies
## it into black slabs. This copy of the mesh puts every shell vertex back on the part and stores
## its push (direction in NORMAL, length in UV2.x) for toon.gdshader to redo at the camera's zoom.
##
## The push is found per corner: the shell's split vertices at one spot carry the normals of the
## faces meeting there, and the push is the offset that moves each of those faces out by the shell's
## thickness (one face: along its normal; an edge or a box corner: diagonally, as Blender's even
## thickness does). The thickness is how far the shell's bounds stick out past the part's.
static func _scalable_hull(mesh: Mesh, oi: int) -> ArrayMesh:
	var part := AABB()
	var first := true
	for i in mesh.get_surface_count():
		if i == oi:
			continue
		var b := _bounds(mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX])
		part = b if first else part.merge(b)
		first = false
	var arrays := mesh.surface_get_arrays(oi)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if first or normals.size() != verts.size():
		return mesh
	var shell := _bounds(verts)
	var grow := (shell.size - part.size) / 2.0
	var t := minf(grow.x, minf(grow.y, grow.z))
	if t <= 1e-5:
		t = maxf(grow.x, maxf(grow.y, grow.z))
	if t <= 1e-5:
		return mesh
	# the shell's faces are turned inside out; which way its normals point decides the outward sign
	var c := shell.get_center()
	var facing := 0.0
	for i in verts.size():
		facing += normals[i].dot(verts[i] - c)
	var out_sign := -1.0 if facing < 0.0 else 1.0
	# sum n n^T and n over the faces meeting at each spot
	var spots := {}
	for i in verts.size():
		var key := Vector3i((verts[i] * 1e5).round())
		var n := normals[i] * out_sign
		if not spots.has(key):
			spots[key] = [Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO, 0]
		var s: Array = spots[key]
		s[0] = Basis(s[0].x + n * n.x, s[0].y + n * n.y, s[0].z + n * n.z)
		s[1] += n
		s[2] += 1
	var push := {}
	for key in spots:
		var s: Array = spots[key]
		var k := float(s[2])
		var a: Basis = s[0]
		var reg := 1e-3 * k            # keeps a lone face or a single edge solvable
		a = Basis(a.x + Vector3(reg, 0, 0), a.y + Vector3(0, reg, 0), a.z + Vector3(0, 0, reg))
		var v: Vector3 = a.inverse() * s[1] * t
		push[key] = v.limit_length(3.0 * t)
	var new_normals := PackedVector3Array()
	var uv2 := PackedVector2Array()
	new_normals.resize(verts.size())
	uv2.resize(verts.size())
	for i in verts.size():
		var v: Vector3 = push[Vector3i((verts[i] * 1e5).round())]
		verts[i] -= v
		new_normals[i] = v.normalized() if v.length() > 1e-7 else Vector3.UP
		uv2[i] = Vector2(v.length(), 0.0)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = new_normals
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_TANGENT] = null
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays if i == oi else mesh.surface_get_arrays(i))
		out.surface_set_material(i, mesh.surface_get_material(i))
		out.surface_set_name(i, mesh.surface_get_name(i))
	return out


static func _bounds(verts: PackedVector3Array) -> AABB:
	if verts.is_empty():
		return AABB()
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box


## set a shader parameter on every variant of a Blender material, e.g.
## set_param("pa_led", "emission_energy", 6.0)
func set_param(material: String, param: String, value: Variant) -> void:
	for m: ShaderMaterial in _by_name.get(material, []):
		m.set_shader_parameter(param, value)


func _make(name: String, src: Material, compat: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("srgb_io", compat)
	var info: Dictionary = _meta.materials.get(name, {})
	var c: Array = info.get("color", [0.8, 0.8, 0.8])
	var color := Vector3(c[0], c[1], c[2])
	if info.is_empty() and src is BaseMaterial3D:
		var a: Color = src.albedo_color.srgb_to_linear()
		color = Vector3(a.r, a.g, a.b)
	match info.get("kind", "toon"):
		"toon":
			m.set_shader_parameter("kind", 0)
			m.set_shader_parameter("albedo", color)
			if info.get("texture", false) and src is BaseMaterial3D and src.albedo_texture:
				m.set_shader_parameter("use_tex", true)
				m.set_shader_parameter("albedo_tex", src.albedo_texture)
				m.set_shader_parameter("albedo", Vector3.ONE)
		"emit":
			m.set_shader_parameter("kind", 1)
			m.set_shader_parameter("emission", color)
			m.set_shader_parameter("emission_energy", info.strength)
		"outline":
			m.set_shader_parameter("kind", 2)
			m.set_shader_parameter("emission", color)
		"sky":
			m.set_shader_parameter("kind", 3)
			_set_window_view(m, name)
	for prefix: String in STATUS_LIGHTS:
		if name.begins_with(prefix):
			var led: Color = STATUS_LIGHTS[prefix].srgb_to_linear()
			m.set_shader_parameter("status_light", true)
			m.set_shader_parameter("emission", Vector3(led.r, led.g, led.b))
			m.set_shader_parameter("emission_energy", 1.0)
	if name.begins_with("mat_fiche_screen"):
		# the microfiche display idles on a turning globe (toon.gdshader kind 4), mapped across the
		# screen's world-space rectangle (written by pipeline/godot/export_glb.py)
		var fs: Dictionary = _meta.points.fiche_screen
		m.set_shader_parameter("kind", 4)
		m.set_shader_parameter("albedo_tex", GLOBE)
		m.set_shader_parameter("screen_center", Vector3(fs.center[0], fs.center[1], fs.center[2]))
		m.set_shader_parameter("screen_size", Vector2(fs.size[0], fs.size[1]))
		m.set_shader_parameter("emission_energy", GLOBE_GLOW)
	return m


## the window's view: where the panorama sits behind the window and how it swings as the room pans.
## The hole in the wall under the window ("wall_hole_view") gets the same view, centred on itself.
func _set_window_view(m: ShaderMaterial, name: String) -> void:
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WINDOW_VIEW_META))
	var w: Array = _meta.points.window
	var zoom := VIEW_ZOOM
	var pitch := VIEW_PITCH
	if name == "wall_hole_view" and _meta.points.get("hole") != null:
		w = _meta.points.hole
		zoom = HOLE_VIEW_ZOOM
		pitch = HOLE_VIEW_PITCH
	var cam: Dictionary = _meta.camera
	var window := Vector3(w[0], w[1], w[2])
	m.set_shader_parameter("use_view", true)
	m.set_shader_parameter("window_view", WINDOW_VIEW)
	m.set_shader_parameter("window_depth", WINDOW_DEPTH)
	m.set_shader_parameter("view_window", window)
	m.set_shader_parameter("view_zoom", zoom)
	m.set_shader_parameter("view_yaw", -atan2(window.x - VIEW_AHEAD_X, cam.pos_z - window.z) * zoom)
	m.set_shader_parameter("view_pitch", deg_to_rad(pitch))
	m.set_shader_parameter("view_frame", Vector3(deg_to_rad(v.hfov_deg), deg_to_rad(v.pitch_top_deg), deg_to_rad(v.pitch_bottom_deg)))
	m.set_shader_parameter("view_depth", Vector3(v.depth_near_m, v.depth_far_m, v.depth_top_m))
	m.set_shader_parameter("view_haze_m", VIEW_HAZE_M)
