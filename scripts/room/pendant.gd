extends Node
## The lamp hanging over the workbench, and its pull chain: lights out ends the day.
##
## Clicking the lamp (the "pendant" group: shade, bulb, cord and the pull chain) tugs the chain and
## the light goes out. The room sits dark a moment, fades to black, GameState.advance_day() moves the
## day on, a DAY card shows, and the morning fades back in with the lamp lit. What a new day changes
## is still to be decided (issue #36); for now only the day number in the top-left corner moves.
##
## Not while water is still running in under the window (room/leak.gd): that has to be dealt with
## first. While the night runs (busy()) the room takes no clicks. Timings are 24 fps frames.

const TUG_FRAMES := 8.0                 # the chain dips and springs back
const TUG_DEPTH := 0.035                # m
const DARK_AT := 4.0                    # frames after the click: the light goes out
const FADE_OUT_AT := 34.0               # the room fades to black...
const BLACK_AT := 58.0                  # ...is black: the day moves on, the card shows
const LIGHT_AT := 104.0                 # the lamp comes back on under the black
const FADE_IN_AT := 112.0               # the morning fades in...
const DONE_AT := 140.0                  # ...and the room is back

var _main: Node
var _materials: Node
var _key: OmniLight3D                   # the lamp's light
var _key_energy := 1.0
var _bulb_energy := 15.0
var _chain: Array[Node3D] = []          # the chain and its knob, with their resting heights
var _chain_y: Array[float] = []
var _pulled_at := -1e9
var _advanced := true


func setup(main: Node, lights: Node3D, materials: Node, room: Node3D) -> void:
	_main = main
	_materials = materials
	_key = lights.get_node_or_null("pendant_key") as OmniLight3D
	if _key:
		_key_energy = _key.light_energy
	var info: Dictionary = main.meta.materials.get("pendant_bulb_emit", {})
	_bulb_energy = info.get("strength", _bulb_energy)
	for n in ["pendant_pull_chain", "pendant_pull_knob"]:
		var node := room.find_child(n, true, false) as Node3D
		if node:
			_chain.append(node)
			_chain_y.append(node.position.y)


## the night is running: no clicks, no hover
func busy() -> bool:
	return _main.clock - _pulled_at < DONE_AT


## a click on the lamp
func pull() -> void:
	if busy():
		return
	if _main.leak.leaking():
		_main.interactions.say("bed_leaking")
		return
	_pulled_at = _main.clock
	_advanced = false
	UiSounds.play("tick")


## 0..1 how black the screen is (overlay.gd draws it over the room)
func blackout() -> float:
	var t: float = _main.clock - _pulled_at
	if t < FADE_OUT_AT or t >= DONE_AT:
		return 0.0
	if t < BLACK_AT:
		return (t - FADE_OUT_AT) / (BLACK_AT - FADE_OUT_AT)
	if t < FADE_IN_AT:
		return 1.0
	return 1.0 - (t - FADE_IN_AT) / (DONE_AT - FADE_IN_AT)


## 0..1 how strongly the DAY card shows (it fades with the black)
func card() -> float:
	var t: float = _main.clock - _pulled_at
	if t < BLACK_AT - 6.0 or t >= FADE_IN_AT + 10.0:
		return 0.0
	return minf(minf((t - (BLACK_AT - 6.0)) / 10.0, (FADE_IN_AT + 10.0 - t) / 10.0), 1.0)


func update() -> void:
	var t: float = _main.clock - _pulled_at
	if not _advanced and t >= BLACK_AT:
		_advanced = true
		GameState.advance_day()
	var lit := t < DARK_AT or t >= LIGHT_AT
	if _key:
		_key.light_energy = _key_energy if lit else 0.0
	_materials.set_param("pendant_bulb_emit", "emission_energy", _bulb_energy if lit else 0.0)
	var dip := TUG_DEPTH * sin(PI * clampf(t / TUG_FRAMES, 0.0, 1.0))
	for i in _chain.size():
		_chain[i].position.y = _chain_y[i] - dip
