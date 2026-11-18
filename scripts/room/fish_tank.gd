extends Node
## The reef tank at the cabin's left end and the gauge board above it. The tank is scenes/fish_tank.tscn
## and the widened left end of the cabin is scenes/room_left.tscn, both instanced under the room in
## scenes/main.tscn, so the editor shows them the way the game does. main.gd creates this as
## `main.fish_tank` and calls build() before the picker and the materials are set up, then update()
## every frame. build() only registers the tank; it does not create meshes or move the room.
##
## The scene is boxes, cylinders and spheres (no Blender on hand), in the same look as the
## pipeline's props: one flat colour per part, and an inverted-hull outline (a second, slightly
## bigger surface with its faces turned inside out, kind "outline") on the parts that face the
## room. Inside the tank parts have no hull, so the bleached corals read bright. Rebuild it with
## scripts/dev/export_fish_tank.gd after changing the builders below.
##
## The story it tells is the ocean's, in miniature: the water is too warm (corals bleach white
## once they're stressed by heat), too acidic (dissolved CO2) and short of oxygen (warm water holds
## less). The gauge board shows all three, and the chiller that should keep the water cool is dead.
##
## Two object groups: "tank" (stand, tank, contents, chiller) and "tank_gauges" (the board). Their
## labels and monologues are in room/interactions.gd and data/dialogue.json.

const EXTRA := 2.4                      # m the cabin's left end was widened (room_camera.gd's CAM_MIN uses it)
const WALL_Z := -2.0                    # the back wall's face (Godot z; the room faces +z)
const HULL := 0.016                     # outline hull thickness, as the pipeline's (ASSET_GUIDE.md)

const TX := -6.35                       # tank centre x
const STAND_H := 0.72
const TANK := Vector3(1.2, 0.58, 0.48)
const TANK_Z := WALL_Z + 0.08 + 0.24    # tank centre z: 8 cm off the wall
const BOTTOM := STAND_H + 0.02          # the tank's glass floor
const WATER_TOP := STAND_H + 0.53
const BOARD_Y := 2.02                   # gauge board centre height
const MODEL := "res://scenes/fish_tank.tscn"

var _main: Node
var _fish: Array = []                   # [pivot, tail, centre x, swim half-range, speed, phase, y, z]
var _bubbles: Array = []                # [MeshInstance3D, x, z, phase]
var _kelp: Array = []                   # [Node3D, phase]
var _needles: Array = []                # [pivot, angle (rad), phase]
var _mats := {}                         # key -> StandardMaterial3D
var _meta: Dictionary


## registers the tank scene's groups and materials in meta (main.gd's scene_meta.json) so the
## picker numbers them and room_materials.gd styles them
func build(main: Node, room: Node3D, meta: Dictionary, _lights: Node3D) -> void:
	_main = main
	_meta = meta
	var model := room.get_node_or_null("FishTank") as Node3D
	if model == null:
		model = (load(MODEL) as PackedScene).instantiate()
		model.name = "FishTank"
		room.add_child(model)
	_register(model)
	_bind(model)


## the tank, its gauges and its lights. export_fish_tank.gd saves what this returns; the game loads
## that scene instead of calling this.
func build_model() -> Node3D:
	var root := Node3D.new()
	root.name = "FishTank"
	var tank := _group(root, "tank")
	_build_stand(tank)
	_build_tank(tank)
	_build_contents(tank)
	_build_chiller(tank)
	_build_gauges(_group(root, "tank_gauges"))
	_add_lights(root)
	_apply_motion(0.0)                  # the pose the editor shows, and the game's first frame
	return root


func _add_lights(root: Node3D) -> void:
	var glow := OmniLight3D.new()       # the hood's lamp, lighting the reef and the wall around it
	glow.name = "tank_glow"
	glow.light_color = Color(0.55, 0.85, 1.0)
	glow.light_energy = 1.6
	glow.omni_range = 3.5
	glow.omni_attenuation = 2.0
	glow.position = Vector3(TX, WATER_TOP - 0.02, TANK_Z + 0.35)
	root.add_child(glow)
	var fill := OmniLight3D.new()       # a little warm light spilling over from the room, so the stand reads
	fill.name = "tank_corner_fill"
	fill.light_color = Color(1.0, 0.78, 0.55)
	fill.light_energy = 2.6
	fill.omni_range = 6.0
	fill.omni_attenuation = 2.0
	fill.position = Vector3(TX + 0.6, 1.6, TANK_Z + 2.6)
	root.add_child(fill)


## per frame: fish swim, bubbles rise, kelp sways, needles twitch, the chiller's fault light blinks
func update() -> void:
	_apply_motion(_main.clock)
	var blink := 1.0 if fmod(_main.clock, 36.0) < 18.0 else 0.0
	_main.materials.set_param("fishtank_chiller_fault", "emission_energy", 4.0 * blink)


func _apply_motion(t: float) -> void:
	for f in _fish:
		var pivot: Node3D = f[0]
		var s: float = sin(t * f[4] + f[5])
		var v: float = cos(t * f[4] + f[5])
		pivot.position = Vector3(f[2] + f[3] * s, f[6] + 0.015 * sin(t * 0.09 + f[5]), f[7])
		pivot.rotation.y = 0.0 if v >= 0.0 else PI
		f[1].rotation.y = 0.5 * sin(t * 0.7 + f[5])
	for b in _bubbles:
		var k: float = fmod(t * 0.012 + b[3], 1.0)
		b[0].position = Vector3(b[1] + 0.01 * sin(t * 0.3 + b[3] * 9.0), BOTTOM + 0.05 + k * (WATER_TOP - BOTTOM - 0.06), b[2])
	for k in _kelp:
		k[0].rotation.z = 0.12 * sin(t * 0.05 + k[1])
	for n in _needles:
		n[0].rotation.z = n[1] + 0.03 * sin(t * 0.37 + n[2]) + 0.015 * sin(t * 1.3 + n[2] * 3.0)


# ---------------------------------------------------------------- the tank
func _build_stand(g: Node3D) -> void:
	var wood := _mat("stand_wood", Color(0.62, 0.42, 0.26))
	var door := _mat("stand_door", Color(0.72, 0.50, 0.31))
	var brass := _mat("stand_knob", Color(0.85, 0.66, 0.30))
	var z := TANK_Z + 0.02
	_part(g, "stand_body", "box", Vector3(1.3, STAND_H, 0.56), Vector3(TX, STAND_H / 2.0, z), wood)
	_part(g, "stand_top", "box", Vector3(1.36, 0.04, 0.6), Vector3(TX, STAND_H - 0.02, z), wood)
	for side in [-1, 1]:
		_part(g, "stand_door", "box", Vector3(0.58, 0.56, 0.02), Vector3(TX + side * 0.31, 0.36, z + 0.29), door, Vector3.ZERO, false)
		_part(g, "stand_knob", "sphere", Vector3(0.035, 0.035, 0.035), Vector3(TX + side * 0.06, 0.40, z + 0.31), brass, Vector3.ZERO, false)


func _build_tank(g: Node3D) -> void:
	var trim := _mat("trim", Color(0.10, 0.10, 0.11))
	var hood := _mat("hood", Color(0.20, 0.22, 0.24))
	var water := _mat("water_back", Color(0.10, 0.48, 0.90), "emit", 0.55)
	var surface := _mat("water_surface", Color(0.55, 0.90, 1.0), "emit", 0.9)
	var lamp := _mat("hood_lamp", Color(0.75, 0.95, 1.0), "emit", 4.0)
	var hx := TANK.x / 2.0
	var front := TANK_Z + TANK.z / 2.0
	var mid_y := STAND_H + TANK.y / 2.0
	# the water: a lit back panel behind everything, and a thin bright surface line
	_part(g, "water_back", "box", Vector3(TANK.x - 0.04, WATER_TOP - BOTTOM, 0.01), Vector3(TX, (BOTTOM + WATER_TOP) / 2.0, TANK_Z - TANK.z / 2.0 + 0.02), water, Vector3.ZERO, false)
	_part(g, "water_surface", "box", Vector3(TANK.x - 0.04, 0.004, TANK.z - 0.04), Vector3(TX, WATER_TOP, TANK_Z), surface, Vector3.ZERO, false)
	# the frame: black trim round the glass
	_part(g, "trim_bottom", "box", Vector3(TANK.x + 0.02, 0.04, TANK.z + 0.02), Vector3(TX, STAND_H + 0.02, TANK_Z), trim)
	_part(g, "trim_top", "box", Vector3(TANK.x + 0.02, 0.025, 0.025), Vector3(TX, STAND_H + TANK.y, front), trim, Vector3.ZERO, false)
	for side in [-1, 1]:
		_part(g, "trim_post", "box", Vector3(0.025, TANK.y, 0.025), Vector3(TX + side * hx, mid_y, front), trim, Vector3.ZERO, false)
		_part(g, "trim_post_back", "box", Vector3(0.025, TANK.y, 0.025), Vector3(TX + side * hx, mid_y, TANK_Z - TANK.z / 2.0), trim, Vector3.ZERO, false)
	# the hood and its lamp (the glow along its front edge)
	_part(g, "hood", "box", Vector3(TANK.x + 0.06, 0.07, TANK.z + 0.06), Vector3(TX, STAND_H + TANK.y + 0.045, TANK_Z), hood)
	_part(g, "hood_lamp", "box", Vector3(TANK.x - 0.1, 0.014, 0.012), Vector3(TX, STAND_H + TANK.y + 0.012, front + 0.03), lamp, Vector3.ZERO, false)
	# the heater along the back corner, with its little red pilot
	_part(g, "heater", "cyl", Vector3(0.03, 0.34, 0.03), Vector3(TX + hx - 0.06, BOTTOM + 0.24, TANK_Z - 0.17), _mat("heater", Color(0.30, 0.32, 0.30)), Vector3.ZERO, false)
	_part(g, "heater_pilot", "box", Vector3(0.018, 0.018, 0.01), Vector3(TX + hx - 0.06, BOTTOM + 0.38, TANK_Z - 0.155), _mat("heater_pilot", Color(1.0, 0.25, 0.10), "emit", 3.0), Vector3.ZERO, false)


func _build_contents(g: Node3D) -> void:
	var sand := _mat("sand", Color(0.88, 0.78, 0.58))
	var rock := _mat("rock", Color(0.48, 0.43, 0.39))
	var algae_rock := _mat("algae_rock", Color(0.46, 0.46, 0.26))
	var bone := _mat("coral_bleached", Color(0.97, 0.95, 0.88))
	var pale := _mat("coral_pale", Color(0.96, 0.86, 0.82))
	var fading := _mat("coral_fading", Color(0.96, 0.58, 0.46))
	var kelp := _mat("kelp", Color(0.50, 0.46, 0.20))
	_part(g, "sand", "box", Vector3(TANK.x - 0.04, 0.05, TANK.z - 0.04), Vector3(TX, BOTTOM + 0.025, TANK_Z), sand, Vector3.ZERO, false)
	var floor_y := BOTTOM + 0.05
	# live rock, some of it furred with algae
	_part(g, "rock", "box", Vector3(0.24, 0.14, 0.16), Vector3(TX - 0.30, floor_y + 0.05, TANK_Z - 0.08), rock, Vector3(0, 18, 9), false)
	_part(g, "rock", "box", Vector3(0.18, 0.10, 0.14), Vector3(TX + 0.18, floor_y + 0.04, TANK_Z - 0.10), algae_rock, Vector3(0, -24, -7), false)
	_part(g, "rock", "box", Vector3(0.14, 0.08, 0.12), Vector3(TX - 0.04, floor_y + 0.03, TANK_Z + 0.06), rock, Vector3(0, 40, 4), false)
	# staghorn corals, bleached bone white: branches fanning up from a base
	for c in [[TX - 0.30, TANK_Z - 0.08, floor_y + 0.12, bone], [TX + 0.34, TANK_Z - 0.04, floor_y, bone], [TX + 0.05, TANK_Z - 0.14, floor_y, pale]]:
		var i := 0
		for a in [-38.0, -16.0, 4.0, 22.0, 40.0]:
			var length := 0.13 + 0.05 * float((i * 7) % 3)
			var rad := deg_to_rad(a)
			var base := Vector3(c[0], c[2], c[1])
			_part(g, "coral_branch", "cyl", Vector3(0.024, length, 0.03), base + Vector3(-sin(rad), cos(rad), 0) * length / 2.0, c[3], Vector3(0, i * 25.0, a), false)
			i += 1
	# a brain coral, half bleached
	_part(g, "coral_brain", "sphere", Vector3(0.16, 0.10, 0.14), Vector3(TX - 0.12, floor_y + 0.03, TANK_Z + 0.10), pale, Vector3.ZERO, false)
	# a table coral, gone white
	_part(g, "coral_table_stalk", "cyl", Vector3(0.03, 0.10, 0.03), Vector3(TX + 0.20, floor_y + 0.12, TANK_Z - 0.10), bone, Vector3.ZERO, false)
	_part(g, "coral_table", "cyl", Vector3(0.20, 0.018, 0.20), Vector3(TX + 0.20, floor_y + 0.17, TANK_Z - 0.10), bone, Vector3.ZERO, false)
	# the last coral still holding its colour: a sea fan
	_part(g, "coral_fan", "box", Vector3(0.14, 0.18, 0.012), Vector3(TX + 0.46, floor_y + 0.09, TANK_Z - 0.16), fading, Vector3(0, -15, 6), false)
	# kelp, swaying
	for k in [[TX - 0.48, 0.0], [TX - 0.42, 1.9]]:
		var strand := Node3D.new()
		strand.name = "Kelp%d" % (_kelp.size() + 1)
		strand.set_meta("kelp_phase", k[1])
		g.add_child(strand)
		strand.position = Vector3(k[0], floor_y, TANK_Z - 0.17)
		for s in 4:
			_part(strand, "kelp", "box", Vector3(0.035, 0.11, 0.008), Vector3(0.012 * (s % 2), 0.055 + s * 0.105, 0), kelp, Vector3(0, 0, 6.0 * (1 - 2 * (s % 2))), false)
		_kelp.append([strand, k[1]])
	# fish: a clownfish, a yellow tang, two blue chromis
	var white := _mat("fish_white", Color(0.97, 0.97, 0.95))
	for f in [[Color(1.0, 0.48, 0.10), true, 0.022, 0.0, BOTTOM + 0.30, TANK_Z + 0.05, 0.30],
			[Color(1.0, 0.86, 0.22), false, 0.016, 2.1, BOTTOM + 0.38, TANK_Z - 0.05, 0.36],
			[Color(0.26, 0.56, 0.98), false, 0.028, 4.0, BOTTOM + 0.22, TANK_Z + 0.12, 0.22],
			[Color(0.26, 0.56, 0.98), false, 0.025, 5.2, BOTTOM + 0.26, TANK_Z + 0.14, 0.24]]:
		var body := _mat("fish_%d" % _fish.size(), f[0])
		var pivot := Node3D.new()
		pivot.name = "Fish%d" % (_fish.size() + 1)
		g.add_child(pivot)
		_part(pivot, "fish_body", "box", Vector3(0.10, 0.055, 0.03), Vector3.ZERO, body, Vector3.ZERO, false)
		if f[1]:
			_part(pivot, "fish_stripe", "box", Vector3(0.016, 0.057, 0.032), Vector3(0.016, 0, 0), white, Vector3.ZERO, false)
		var tail := Node3D.new()
		tail.name = "Tail"
		pivot.add_child(tail)
		tail.position = Vector3(-0.05, 0, 0)
		_part(tail, "fish_tail", "box", Vector3(0.034, 0.046, 0.012), Vector3(-0.015, 0, 0), body, Vector3.ZERO, false)
		var swim: float = TANK.x / 2.0 - 0.14
		var centre := TX + (0.06 if _fish.size() % 2 == 0 else -0.06)
		var reach := swim * (0.6 + 0.12 * _fish.size())
		pivot.set_meta("fish", {"cx": centre, "range": reach, "speed": f[2], "phase": f[3], "y": f[4], "z": f[5]})
		_fish.append([pivot, tail, centre, reach, f[2], f[3], f[4], f[5]])
	# bubbles from an airstone in the back left corner
	var bubble := _mat("bubble", Color(0.85, 0.97, 1.0), "emit", 1.2)
	_part(g, "airstone", "box", Vector3(0.05, 0.025, 0.03), Vector3(TX - 0.50, floor_y + 0.012, TANK_Z - 0.12), _mat("airstone", Color(0.70, 0.66, 0.62)), Vector3.ZERO, false)
	for i in 5:
		var b := _part(g, "bubble", "box", Vector3(0.016, 0.016, 0.016), Vector3.ZERO, bubble, Vector3.ZERO, false)
		b.name = "Bubble%d" % (i + 1)
		var phase := i / 5.0
		b.set_meta("bubble", {"x": TX - 0.50, "z": TANK_Z - 0.12, "phase": phase})
		_bubbles.append([b, TX - 0.50, TANK_Z - 0.12, phase])


## the dead chiller on the floor beside the stand, its hoses running up into the tank
func _build_chiller(g: Node3D) -> void:
	var x := TX + 0.86
	var z := TANK_Z + 0.02
	_part(g, "chiller", "box", Vector3(0.30, 0.38, 0.32), Vector3(x, 0.19, z), _mat("chiller", Color(0.62, 0.66, 0.68)))
	_part(g, "chiller_grille", "box", Vector3(0.22, 0.20, 0.01), Vector3(x, 0.17, z + 0.165), _mat("chiller_grille", Color(0.22, 0.24, 0.26)), Vector3.ZERO, false)
	_part(g, "chiller_fault", "box", Vector3(0.03, 0.02, 0.01), Vector3(x + 0.08, 0.33, z + 0.165), _mat("chiller_fault", Color(1.0, 0.20, 0.10), "emit", 4.0), Vector3.ZERO, false)
	var hose := _mat("hose", Color(0.14, 0.14, 0.15))
	for dx in [-0.06, 0.06]:
		_part(g, "hose", "cyl", Vector3(0.025, STAND_H + TANK.y - 0.36, 0.025), Vector3(x + dx, 0.38 + (STAND_H + TANK.y - 0.36) / 2.0, z - 0.1), hose, Vector3.ZERO, false)
		_part(g, "hose", "cyl", Vector3(0.025, 0.24, 0.025), Vector3(x + dx - 0.12, STAND_H + TANK.y + 0.01, z - 0.1), hose, Vector3(0, 0, 90), false)


# ---------------------------------------------------------------- the gauge board
## three dials, each with its needle in the red, and a readout under it:
## water temperature (warming), pH (acidification) and dissolved oxygen (deoxygenation)
func _build_gauges(g: Node3D) -> void:
	var z := WALL_Z + 0.02
	_part(g, "gauge_board", "box", Vector3(1.04, 0.46, 0.03), Vector3(TX, BOARD_Y, z), _mat("gauge_board", Color(0.70, 0.52, 0.34)))
	var face := _mat("gauge_face", Color(0.95, 0.90, 0.76), "emit", 0.9)     # backlit dials
	var red := _mat("gauge_red", Color(1.0, 0.22, 0.12), "emit", 1.6)
	var ink := _mat("gauge_needle", Color(0.08, 0.06, 0.06))
	# [x, cap colour, readout colour, the needle's angle (deg, 0 = pointing right, + = up)]
	for d in [[TX - 0.33, Color(0.90, 0.30, 0.15), Color(1.0, 0.40, 0.15), 8.0],
			[TX, Color(0.62, 0.40, 0.80), Color(1.0, 0.70, 0.20), 14.0],
			[TX + 0.33, Color(0.30, 0.55, 0.95), Color(1.0, 0.40, 0.15), 4.0]]:
		var c := Vector3(d[0], BOARD_Y + 0.05, z + 0.035)
		_part(g, "gauge_dial", "cyl", Vector3(0.21, 0.04, 0.21), c, face, Vector3(90, 0, 0))
		# the red zone: a band of short ticks round the right-hand rim
		for a in [-5.0, 12.0, 29.0]:
			var r := deg_to_rad(a)
			_part(g, "gauge_red", "box", Vector3(0.035, 0.022, 0.006), c + Vector3(cos(r), sin(r), 0) * 0.08 + Vector3(0, 0, 0.022), red, Vector3(0, 0, a), false)
		var pivot := Node3D.new()
		pivot.name = "Needle%d" % (_needles.size() + 1)
		var angle := deg_to_rad(d[3])
		var phase: float = d[0] * 7.0
		pivot.set_meta("needle", {"angle": angle, "phase": phase})
		g.add_child(pivot)
		pivot.position = c + Vector3(0, 0, 0.026)
		_part(pivot, "gauge_needle", "box", Vector3(0.085, 0.012, 0.004), Vector3(0.036, 0, 0), ink, Vector3.ZERO, false)
		_needles.append([pivot, angle, phase])
		_part(g, "gauge_cap", "cyl", Vector3(0.03, 0.01, 0.03), c + Vector3(0, 0, 0.03), _mat("gauge_cap_%d" % _needles.size(), d[1]), Vector3(90, 0, 0), false)
		_part(g, "gauge_readout", "box", Vector3(0.15, 0.045, 0.01), Vector3(d[0], BOARD_Y - 0.15, z + 0.02), _mat("gauge_readout_%d" % _needles.size(), d[2], "emit", 2.5))


# ---------------------------------------------------------------- building blocks
## a new object group: a grp_<name> node. build() adds the name to meta.groups for the picker.
func _group(parent: Node3D, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = "grp_" + name
	parent.add_child(g)
	return g


## groups and materials the scene carries, written into meta the way the builders used to
func _register(root: Node) -> void:
	for group_name in ["tank", "tank_gauges"]:
		if not group_name in _meta.groups:
			_meta.groups.append(group_name)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat == null:
				continue
			var mat_name := mat.resource_name
			if mat_name == "" or _meta.materials.has(mat_name):
				continue
			var lin := Color.WHITE
			if mat is StandardMaterial3D:
				lin = mat.albedo_color.srgb_to_linear()
			_meta.materials[mat_name] = {
				"kind": mat.get_meta("kind", "toon"),
				"color": [lin.r, lin.g, lin.b],
				"strength": float(mat.get_meta("strength", 0.0)),
			}


## the nodes update() moves, found by the metadata build_model() stored on them
func _bind(root: Node) -> void:
	_fish.clear()
	_bubbles.clear()
	_kelp.clear()
	_needles.clear()
	for n in root.find_children("*", "", true, false):
		if n.has_meta("fish"):
			var fish: Dictionary = n.get_meta("fish")
			_fish.append([n, n.get_node("Tail"), fish.cx, fish.range, fish.speed, fish.phase, fish.y, fish.z])
		elif n.has_meta("bubble"):
			var bubble: Dictionary = n.get_meta("bubble")
			_bubbles.append([n, bubble.x, bubble.z, bubble.phase])
		elif n.has_meta("kelp_phase"):
			_kelp.append([n, float(n.get_meta("kelp_phase"))])
		elif n.has_meta("needle"):
			var needle: Dictionary = n.get_meta("needle")
			_needles.append([n, needle.angle, needle.phase])


## a flat-colour material. Its name, kind and strength are saved on it; build() copies them into
## meta.materials so room_materials.gd can turn it into the toon shader.
func _mat(key: String, srgb: Color, kind := "toon", strength := 0.0) -> StandardMaterial3D:
	var name := "fishtank_" + key
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.resource_name = name
		m.albedo_color = srgb
		m.set_meta("kind", kind)
		m.set_meta("strength", strength)
		_mats[name] = m
	return _mats[name]


## one part: a box, cylinder (size.x = diameter, size.y = height) or sphere at a position (relative
## to parent) and rotation (degrees). hull adds the black inverted-hull outline as a second surface.
func _part(parent: Node3D, name: String, shape: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D,
		rot := Vector3.ZERO, hull := true) -> MeshInstance3D:
	var prim: PrimitiveMesh
	match shape:
		"box":
			var b := BoxMesh.new()
			b.size = size
			prim = b
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = size.x / 2.0
			c.bottom_radius = size.z / 2.0
			c.height = size.y
			c.radial_segments = 10
			c.rings = 1
			prim = c
		"sphere":
			var s := SphereMesh.new()
			s.radius = size.x / 2.0
			s.height = size.y
			s.radial_segments = 10
			s.rings = 5
			prim = s
	var arrays := prim.get_mesh_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	if hull:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _hull(arrays, shape))
		mesh.surface_set_material(1, _outline())
	var mi := MeshInstance3D.new()
	var unique := "fishtank_" + name
	var n := 2
	while parent.get_node_or_null(NodePath(unique)) != null:
		unique = "fishtank_%s_%d" % [name, n]
		n += 1
	mi.name = unique
	mi.mesh = mesh
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot
	return mi


## the outline shell: every vertex pushed out by HULL, faces turned inside out so only its back shows
func _hull(arrays: Array, shape: String) -> Array:
	var h := arrays.duplicate(true)
	var verts: PackedVector3Array = h[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		match shape:
			"box":
				v += Vector3(signf(v.x), signf(v.y), signf(v.z)) * HULL
			"cyl":
				var r := Vector2(v.x, v.z)
				r = r.normalized() * HULL if r.length() > 1e-5 else Vector2.ZERO
				v += Vector3(r.x, signf(v.y) * HULL, r.y)
			_:
				v += v.normalized() * HULL
		verts[i] = v
	h[Mesh.ARRAY_VERTEX] = verts
	var idx: PackedInt32Array = h[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		var a := idx[i + 1]
		idx[i + 1] = idx[i + 2]
		idx[i + 2] = a
	h[Mesh.ARRAY_INDEX] = idx
	return h


## the pipeline's outline material (scene_meta.json's toon_outline: kind "outline", near-black)
func _outline() -> StandardMaterial3D:
	if not _mats.has("toon_outline"):
		var m := StandardMaterial3D.new()
		m.resource_name = "toon_outline"
		m.set_meta("kind", "outline")
		_mats["toon_outline"] = m
	return _mats["toon_outline"]
