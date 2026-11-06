extends Node
## The cabin. Swaps the imported materials for the toon shader, pans the camera
## when the cursor pushes against the screen edges, reads the mask render to find
## what is under the cursor, and runs the interactions (window, microfiche reader, cabinet,
## and the close-up camera views: the workbench's crafting view in scripts/crafting.gd and the
## ham radio's in scripts/radio_view.gd).
##
## Timings are in "frames" of the 24 fps clock the video used, so numbers port
## straight over from pipeline/scene/build_story.py.

const W := 480
const H := 270
const TICK := 24.0
const PIX := 6.6 / 480.0                  # world units per low-res pixel
const EDGE := 48.0                        # px from the screen edge where the cursor starts pushing
const PAN_SPEED := 2.6                    # m/s at full push
const PAN_EASE := 8.0                     # how quickly the camera speeds up / settles (1/s)
const CAM_MIN := -1.85                    # camera x limits: left wall .. just past the speaker corner
const CAM_MAX := 3.0
const SH_ANGLE := deg_to_rad(176.0)
const SHUTTER_FRAMES := 48.0
const DOOR_ANGLE := deg_to_rad(105.0)
const DOOR_FRAMES := 36.0
const CAB_LIGHT := 160.0 / (4.0 * PI * PI)   # Blender's 160 W interior glow in Godot units
const PROP_DIRECT_LIGHT := 0.12
const COMPAT_SHADOW_LIGHT_SCALE := 0.2      # fitted against Forward+, see _ready()
const MASK_ID_OFFSET := 4                 # mask ids are stored 4 steps up (see toon.gdshader)
const TOON := preload("res://shaders/toon.gdshader")
const CRAFTING := preload("res://scripts/crafting.gd")
const RADIO_VIEW := preload("res://scripts/radio_view.gd")
const GLOBE := preload("res://ui/globe_equirect.png")
const DEBUG_MENU := true                  # F9 developer menu; turn off for a release

const LABELS := {
	"shutters": "STORM SHUTTERS", "cabinet": "SUPPLY CABINET", "microfiche": "MICROFICHE MAP", "speaker": "PA SPEAKER",
	"radio": "HAM RADIO (BROKEN)", "jar": "DRIED MUSHROOMS", "papers": "ROLLING PAPERS", "bench": "WORKBENCH",
	"lantern": "LANTERN", "instruments": "WEATHER GAUGES", "power": "POWER STATION", "filter": "WATER FILTER",
	"crates": "SUPPLY CRATES", "sandbags": "SANDBAGS", "flashlight": "FLASHLIGHT",
}

@onready var world_vp: SubViewport = $WorldVP
@onready var mask_vp: SubViewport = $MaskVP
@onready var room: Node3D = $WorldVP/Room
@onready var camera: Camera3D = $WorldVP/Camera
@onready var mask_cam: Camera3D = $MaskVP/MaskCam
@onready var screen: TextureRect = $Screen
@onready var ui: Control = $UI/Overlay
@onready var lantern_light: OmniLight3D = $WorldVP/Lights/lantern_glow
@onready var cabinet_light: OmniLight3D = $WorldVP/Lights/cabinet_interior

var meta: Dictionary
var group_ids := {}                       # group name -> id written into the mask (1-based)
var group_names: Array[String] = []
var groups := {}                          # group name -> Node3D
var mats := {}                            # Blender material name -> [ShaderMaterial per group variant]
var post: ShaderMaterial
## Compatibility (the only renderer on the web) wants shader colours sRGB; toon.gdshader compensates
var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"

var clock := 0.0                          # 24 fps frames since start
var cursor := Vector2(W / 2.0, H / 2.0)
var cursor_override = null                # Vector2 while a demo script drives the cursor
var hover := ""
var hover_t := 0.0
var click_at := -1e9
var shimmer_step := -1

# camera
var cam_left: float
var cam_right: float
var cam_x := 0.0
var cam_v := 0.0
var push := 0.0                           # -1..1, how hard the cursor (or A/D) pushes the view
var beyond := Vector2.ZERO                # -1/0/+1 per axis: the pointer is past that edge of the game
                                          # area (e.g. in the black borders around the scaled picture)
var mouse_seen := false                   # no edge-push until the mouse has really moved (web starts at 0,0)
var web_out := Vector2.ZERO               # web: which way the mouse left the page (see _watch_web_mouse)
var _web_callbacks := []                  # keeps the JavaScript callbacks alive
var edge_hold := false                    # after a close-up or panel the cursor may sit in an edge band
                                          # (BACK is top-left): no edge-push until it has left the band
var room_basis: Basis                     # the room camera's fixed tilt, height, depth and zoom
var room_y: float
var room_z: float
var room_size: float

# close-up camera views (scripts/close_view.gd): top-down over the cutting mat, the radio's front
var crafting: Node
var radio_view: Node
var views: Array[Node] = []

# window
var shutter := 0.0
var shutter_open := false
var shutter_from := 0.0
var shutter_at := -1e9
var hinge_l: Node3D
var hinge_r: Node3D
var heat := 0.0
var heat_from := 0.0
var heat_at := -1e9
var lantern_e0 := 1.0

# cabinet
var door := 0.0
var door_open := false
var door_from := 0.0
var door_at := -1e9
var door_l: Node3D
var door_r: Node3D


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/scene_meta.json"))
	for i in meta.groups.size():
		group_names.append(meta.groups[i])
		group_ids[meta.groups[i]] = i + 1
	for name in group_names:
		groups[name] = room.find_child("grp_" + name, true, false)
	_toonify(room)
	for n in meta.start_hidden:
		var node := room.find_child(n, true, false)
		if node:
			node.visible = false
	hinge_l = room.find_child("shutter_hinge_L", true, false)
	hinge_r = room.find_child("shutter_hinge_R", true, false)
	door_l = room.find_child("cabinet_hinge_L", true, false)
	door_r = room.find_child("cabinet_hinge_R", true, false)
	lantern_e0 = lantern_light.light_energy
	if compat:
		# Compatibility adds each shadow-casting light in its own pass, in sRGB space, which
		# brightens everything it touches; scale those lights so the web build matches Forward+
		for l: Light3D in $WorldVP/Lights.get_children():
			if l.shadow_enabled:
				l.light_energy *= COMPAT_SHADOW_LIGHT_SCALE

	cam_left = meta.camera.x_left
	cam_right = meta.camera.x_right
	cam_x = cam_right
	room_basis = camera.basis
	room_y = camera.position.y
	room_z = camera.position.z
	room_size = camera.size
	crafting = CRAFTING.new()
	crafting.name = "Crafting"
	add_child(crafting)
	crafting.setup(meta, W, H)
	radio_view = RADIO_VIEW.new()
	radio_view.name = "RadioView"
	add_child(radio_view)
	radio_view.setup(meta, camera)
	views = [crafting, radio_view]
	if OS.has_feature("web"):
		_watch_web_mouse()

	post = screen.material
	screen.texture = world_vp.get_texture()
	post.set_shader_parameter("scene_tex", world_vp.get_texture())
	post.set_shader_parameter("mask_tex", mask_vp.get_texture())
	var pal := PackedVector3Array()
	for c in JSON.parse_string(FileAccess.get_file_as_string("res://assets/palette.json")):
		pal.append(Vector3(c[0], c[1], c[2]) / 255.0)
	post.set_shader_parameter("palette", pal)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_start_demo_if_asked()


# ---------------------------------------------------------------- materials
## One material per (Blender material, object group, outlined?) so group id and prop
## dimming are plain uniforms -- no instance uniforms, which keeps every renderer happy.
func _toonify(root: Node) -> void:
	var variants := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var gid := _group_of(mi)
		var keys: Array[String] = []
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			keys.append(src.resource_name if src else "")
		# Blender's outline shells also shadowed the prop inside them, which gave the
		# video its dark, moody props; dim their direct light to match
		var outlined := keys.any(func(k): return meta.materials.get(k, {}).get("kind") == "outline")
		for i in keys.size():
			var key := keys[i]
			var vkey := "%s|%d|%s" % [key, gid, outlined]
			if not variants.has(vkey):
				var m := _make_material(key, mi.get_active_material(i))
				m.set_shader_parameter("group_id", gid)
				m.set_shader_parameter("direct_light", PROP_DIRECT_LIGHT if outlined else 1.0)
				variants[vkey] = m
				if not mats.has(key):
					mats[key] = []
				mats[key].append(m)
			mi.set_surface_override_material(i, variants[vkey])


## set a shader parameter on every variant of a Blender material
func set_mat_param(material: String, param: String, value: Variant) -> void:
	for m: ShaderMaterial in mats.get(material, []):
		m.set_shader_parameter(param, value)


func _make_material(name: String, src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("srgb_io", compat)
	var info: Dictionary = meta.materials.get(name, {})
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
		# the microfiche display idles on a turning globe (toon.gdshader kind 4)
		var fs: Dictionary = meta.points.fiche_screen
		m.set_shader_parameter("kind", 4)
		m.set_shader_parameter("albedo_tex", GLOBE)
		m.set_shader_parameter("screen_center", Vector3(fs.center[0], fs.center[1], fs.center[2]))
		m.set_shader_parameter("screen_size", Vector2(fs.size[0], fs.size[1]))
		m.set_shader_parameter("emission_energy", 1.4)
	return m


func _group_of(n: Node) -> int:
	while n and n != room:
		if n.name.begins_with("grp_"):
			return group_ids.get(n.name.substr(4), 0)
		n = n.get_parent()
	return 0


# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	var step := delta * TICK
	clock += step
	var raw: Vector2 = cursor_override if cursor_override != null else ui.get_global_mouse_position()
	beyond = Vector2(-1.0 if raw.x < 0.0 else (1.0 if raw.x >= W else 0.0),
			-1.0 if raw.y < 0.0 else (1.0 if raw.y >= H else 0.0))
	cursor = raw.clamp(Vector2.ZERO, Vector2(W - 1, H - 1))

	# camera follows the cursor's push on the edges, snapped to whole pixels so the art never swims
	_update_push()
	cam_v = lerpf(cam_v, push * PAN_SPEED, 1.0 - exp(-delta * PAN_EASE))
	cam_x += cam_v * delta
	if cam_x < CAM_MIN or cam_x > CAM_MAX:
		cam_x = clampf(cam_x, CAM_MIN, CAM_MAX)
		cam_v = 0.0
	var cam_px := roundf((cam_x - cam_left) / PIX)
	var room := Transform3D(room_basis, Vector3(cam_left + cam_px * PIX, room_y, room_z))
	var pose: Array = [room, room_size]
	for v in views:
		v.update(clock, cursor, not ui.over_ui(cursor))
		if v.t > 0.0:
			pose = v.camera_pose(room, room_size)
	if ui.panel == "fiche":
		ui.fiche.update(cursor, delta, _pan_keys(), _mouse_outside())
	for cam: Camera3D in [camera, mask_cam]:
		cam.transform = pose[0]
		cam.size = pose[1]

	_update_window()
	_update_cabinet()
	_update_hover(step)
	_update_ambience()

	var win: Vector2 = camera.unproject_position(_v3(meta.points.window))
	post.set_shader_parameter("frame", clock)
	post.set_shader_parameter("cam_px", cam_px)
	post.set_shader_parameter("noise_seed", fmod(clock, 97.0))
	post.set_shader_parameter("cursor", cursor.floor())
	post.set_shader_parameter("target_id", group_ids.get(hover, 0) if hover != "" else 0)
	post.set_shader_parameter("build", 1.0 - exp(-hover_t / 10.0))
	post.set_shader_parameter("outline_px", 3 if clock - click_at < 4.0 else 2)
	post.set_shader_parameter("heat", heat)
	post.set_shader_parameter("heat_focus", 1.0)
	post.set_shader_parameter("shutter", shutter)
	post.set_shader_parameter("window_px", win)
	post.set_shader_parameter("dim", ui.panel_scale())
	var s := int(clock / 2.0)
	if s != shimmer_step:
		shimmer_step = s
		post.set_shader_parameter("shimmer_off", Vector2(randi() % 4, randi() % 4))
	ui.queue_redraw()


func _update_hover(step: float) -> void:
	var target := ""
	if ui.panel == "" and not ui.over_ui(cursor) and not ui.flying() and active_view() == null:
		target = _group_at(cursor)
	hover_t = hover_t + step if (target != "" and target == hover) else (1.0 if target != "" else 0.0)
	hover = target


func _group_at(p: Vector2) -> String:
	var img := mask_vp.get_texture().get_image()
	if img == null:                      # first frame, or a headless run with no renderer
		return ""
	var ip := Vector2i(p)
	for o in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var q: Vector2i = (ip + o).clamp(Vector2i.ZERO, Vector2i(W - 1, H - 1))
		var id := roundi(img.get_pixelv(q).r * 255.0 / 12.0) - MASK_ID_OFFSET
		if id >= 1 and id <= group_names.size():
			var name := group_names[id - 1]
			if LABELS.has(name) or (name == "sky" and shutter_open):
				return name
	return ""


func label_for(group: String) -> String:
	var name: String = "CLOSE SHUTTERS" if group == "sky" else LABELS.get(group, "")
	if ui.held != null and name != "":
		return "USE %s ON %s" % [ui.held.name, name]
	return name


func _update_ambience() -> void:
	set_mat_param("storm_window_emit", "sky_w", clock * 2.2 / 600.0)
	set_mat_param("pa_led", "emission_energy", 6.0 + 3.0 * sin(clock * 0.21))
	# lantern: gentle flame flicker
	var n := sin(clock * 0.9) * 0.5 + sin(clock * 2.3 + 1.7) * 0.3 + sin(clock * 5.1) * 0.2
	lantern_light.light_energy = lantern_e0 * (1.0 + 0.12 * n)


# ---------------------------------------------------------------- the window
func _update_window() -> void:
	var t := clock - shutter_at
	if shutter_open:
		shutter = shutter_from + (1.0 - shutter_from) * out_back(t / SHUTTER_FRAMES)
		heat = heat_from + (0.62 - heat_from) * smooth((clock - heat_at - 8.0) / 110.0)
	else:
		var k := clampf(t / SHUTTER_FRAMES, 0.0, 1.0)
		shutter = shutter_from * (1.0 - pow(k, 2.2))
		if t > SHUTTER_FRAMES:                                # thud: a small rebound against the frame
			var b := t - SHUTTER_FRAMES
			shutter = 0.025 * exp(-b / 4.0) * absf(sin(b * 0.9)) * signf(shutter_from)
		heat = heat_from * (1.0 - smooth((clock - heat_at) / 90.0))
	if hinge_l:
		hinge_l.rotation.y = -SH_ANGLE * shutter
		hinge_r.rotation.y = SH_ANGLE * shutter


func toggle_shutters() -> void:
	shutter_from = shutter
	heat_from = heat
	shutter_open = not shutter_open
	shutter_at = clock
	heat_at = clock
	if shutter_open:
		GameState.set_flag("window_opened")


# ---------------------------------------------------------------- the supply cabinet
func _update_cabinet() -> void:
	var t := clock - door_at
	if door_open:
		door = door_from + (1.0 - door_from) * out_back(t / DOOR_FRAMES)
	else:
		door = door_from * (1.0 - smooth(t / 30.0))
	if door_l:
		door_l.rotation.y = -DOOR_ANGLE * door
		door_r.rotation.y = DOOR_ANGLE * door
	cabinet_light.light_energy = CAB_LIGHT * clampf(door, 0.0, 1.0)


func toggle_cabinet() -> void:
	door_from = door
	door_open = not door_open
	door_at = clock


## take a prop off the shelf/bench: hide it in the room, fly its icon to the inventory.
## item_id names res://items/<item_id>.tres. Nothing happens while the bar is full.
func pick_up(group: String, item_id: String) -> void:
	if not ui.has_room():
		return
	var from := group_screen_pt(group)
	groups[group].visible = false
	ui.fly(InventoryManager.get_item(item_id), from, clock)
	GameState.set_flag("took_" + item_id)


## a held item clicked on something in the room; false = nothing happens, it goes back.
## An item the use consumes should leave with InventoryManager.remove_item(item).
func use_item(item: ItemData, group: String) -> bool:
	return false


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_seen = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			click()
		else:
			ui.release_click(cursor)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if ui.debug_open:
			ui.debug_open = false
		elif ui.held != null:
			ui.held = null
		else:
			back(false)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		ui.wheel(event.button_index == MOUSE_BUTTON_WHEEL_UP, cursor)
	elif event is InputEventKey and event.pressed and not event.echo:
		if ui.debug_open:
			var n := _digit(event.keycode)
			if n >= 0:
				run_debug((n + 9) % 10)          # keys 1..9 then 0
			elif event.keycode in [KEY_ESCAPE, KEY_F9]:
				ui.debug_open = false
			return
		match event.keycode:
			KEY_ESCAPE:                      # leave whatever is open, all the way back to the room
				ui.held = null
				back(true)
			KEY_F9:
				ui.debug_open = DEBUG_MENU
			KEY_MINUS, KEY_KP_SUBTRACT:
				if ui.panel == "fiche":
					ui.fiche.zoom_by(-1, cursor)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				if ui.panel == "fiche":
					ui.fiche.zoom_by(1, cursor)


## Esc / right-click / BACK: close the panel, or leave the close-up view. Right-click (full = false)
## only steps back one level, e.g. out of a zoomed microfiche; Esc always leaves it entirely.
func back(full := true) -> void:
	if ui.panel == "fiche" and not full and ui.fiche.zoomed():
		ui.fiche.leave_detail()
	elif ui.panel != "":
		ui.close_panel()
	else:
		for v in views:
			v.exit(clock)


func _digit(code: int) -> int:
	if code >= KEY_0 and code <= KEY_9:
		return code - KEY_0
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return code - KEY_KP_0
	return -1


# ---------------------------------------------------------------- debug menu (F9)
## [key, label, action]; the menu lists them in this order and keys 1..9, 0 run them
func debug_commands() -> Array:
	return [
		["1", "CONTACT NEXT STATION", _dbg_contact_next],
		["2", "CONTACT ALL STATIONS", _dbg_contact_all],
		["3", "REVEAL THE WHOLE MAP", func(): GameState.reveal(0, 0, 400); ui.debug_say("WHOLE MAP REVEALED")],
		["4", "RESET THE MAP", func(): GameState.reset_map(); ui.debug_say("MAP RESET")],
		["5", "GIVE ALL ITEMS", _dbg_give_all],
		["6", "CLEAR INVENTORY", _dbg_clear_inventory],
		["7", "OPEN / CLOSE SHUTTERS", func(): toggle_shutters(); ui.debug_say("SHUTTERS")],
		["8", "OPEN / CLOSE CABINET", func(): toggle_cabinet(); ui.debug_say("CABINET")],
		["9", "NEXT DAY", func(): GameState.day += 1; ui.debug_say("DAY %d" % GameState.day)],
		["0", "CLOSE THIS MENU", func(): ui.debug_open = false],
	]


func debug_status() -> String:
	return "DAY %d   STATIONS %d/%d   ITEMS %d/%d" % [GameState.day, GameState.contacted.size(),
			GameState.stations.size(), InventoryManager.inventory.items.size(), InventoryManager.MAX_ITEMS]


func run_debug(i: int) -> void:
	var cmds := debug_commands()
	if i >= 0 and i < cmds.size():
		cmds[i][2].call()


func _dbg_contact_next() -> void:
	for id in GameState.stations:
		if not GameState.is_contacted(id):
			GameState.contact_station(id)
			ui.debug_say("CONTACTED " + GameState.stations[id].callsign)
			return
	ui.debug_say("EVERY STATION IS CONTACTED")


func _dbg_contact_all() -> void:
	for id in GameState.stations:
		GameState.contact_station(id)
	ui.debug_say("ALL %d STATIONS CONTACTED" % GameState.stations.size())


func _dbg_give_all() -> void:
	for f in DirAccess.get_files_at(InventoryManager.ITEM_DIR):
		if f.ends_with(".tres") or f.ends_with(".tres.remap"):
			var item: ItemData = InventoryManager.get_item(f.get_basename().trim_suffix(".tres"))
			if item and not InventoryManager.has_item(item):
				InventoryManager.add_item(item)
	ui.debug_say("INVENTORY FULL")


func _dbg_clear_inventory() -> void:
	ui.held = null
	for item in InventoryManager.inventory.items.duplicate():
		InventoryManager.remove_item(item)
	ui.debug_say("INVENTORY EMPTY")


## the close-up view that owns the screen (moving or settled), or null for the room
func active_view() -> Node:
	for v in views:                      # one being opened wins over one still easing out
		if v.open:
			return v
	for v in views:
		if v.active():
			return v
	return null


## which way the real mouse has left the game window (-1 / 0 / +1 per axis). The game cursor is
## clamped to the screen, so this is how pans keep going at full speed past the window's edge.
## The web build can't ask where the mouse is, so it uses the edge the pointer left the page by.
func _mouse_outside() -> Vector2:
	if cursor_override != null or not mouse_seen:
		return Vector2.ZERO
	if beyond != Vector2.ZERO:           # still in the window, but past the game area (black borders)
		return beyond
	if OS.has_feature("web"):
		return web_out
	if not get_window().has_focus():
		return Vector2.ZERO
	var w := get_window()
	var p := Vector2(DisplayServer.mouse_get_position() - w.position)
	var out := Vector2.ZERO
	out.x = -1.0 if p.x < 0 else (1.0 if p.x >= w.size.x else 0.0)
	out.y = -1.0 if p.y < 0 else (1.0 if p.y >= w.size.y else 0.0)
	return out


## Browsers stop reporting the mouse once it leaves the page, so listen for the page's own
## mouseleave / mouseenter and remember the edge it left by (the nearest one to where it went out).
func _watch_web_mouse() -> void:
	var root = JavaScriptBridge.get_interface("document").documentElement
	var leave := JavaScriptBridge.create_callback(_on_web_mouse_leave)
	var enter := JavaScriptBridge.create_callback(func(_args): web_out = Vector2.ZERO)
	root.addEventListener("mouseleave", leave)
	root.addEventListener("mouseenter", enter)
	_web_callbacks = [leave, enter]


func _on_web_mouse_leave(args: Array) -> void:
	var e = args[0]
	var win = JavaScriptBridge.get_interface("window")
	var x: float = e.clientX
	var y: float = e.clientY
	var w: float = win.innerWidth
	var h: float = win.innerHeight
	var dist := [x, w - 1.0 - x, y, h - 1.0 - y]      # to the left, right, top and bottom edges
	var near: float = minf(minf(dist[0], dist[1]), minf(dist[2], dist[3])) + 16.0
	web_out = Vector2((-1.0 if dist[0] <= near and dist[0] <= dist[1] else (1.0 if dist[1] <= near else 0.0)),
			(-1.0 if dist[2] <= near and dist[2] <= dist[3] else (1.0 if dist[3] <= near else 0.0)))


## WASD / arrows as a direction, for panning inside panels
func _pan_keys() -> Vector2:
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		k.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		k.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		k.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		k.y += 1
	return k


func click() -> void:
	click_at = clock
	ui.ripple(cursor, clock)
	if ui.handle_click(cursor):
		return
	if active_view() != null:
		active_view().click(cursor, ui.held)   # the view's listeners decide what a click does
		return
	if ui.held != null:
		var item: ItemData = ui.held
		ui.held = null                   # back to its slot unless the use consumes it
		if hover != "":
			use_item(item, hover)
		return
	match hover:
		"shutters", "sky":
			toggle_shutters()
		"microfiche":
			ui.open_panel("fiche", clock)
			GameState.set_flag("fiche_seen")
		"radio":
			radio_view.enter(clock)
		"cabinet":
			toggle_cabinet()
		"jar":
			pick_up("jar", "jar")
		"papers":
			pick_up("papers", "papers")
		"bench":
			crafting.enter(clock)


## cursor inside the edge band pushes the view, harder the closer it gets; A/D push fully
func _update_push() -> void:
	push = 0.0
	if active_view() != null or ui.panel != "":
		edge_hold = true
		return
	if edge_hold and cursor.x >= EDGE and cursor.x <= W - 1 - EDGE:
		edge_hold = false
	var live: bool = cursor_override != null or (mouse_seen and get_window().has_focus())
	var out := _mouse_outside()
	if live and ui.panel == "" and not edge_hold and out.x != 0.0:
		push = out.x                     # the mouse has left the window on that side: full speed
	elif live and ui.panel == "" and not edge_hold:
		if cursor.x < EDGE:
			push = -pow((EDGE - cursor.x) / EDGE, 1.5)
		elif cursor.x > W - 1 - EDGE:
			push = pow((cursor.x - (W - 1 - EDGE)) / EDGE, 1.5)
	if ui.panel == "":
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			push = -1.0
		elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			push = 1.0
	if (push < 0.0 and cam_x <= CAM_MIN) or (push > 0.0 and cam_x >= CAM_MAX):
		push = 0.0                       # already against the wall


func panning() -> bool:
	return absf(cam_v) > 0.05


func clicking() -> bool:
	return clock - click_at < 4.0


# ---------------------------------------------------------------- helpers
static func smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func out_back(t: float, s := 1.2) -> float:
	t = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (s + 1.0) * t * t * t + s * t * t


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func group_screen_pt(name: String) -> Vector2:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in groups[name].find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return camera.unproject_position(box.get_center())


# ---------------------------------------------------------------- scripted demo (dev screenshots)
## godot --path . -- --demo <out_dir>: drives the cursor through the interactions,
## saves low-res screenshots, then quits.
func _start_demo_if_asked() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--demo")
	if i < 0:
		return
	var out := args[i + 1] if i + 1 < args.size() else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join(".gdignore"), FileAccess.WRITE)   # keep shots out of the import/export
	cursor_override = Vector2(W / 2.0, H / 2.0)  # the real mouse may sit on an edge and pan
	if args.has("--raw"):                       # plain lit render, for matching Blender's raw frames
		screen.material = null
		$UI.visible = false
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("raw.png"))
		mask_vp.get_texture().get_image().save_png(out.path_join("mask.png"))
		get_tree().quit()
		return
	_demo(out)


func _demo(out: String) -> void:
	var steps := [
		[20, "shot", "01_bench_view"],
		[21, "hover", "lantern"], [45, "shot", "02_hover_lantern"],
		[46, "hover", "speaker"], [70, "shot", "03_hover_speaker"],
		[71, "pan", "left"], [90, "shot", "03b_pushing_left"], [150, "shot", "04_window_view"],
		[151, "hover", "shutters"], [175, "shot", "05_hover_shutters"],
		[176, "click"], [200, "shot", "06_shutters_opening"], [320, "shot", "07_heat"],
		[321, "hover", "sky", Vector2(40, -14)], [330, "shot", "07b_hover_open_window"], [331, "click"], [460, "shot", "08_closed_again"],
		[461, "pan", "right"], [485, "shot", "08b_pushing_right"], [540, "hover", "microfiche"], [560, "shot", "09_hover_fiche"],
		[561, "click"], [575, "shot", "10_fiche_blank"],
		[576, "contact", ["kl7_anchorage", "du1_manila", "5n_lagos", "cx_montevideo"]],
		[577, "fiche_center", Vector2(57.0, -142.0)], [580, "shot", "10b_fiche_marks"],
		[581, "fiche_mark", "kl7_anchorage"], [590, "shot", "10c_fiche_note"],
		[591, "fiche_click", "kl7_anchorage"], [594, "shot", "10d_fiche_zoomed"],
		[595, "point", Vector2(447, 130)], [603, "shot", "10e_fiche_zoomed_panning"],
		[604, "close_box"], [608, "shot", "11_fiche_close_hover"], [609, "click"], [620, "shot", "12_back"],
		[621, "hover", "cabinet", Vector2(0, -20)], [640, "shot", "13_hover_cabinet"], [641, "click"],
		[700, "shot", "14_cabinet_open"],
		[701, "hover", "jar"], [720, "shot", "15_hover_jar"], [721, "click"], [728, "shot", "16_jar_flying"],
		[745, "hover", "papers"], [765, "shot", "17_hover_papers"], [766, "click"],
		[800, "point", Vector2(196, 255)], [815, "shot", "18_hover_slot"], [816, "click"],
		[817, "hover", "bench", Vector2(0, 20)], [840, "shot", "19_holding_over_bench"], [841, "click"],
		[860, "point", Vector2(218, 255)], [870, "shot", "20_back_in_inventory"],
		[871, "hover", "bench", Vector2(0, 20)], [880, "shot", "21_hover_bench"], [881, "click"],
		[895, "shot", "22_craft_swing"], [920, "shot", "23_craft_view"],
		[921, "cell", Vector2i(4, 2)], [935, "shot", "24_craft_hover_cell"],
		[936, "point", Vector2(20, 12)], [945, "shot", "25_craft_hover_back"], [946, "click"],
		[960, "shot", "26_craft_leaving"], [985, "shot", "27_back_in_room"],
		[986, "radio"], [995, "shot", "28_hover_radio"], [996, "click"],
		[1010, "shot", "29_radio_swing"], [1035, "shot", "30_radio_view"],
		[1036, "point", Vector2(20, 12)], [1040, "click"], [1075, "shot", "31_back_from_radio"],
		[1076, "debug"], [1085, "shot", "32_debug_menu"],
		[1086, "quit"],
	]
	for s in steps:
		while clock < s[0]:
			await get_tree().process_frame
		match s[1]:
			"shot":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out.path_join(s[2] + ".png"))
			"hover":
				cursor_override = group_screen_pt(s[2]) + (s[3] if s.size() > 3 else Vector2.ZERO)
			"point":
				cursor_override = s[2]
			"close_box":
				cursor_override = ui.close_box_center()
			"radio":                     # the radio's front panel (its group centre is up the coax)
				var f: Array = meta.points.radio_front
				cursor_override = camera.unproject_position(Vector3(f[0], f[1], f[2]))
			"contact":
				for id in s[2]:
					GameState.contact_station(id)
			"fiche_center":
				ui.fiche.center_on(s[2].x, s[2].y)
			"fiche_click":               # click (press + release) inside a station's revealed patch
				var sc: Dictionary = GameState.stations[s[2]]
				cursor_override = ui.fiche.screen_px(sc.lat - 1.5, sc.lon + 1.5)
				cursor = cursor_override
				click()
				ui.release_click(cursor_override)
			"debug":
				ui.debug_open = true
				cursor_override = Vector2(240, 80)
			"fiche_mark":
				var st: Dictionary = GameState.stations[s[2]]
				cursor_override = ui.fiche.screen_px(st.lat, st.lon)
			"cell":                      # middle of a crafting grid cell
				cursor_override = Vector2(crafting.cell_rect(s[2]).get_center())
			"pan":                       # park the cursor on that edge and let it push
				cursor_override = Vector2(1.0 if s[2] == "left" else W - 2.0, H / 2.0)
			"click":
				click()
			"quit":
				get_tree().quit()
