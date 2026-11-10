extends Node
## Replaces every material in the imported room (assets/shelter.glb) with the toon shader
## (shaders/toon.gdshader).
##
## The room comes from Blender with plain glTF materials. assets/scene_meta.json says what each
## material really is, by its Blender name:
##   "toon"    lit, flat colour (optionally a texture: the cutting mat)
##   "emit"    glows (lamp bulb, lantern flame, PA status light, readouts)
##   "outline" the black inverted-hull shell around a prop
##   "sky"     the animated storm behind the window
## The microfiche display's screen ("mat_fiche_screen_*") is special-cased to a turning globe.
##
## One ShaderMaterial is made per (Blender material, object group, outlined?) combination, so the
## mask's group id and the prop dimming are plain uniforms. (Per-instance uniforms would be simpler,
## but they don't work on every renderer.) Scripts change a material later with set_param().

const TOON := preload("res://shaders/toon.gdshader")
const GLOBE := preload("res://ui/globe_equirect.png")
## In Blender the outline shells also shadowed the props inside them, which gave the video its dark,
## moody props; in Godot outlined props get only this share of direct light to match.
const PROP_DIRECT_LIGHT := 0.12
const GLOBE_GLOW := 1.4

var _meta: Dictionary
var _by_name := {}                      # Blender material name -> [every ShaderMaterial variant of it]


## build and assign the materials. group_of(mesh) gives a mesh's object group id (0 = none).
## compat: the Compatibility renderer wants colours sRGB-encoded (see toon.gdshader's srgb_io).
func setup(room: Node3D, meta: Dictionary, group_of: Callable, compat: bool) -> void:
	_meta = meta
	var variants := {}
	for mi: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
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
