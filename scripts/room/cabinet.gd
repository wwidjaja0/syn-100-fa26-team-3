extends Node
## The supply cabinet: two hinged doors (cabinet_hinge_L / _R, made in
## pipeline/scene/story_parts/story_3_rigs_and_camera.py) and the warm light inside, which brightens
## as the doors open.
## `value` is the doors' swing: 0 closed .. 1 open. Timings are in 24 fps frames.

const Ease := preload("res://scripts/room/ease.gd")
const OPEN_ANGLE := deg_to_rad(105.0)
const OPEN_FRAMES := 36.0
const CLOSE_FRAMES := 30.0
const INTERIOR_LIGHT := 160.0 / (4.0 * PI * PI)   # Blender's 160 W glow, in Godot light energy

var is_open := false
var value := 0.0

var _main: Node
var _door_l: Node3D
var _door_r: Node3D
var _light: OmniLight3D
var _from := 0.0
var _at := -1e9


func setup(main: Node, room: Node3D, interior_light: OmniLight3D) -> void:
	_main = main
	_door_l = room.find_child("cabinet_hinge_L", true, false)
	_door_r = room.find_child("cabinet_hinge_R", true, false)
	_light = interior_light


func toggle() -> void:
	_from = value
	is_open = not is_open
	_at = _main.clock


func update() -> void:
	var t: float = _main.clock - _at
	if is_open:
		value = _from + (1.0 - _from) * Ease.out_back(t / OPEN_FRAMES)
	else:
		value = _from * (1.0 - Ease.smooth(t / CLOSE_FRAMES))
	if _door_l:
		_door_l.rotation.y = -OPEN_ANGLE * value
		_door_r.rotation.y = OPEN_ANGLE * value
	_light.light_energy = INTERIOR_LIGHT * clampf(value, 0.0, 1.0)
