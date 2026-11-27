extends Node
## The hole under the window, the sandbag that belongs in it, and the water that gets in without it.
##
## A hole is knocked through the wall low under the window, behind the left end of the sandbag pile's
## second row (pipeline/scene/build_pixel_scene.py's "wall_hole"). That row's left bag (its parts are
## "loose_bag_*") was built sitting in it, but the game starts with the bag thrown up on top of the
## pile, so the storm runs in: water spills out of the hole, down between the bottom row's bags, and
## spreads over the floor. Clicking
## the sandbags drops the bag back into the hole (flag "hole_plugged"). Later the water filter's intake
## can go out through the hole in its place (room/water_filter.gd calls make_way(), and the bag goes
## back up on top; flag "filter_installed"). Either one seals the hole.
##
## The puddle grows while the hole is open and it is raining outside (room/weather.gd's rain), and
## dries slowly once the hole is sealed. Timings in seconds unless named in frames (24 fps clock).

const Ease := preload("res://scripts/room/ease.gd")
const MOVE_FRAMES := 20.0               # the bag's hop between the pile top and the hole
## where the bag sits on top of the pile, from its spot in the hole (Godot: x right, y up, z toward
## the camera), and how it lies there: tipped and turned a little, as if thrown
const TOP_OFFSET := Vector3(0.94, 0.38, 0.03)
const TOP_ROTATION := Vector3(0.05, 0.22, -0.10)
const FILL_SECONDS := 100.0             # a downpour (rain 1) spreads the puddle from nothing to full
const DRY_SECONDS := 300.0              # a sealed hole's full puddle takes this long to dry
const START_LEVEL := 0.4                # it has been coming in for a while when the game starts
const MIN_SCALE := 0.25                 # the puddle's size at the smallest level that still shows
const STREAM_FRAMES := 5.0              # the stream's two shapes swap this often

var level := START_LEVEL                # the puddle, 0 (dry) .. 1 (full size)

var _main: Node
var _bag: Node3D                        # a pivot made at the bag's centre, its parts under it
var _home: Transform3D                  # the pivot in the hole (global)
var _move_from := 0.0                   # 0 in the hole .. 1 on top; the hop animates between
var _move_to := 1.0
var _moved_at := -1e9
var _puddle: Array[Node3D] = []
var _streams: Array = []                # the stream's two shapes, each a list of parts


func setup(main: Node, room: Node3D) -> void:
	_main = main
	var parts := room.find_children("loose_bag_*", "MeshInstance3D", true, false)
	if not parts.is_empty():
		var box := AABB()
		for i in parts.size():
			var mi: MeshInstance3D = parts[i]
			var b := mi.global_transform * mi.get_aabb()
			box = b if i == 0 else box.merge(b)
		_bag = Node3D.new()
		_bag.name = "loose_bag_pivot"
		parts[0].get_parent().add_child(_bag)
		_bag.global_position = box.get_center()
		_home = _bag.global_transform
		for mi: Node3D in parts:
			mi.reparent(_bag, true)
	for n in ["leak_puddle", "leak_puddle_sheen"]:
		var p := room.find_child(n, true, false) as Node3D
		if p:
			_puddle.append(p)
	for n in ["leak_stream_a_*", "leak_stream_b_*"]:
		_streams.append(room.find_children(n, "MeshInstance3D", true, false))
	reset()


## back to how a new game starts: the bag on top of the pile, the puddle part-spread
func reset() -> void:
	level = START_LEVEL
	var up := 0.0 if GameState.flag("hole_plugged") and not GameState.flag("filter_installed") else 1.0
	_move_from = up
	_move_to = up
	_moved_at = -1e9


## what fills the hole: "open" (nothing, water runs in), "bag" or "filter"
func state() -> String:
	if GameState.flag("filter_installed"):
		return "filter"
	return "bag" if GameState.flag("hole_plugged") else "open"


func leaking() -> bool:
	return state() == "open"


## the player clicked the sandbags with the hole open: drop the bag into it
func plug() -> void:
	if not leaking():
		return
	GameState.set_flag("hole_plugged")
	_hop(0.0)
	UiSounds.play("pick")


## the filter's intake is going through the hole: the bag goes back up on top of the pile
func make_way() -> void:
	_hop(1.0)


func _hop(to: float) -> void:
	_move_from = _bag_pose()
	_move_to = to
	_moved_at = _main.clock


## 0 in the hole .. 1 on top, now
func _bag_pose() -> float:
	var k := clampf((_main.clock - _moved_at) / MOVE_FRAMES, 0.0, 1.0)
	return lerpf(_move_from, _move_to, Ease.smooth(k))


## per frame, from main.gd. delta in seconds.
func update(delta: float) -> void:
	var rain: float = _main.weather.rain()
	if leaking():
		level = minf(level + rain * delta / FILL_SECONDS, 1.0)
	else:
		level = maxf(level - delta / DRY_SECONDS, 0.0)
	var s := lerpf(MIN_SCALE, 1.0, sqrt(level))
	for p in _puddle:
		p.visible = level > 0.02
		p.scale = Vector3(s, 1.0, s)
	var flowing := leaking() and rain > 0.05
	var frame := int(_main.clock / STREAM_FRAMES) % 2
	for i in _streams.size():
		for p: Node3D in _streams[i]:
			p.visible = flowing and i == frame
	if _bag:
		var t := _bag_pose()
		var k := clampf((_main.clock - _moved_at) / MOVE_FRAMES, 0.0, 1.0)
		var arc := 0.18 * sin(PI * k) if k < 1.0 else 0.0    # a little lift through the hop
		var tf := _home
		tf.origin += TOP_OFFSET * t + Vector3(0, arc, 0)
		tf.basis = _home.basis * Basis.from_euler(TOP_ROTATION * t)
		_bag.global_transform = tf
