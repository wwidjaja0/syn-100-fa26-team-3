extends Node
## The pendant lamp, its wall switch, and the short sleep / waking transition.

const FADE_DELAY_FRAMES := 10.0
const FADE_OUT_FRAMES := 16.0
const BLACK_HOLD_FRAMES := 22.0
const EYES_OPEN_FRAMES := 42.0

var active := false
var lamp_on := true

var _main: Node
var _materials: Node
var _lamp_light: OmniLight3D
var _lamp_energy := 0.0
var _bulb_energy := 15.0
var _started_at := -1e9
var _day_advanced := false
var _rocker: MeshInstance3D
var _rocker_base_y := 1.62


## Reuse the old lantern picker's mask id for only the new wall switch. The imported pendant stays
## outside the group so its bright bulb does not receive the picker's animated hover shimmer.
func build(main: Node, room: Node3D, meta: Dictionary) -> void:
	_main = main
	var index: int = meta.groups.find("lantern")
	if index >= 0:
		meta.groups[index] = "light_switch"

	var group := Node3D.new()
	group.name = "grp_light_switch"
	room.add_child(group)

	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.22, 0.30, 0.045)
	var plate := MeshInstance3D.new()
	plate.name = "light_switch_plate"
	plate_mesh.material = _switch_material("light_switch_plate", Color(0.10, 0.07, 0.045))
	plate.mesh = plate_mesh
	plate.position = Vector3(2.08, 1.62, -1.91)
	group.add_child(plate)

	var rocker_mesh := BoxMesh.new()
	rocker_mesh.size = Vector3(0.09, 0.16, 0.075)
	rocker_mesh.material = _switch_material("light_switch_rocker", Color(0.95, 0.58, 0.16))
	_rocker = MeshInstance3D.new()
	_rocker.name = "light_switch_rocker"
	_rocker.mesh = rocker_mesh
	_rocker.position = Vector3(2.08, _rocker_base_y, -1.84)
	group.add_child(_rocker)
	_update_switch_visual()


func setup_lighting(materials: Node, lights: Node3D) -> void:
	_materials = materials
	_lamp_light = lights.get_node_or_null("pendant_key") as OmniLight3D
	if _lamp_light:
		_lamp_energy = _lamp_light.light_energy
	_bulb_energy = float(_main.meta.materials.get("pendant_bulb_emit", {}).get("strength", 15.0))


func toggle_lamp() -> void:
	if active:
		return
	set_lamp(not lamp_on)
	UiSounds.play("click")


func start_sleep() -> void:
	if active:
		return
	active = true
	_started_at = _main.clock
	_day_advanced = false
	set_lamp(false)
	UiSounds.play("click")


func set_lamp(on: bool) -> void:
	lamp_on = on
	if _lamp_light:
		_lamp_light.light_energy = _lamp_energy if on else 0.0
	if _materials:
		_materials.set_param("pendant_bulb_emit", "emission_energy", _bulb_energy if on else 0.0)
	if _main.ambience:
		_main.ambience.set_lantern(on)
	_update_switch_visual()


func update() -> void:
	var elapsed: float = _main.clock - _started_at
	if not active:
		return

	var black_at := FADE_DELAY_FRAMES + FADE_OUT_FRAMES
	var wake_at := black_at + BLACK_HOLD_FRAMES
	if not _day_advanced and elapsed >= black_at + BLACK_HOLD_FRAMES * 0.5:
		_day_advanced = true
		GameState.start_next_day()
		set_lamp(true)
	if elapsed >= wake_at + EYES_OPEN_FRAMES:
		active = false
		_main.room_camera.hold_edge()
		_main.ui.dialogue.start_entry({
			"style": "monologue",
			"speaker": "INTERNAL MONOLOGUE",
			"title": "DAY %d" % GameState.day,
			"repeatable": true,
			"lines": ["A NEW DAY. I FEEL RESTED ENOUGH TO GET BACK TO WORK."],
		}, "day_%d_started" % GameState.day)


## Draw over the entire UI so sleep really reaches full black. Waking opens from a narrow,
## curved slit toward the edges, like eyelids rather than a plain cross-fade.
func draw(overlay: Control) -> void:
	if not active:
		return
	var elapsed: float = _main.clock - _started_at
	if elapsed < FADE_DELAY_FRAMES:
		return
	if elapsed < FADE_DELAY_FRAMES + FADE_OUT_FRAMES:
		var alpha := smoothstep(0.0, 1.0, (elapsed - FADE_DELAY_FRAMES) / FADE_OUT_FRAMES)
		overlay.draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, alpha))
		return
	var wake_at := FADE_DELAY_FRAMES + FADE_OUT_FRAMES + BLACK_HOLD_FRAMES
	if elapsed < wake_at:
		overlay.draw_rect(Rect2(0, 0, 480, 270), Color.BLACK)
		return

	var opened := smoothstep(0.0, 1.0, (elapsed - wake_at) / EYES_OPEN_FRAMES)
	var columns := 24
	var width := 480.0 / columns
	for i in columns:
		var from_centre := absf((i + 0.5) / columns * 2.0 - 1.0)
		var local_open := clampf(opened * 1.3 - from_centre * 0.25, 0.0, 1.0)
		var lid_h := ceilf(135.0 * (1.0 - smoothstep(0.0, 1.0, local_open)))
		var x := floorf(i * width)
		overlay.draw_rect(Rect2(x, 0, ceilf(width) + 1.0, lid_h), Color.BLACK)
		overlay.draw_rect(Rect2(x, 270.0 - lid_h, ceilf(width) + 1.0, lid_h), Color.BLACK)


func _update_switch_visual() -> void:
	if _rocker:
		_rocker.rotation.x = deg_to_rad(-24.0 if lamp_on else 24.0)
		_rocker.position.y = _rocker_base_y + (0.035 if lamp_on else -0.035)


static func _switch_material(name: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_color = color
	material.roughness = 0.9
	return material
