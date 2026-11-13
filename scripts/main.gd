extends Node
## Main: the root of scenes/main.tscn, the game's only scene.
##
## It builds the parts below as child nodes, runs them in a fixed order every frame, and routes
## mouse and keyboard input. Each part is its own script; docs/ARCHITECTURE.md explains how they
## fit together.
##
##   room/room_materials.gd   swaps the room's imported materials for the toon shader
##   room/object_picker.gd    which object is under the cursor (reads the mask render)
##   room/interactions.gd     hover labels and what clicking each object does   <- game rules
##   room/shutters.gd         storm shutters and the heat they let in
##   room/cabinet.gd          supply cabinet doors and interior light
##   room/ambience.gd         storm sky, PA light, lantern glow
##   room/placeholders.gd     stand-in boxes for props not modelled yet (the battery)
##   room/room_camera.gd      panning, pixel snapping, hand-over to close-ups
##   room/post_process.gd     feeds the post shader
##   views/crafting_view.gd   close-up: straight down onto the workbench's cutting mat
##   views/radio_view.gd      close-up: the ham radio's front panel
##   crafting/crafting.gd     what lies on the cutting mat, the recipes, crafting   <- crafting rules
##   ui/overlay.gd            the pixel UI (its own node, UI/Overlay)
##   ui/start_menu.gd         the title screen (its own node, UI/StartMenu); calls start_game()
##   ui/pause_menu.gd         the pause / settings menu (its own node, UI/PauseMenu)
##   dev/debug_menu.gd        the F9 menu
##   dev/demo.gd              the scripted screenshot walkthrough (--demo)
##
## Time is counted in "frames" of a 24 fps clock (`clock`), the frame rate of the story video the
## game grew out of, so animation timings carry over from pipeline/scene/build_story.py.

const W := 480                          # the game's canvas, before the integer upscale
const H := 270
const TICK := 24.0                      # clock frames per second

const RoomMaterials := preload("res://scripts/room/room_materials.gd")
const ObjectPicker := preload("res://scripts/room/object_picker.gd")
const Interactions := preload("res://scripts/room/interactions.gd")
const Shutters := preload("res://scripts/room/shutters.gd")
const Cabinet := preload("res://scripts/room/cabinet.gd")
const Ambience := preload("res://scripts/room/ambience.gd")
const RoomCamera := preload("res://scripts/room/room_camera.gd")
const PostProcess := preload("res://scripts/room/post_process.gd")
const CraftingView := preload("res://scripts/views/crafting_view.gd")
const RadioView := preload("res://scripts/views/radio_view.gd")
const Crafting := preload("res://scripts/crafting/crafting.gd")
const Placeholders := preload("res://scripts/room/placeholders.gd")
const DebugMenu := preload("res://scripts/dev/debug_menu.gd")
const Demo := preload("res://scripts/dev/demo.gd")

@onready var world_vp: SubViewport = $WorldVP
@onready var mask_vp: SubViewport = $MaskVP
@onready var room: Node3D = $WorldVP/Room
@onready var camera: Camera3D = $WorldVP/Camera
@onready var mask_cam: Camera3D = $MaskVP/MaskCam
@onready var screen: TextureRect = $Screen
@onready var ui: Control = $UI/Overlay
@onready var pause_menu: Control = $UI/PauseMenu
@onready var start_menu: Control = $UI/StartMenu

## the room's description, written by pipeline/godot/export_glb.py: object groups, materials,
## lights, camera, and points of interest
var meta: Dictionary
## true on the Compatibility renderer (web build, OpenGL fallback), which handles colour differently
var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"

var clock := 0.0                        # 24 fps frames since the game started
var cursor := Vector2(W / 2.0, H / 2.0) # the mouse on the 480x270 canvas, clamped to it
var cursor_override = null              # a Vector2 while the demo drives the cursor
var beyond := Vector2.ZERO              # -1/0/+1 per axis: the pointer is past that edge of the game
										# area (e.g. in the black borders around the scaled picture)
var mouse_seen := false                 # no edge-panning until the mouse has really moved (the web
										# build starts with the pointer at 0,0)
var landing_active := true              # the title screen is up: ambience runs, gameplay input does not
var click_at := -1e9                    # clock of the last click (the cursor sinks in briefly)

# story & dialogue trigger tracking
var game_started_at := -1e9
var intro_triggered := false
var scanned_left := false
var scanned_right := false
var radio_hint_triggered := false
var suppress_auto_dialogue := false
var _radio_was_fixed := false

# the parts (see the list above)
var materials: RoomMaterials
var picker: ObjectPicker
var interactions: Interactions
var shutters: Shutters
var cabinet: Cabinet
var ambience: Ambience
var room_camera: RoomCamera
var post: PostProcess
var crafting: CraftingView
var radio_view: RadioView
var workbench: Crafting                 # the crafting rules (crafting is the camera view)
var views: Array[Node] = []             # every close-up view
var debug_menu: DebugMenu
var demo: Demo


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/scene_meta.json"))
	for n in meta.start_hidden:          # parts that appear later in the story (e.g. the radio's grill)
		var node := room.find_child(n, true, false)
		if node:
			node.visible = false
	Placeholders.add_all(room, meta)     # adds their groups to meta.groups, so before the picker

	interactions = Interactions.new()
	_add(interactions, "Interactions")
	interactions.setup(self)
	picker = ObjectPicker.new()
	_add(picker, "ObjectPicker")
	picker.setup(self, meta, room, mask_vp, camera)
	materials = RoomMaterials.new()
	_add(materials, "RoomMaterials")
	materials.setup(room, meta, picker.group_of, compat)
	shutters = Shutters.new()
	_add(shutters, "Shutters")
	shutters.setup(self, room)
	cabinet = Cabinet.new()
	_add(cabinet, "Cabinet")
	cabinet.setup(self, room, $WorldVP/Lights/cabinet_interior)
	ambience = Ambience.new()
	_add(ambience, "Ambience")
	ambience.setup(self, $WorldVP/Lights, materials, $WorldVP/Lights/lantern_glow, compat)
	crafting = CraftingView.new()
	_add(crafting, "CraftingView")
	crafting.setup(meta, W, H)
	radio_view = RadioView.new()
	_add(radio_view, "RadioView")
	radio_view.setup(meta, camera)
	radio_view.entered.connect(_on_radio_view_entered)
	views = [crafting, radio_view]
	workbench = Crafting.new()
	_add(workbench, "Workbench")
	workbench.setup(self)
	room_camera = RoomCamera.new()
	_add(room_camera, "RoomCamera")
	room_camera.setup(self, meta, room, camera, mask_cam)
	post = PostProcess.new()
	_add(post, "PostProcess")
	post.setup(self, meta, screen, world_vp, mask_vp)
	debug_menu = DebugMenu.new()
	_add(debug_menu, "DebugMenu")
	debug_menu.setup(self)
	demo = Demo.new()
	_add(demo, "Demo")

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN   # overlay.gd draws a pixel cursor instead
	demo.start_if_asked(self)


func _add(part: Node, name: String) -> void:
	part.name = name
	add_child(part)


func _process(delta: float) -> void:
	var step := delta * TICK
	clock += step
	_read_cursor()
	room_camera.update(delta)                     # pans; moves the close-up views; places the cameras
	if ui.panel == "fiche":
		ui.microfiche.update(cursor, delta, _pan_keys())
	shutters.update()
	cabinet.update()
	ui.dialogue.update(clock, step)
	_check_dialogue_triggers()
	interactions.update()
	var room_hover: bool = not landing_active and ui.panel == "" and not ui.over_ui(cursor) and not ui.inventory.flying() \
			and active_view() == null
	picker.update(cursor, step, room_hover)
	ambience.update()
	post.update()
	ui.queue_redraw()


func _read_cursor() -> void:
	var raw: Vector2 = cursor_override if cursor_override != null else ui.get_global_mouse_position()
	beyond = Vector2(-1.0 if raw.x < 0.0 else (1.0 if raw.x >= W else 0.0),
			-1.0 if raw.y < 0.0 else (1.0 if raw.y >= H else 0.0))
	cursor = raw.clamp(Vector2.ZERO, Vector2(W - 1, H - 1))


# ---------------------------------------------------------------- input
## Controls (also in the README):
##   left click         use the UI, else the close-up view, else the room object under the cursor
##   right click        drop the held item; else step back one level (out of a zoom, a panel, a close-up)
##   Esc                drop the held item and go straight back to the room; in the room, pause
##   mouse wheel, - / = zoom the microfiche
##   F9                 the debug menu
func _input(event: InputEvent) -> void:
	if not landing_active and event is InputEventMouseMotion:
		mouse_seen = true


func _unhandled_input(event: InputEvent) -> void:
	if landing_active:                   # start_menu.gd owns input until Start Game
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			click()
		else:
			ui.release_click(cursor)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if debug_menu.open:
			debug_menu.open = false
		elif ui.dialogue.is_active():
			ui.dialogue.close()
		elif ui.inventory.held != null:
			ui.inventory.held = null
			UiSounds.play("back")
		else:
			back(false)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		ui.wheel(event.button_index == MOUSE_BUTTON_WHEEL_UP, cursor)
	elif event is InputEventKey and event.pressed and not event.echo:
		if debug_menu.open:
			debug_menu.key(event.keycode)
			return
		if ui.dialogue.is_active():
			if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
				ui.dialogue.skip_or_advance()
				return
			elif event.keycode == KEY_ESCAPE:
				ui.dialogue.close()
				return
		match event.keycode:
			KEY_ESCAPE:
				if ui.inventory.held != null:
					UiSounds.play("back")
				ui.inventory.held = null
				if ui.panel != "" or active_view() != null:
					back(true)
				else:
					pause_menu.open_pause()
			KEY_F9:
				debug_menu.toggle()
			KEY_MINUS, KEY_KP_SUBTRACT:
				if ui.panel == "fiche":
					ui.microfiche.zoom_by(-1, cursor)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				if ui.panel == "fiche":
					ui.microfiche.zoom_by(1, cursor)


## Leave the title screen (called by start_menu.gd). The cabin behind it is already live, so
## nothing reloads: the UI appears and input starts reaching the game.
func start_game() -> void:
	landing_active = false
	game_started_at = clock
	ui.visible = true
	screen.material.set_shader_parameter("landing_amount", 0.0)
	mouse_seen = false
	room_camera.hold_edge()
	picker.hover = ""
	picker.hover_t = 0.0


func _on_radio_view_entered() -> void:
	if not GameState.flag("radio_fixed"):
		interactions.inspect_broken_radio()      # its monologue, then it's picked up


func _apply_radio_mesh_state(fixed: bool) -> void:
	for n in meta.start_hidden:
		var node := room.find_child(n, true, false)
		if node:
			node.visible = fixed
	for broken_part in ["radio_speaker_hole", "radio_wire_red", "radio_wire_yel"]:
		var node := room.find_child(broken_part, true, false)
		if node:
			node.visible = not fixed


func _check_dialogue_triggers() -> void:
	var radio_fixed := GameState.flag("radio_fixed")
	if radio_fixed != _radio_was_fixed:
		_radio_was_fixed = radio_fixed
		_apply_radio_mesh_state(radio_fixed)
		if radio_fixed:
			ui.dialogue.arm_radio_chatter(clock, true)
			if not landing_active and not suppress_auto_dialogue and not ui.dialogue.is_active():
				ui.dialogue.start("radio_repaired")

	if landing_active or suppress_auto_dialogue:
		return

	# 1. Intro dialogue shortly after starting
	if not intro_triggered and clock - game_started_at >= 12.0:
		intro_triggered = true
		ui.dialogue.start("intro_wake")

	# 2. Room scan tracking: visiting left wall and right wall
	if not radio_hint_triggered:
		if room_camera.x <= room_camera.CAM_MIN + 0.6:
			scanned_left = true
		if room_camera.x >= room_camera.CAM_MAX - 0.6:
			scanned_right = true

		var can_trigger_hint: bool = scanned_left and scanned_right and not ui.dialogue.is_active() \
				and ui.panel == "" and active_view() == null
		if can_trigger_hint:
			radio_hint_triggered = true
			if not GameState.flag("radio_fixed") and not GameState.flag("took_radio_broken"):
				ui.dialogue.start("hint_use_radio")


## a left click: the UI gets it first, then an open close-up view, then the room
func click() -> void:
	click_at = clock
	ui.ripple(cursor, clock)
	if ui.handle_click(cursor):
		return
	if active_view() != null:
		active_view().click(cursor, ui.inventory.held)   # the view's listeners decide what a click does
		return
	var held: ItemData = ui.inventory.held
	if held != null:
		ui.inventory.held = null                         # back to its slot unless the use consumes it
		if picker.hover != "":
			interactions.use_item(held, picker.hover)
		return
	interactions.click(picker.hover)


## Esc / right-click / BACK: close the panel, or leave the close-up view. Right-click (full = false)
## only steps back one level, e.g. out of a zoomed microfiche; Esc (full = true) closes it outright.
func back(full := true) -> void:
	if ui.dialogue.is_active():
		ui.dialogue.close()
	elif ui.panel == "fiche" and not full and ui.microfiche.zoomed():
		ui.microfiche.leave_detail()
		UiSounds.play("tick")
	elif ui.panel != "":
		ui.close_panel()
	else:
		for v in views:                  # silent: leaving a close-up is the room, not UI
			v.exit(clock)


## the close-up view that owns the screen (opening, open or closing), or null in the room
func active_view() -> Node:
	for v in views:                      # one being opened wins over one still easing out
		if v.open:
			return v
	for v in views:
		if v.active():
			return v
	return null


## true for a moment after a click (the cursor sinks in, the hover outline thickens)
func clicking() -> bool:
	return clock - click_at < 4.0


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
