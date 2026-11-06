extends Node
## The storm shutters over the window, and the heat they let in.
##
## Two hinged panels (the shutter_hinge_L / _R nodes, made in
## pipeline/scene/story_parts/story_3_rigs_and_camera.py) swing open with a little overshoot and close
## with a thud. While they are open, `heat` climbs, which the
## post shader turns into a shimmer around the window. `value` is the swing: 0 closed .. 1 open
## (it overshoots slightly). Timings are in 24 fps frames (main.gd's clock).

const Ease := preload("res://scripts/room/ease.gd")
const OPEN_ANGLE := deg_to_rad(100.0)   # stand out from the wall, clear of the microfiche display
const SWING_FRAMES := 48.0
const MAX_HEAT := 0.62                  # heat once the window has been open a while
const HEAT_RISE_FRAMES := 110.0
const HEAT_FALL_FRAMES := 90.0

var is_open := false
var value := 0.0                        # 0 closed .. 1 open
var heat := 0.0                         # 0 .. MAX_HEAT

var _main: Node
var _hinge_l: Node3D
var _hinge_r: Node3D
var _from := 0.0
var _at := -1e9
var _heat_from := 0.0
var _heat_at := -1e9


func setup(main: Node, room: Node3D) -> void:
	_main = main
	_hinge_l = room.find_child("shutter_hinge_L", true, false)
	_hinge_r = room.find_child("shutter_hinge_R", true, false)


func toggle() -> void:
	var now: float = _main.clock
	_from = value
	_heat_from = heat
	is_open = not is_open
	_at = now
	_heat_at = now
	if is_open:
		GameState.set_flag("window_opened")


func update() -> void:
	var now: float = _main.clock
	var t := now - _at
	if is_open:
		value = _from + (1.0 - _from) * Ease.out_back(t / SWING_FRAMES)
		heat = _heat_from + (MAX_HEAT - _heat_from) * Ease.smooth((now - _heat_at - 8.0) / HEAT_RISE_FRAMES)
	else:
		var k := clampf(t / SWING_FRAMES, 0.0, 1.0)
		value = _from * (1.0 - pow(k, 2.2))
		if t > SWING_FRAMES:                                  # thud: a small rebound against the frame
			var b := t - SWING_FRAMES
			value = 0.025 * exp(-b / 4.0) * absf(sin(b * 0.9)) * signf(_from)
		heat = _heat_from * (1.0 - Ease.smooth((now - _heat_at) / HEAT_FALL_FRAMES))
	if _hinge_l:
		_hinge_l.rotation.y = -OPEN_ANGLE * value
		_hinge_r.rotation.y = OPEN_ANGLE * value

