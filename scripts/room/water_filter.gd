extends Node
## The bucket water filter under the window, and the jug it fills.
##
## It stands beside the hole in the wall (room/leak.gd). Its intake hose starts coiled on the floor
## ("intake_idle_*" parts). Once the sandbag is in the hole, clicking the filter runs the intake out
## through the hole in the bag's place ("intake_hole_*" parts, sealed with a rubber boot and rags) and
## the bag goes back up on the pile (flag "filter_installed").
##
## It only runs while the shutters are open (the sealed top bucket needs the window's air to drain)
## and it is raining outside (weather.gd's rain). Then it drips ("filter_drip") into the water jug on the
## floor beside it (the "jug" group), whose level shows through its side ("jug_water"). Clicking the
## full jug gives the player CLEAN WATER (items/water_jug.tres); the jug is gone from the floor until it
## comes back empty (return_jug(): tank/tank_water.gd, when the water goes into the reef tank).

const MIN_RAIN := 0.05                  # less rain than this and there is nothing to draw
const OPEN_ENOUGH := 0.6                # shutters.value at which the window counts as open
const FILL_SECONDS := 60.0              # filling the jug in a downpour (rain 1); slower in lighter rain
const DRIP_FRAMES := 6.0                # a drop falls from the tap this often while it runs
## the filter stands in the window wall's shadow, so a little cool light picks it out (made in setup)
const FILL_COLOR := Color(0.55, 0.75, 1.0)
const FILL_ENERGY := 1.2
const FILL_RANGE := 1.6                 # m

var fill := 0.0                         # the jug, 0 empty .. 1 full
var jug_here := true                    # false while the player has it

var _main: Node
var _idle: Array[Node3D] = []
var _hole: Array[Node3D] = []
var _drip: Node3D
var _water: Node3D                      # the jug's level, scaled up from the jug's floor
var _water_tf: Transform3D
var _water_floor := 0.0                 # y of the bottom of the jug's water


func setup(main: Node, room: Node3D) -> void:
	_main = main
	for n: Node3D in room.find_children("intake_idle_*", "MeshInstance3D", true, false):
		_idle.append(n)
	for n: Node3D in room.find_children("intake_hole_*", "MeshInstance3D", true, false):
		_hole.append(n)
	_drip = room.find_child("filter_drip_*", true, false) as Node3D
	var water := room.find_child("jug_water_*", true, false) as MeshInstance3D
	if water:
		_water = water
		_water_tf = water.global_transform
		_water_floor = (water.global_transform * water.get_aabb()).position.y
	var body := room.find_child("raw_bucket_*", true, false) as MeshInstance3D
	if body:
		var fill_light := OmniLight3D.new()
		fill_light.name = "filter_fill"
		fill_light.light_color = FILL_COLOR
		fill_light.light_energy = FILL_ENERGY
		fill_light.omni_range = FILL_RANGE
		fill_light.omni_attenuation = 1.5
		main.get_node("WorldVP/Lights").add_child(fill_light)
		fill_light.global_position = body.global_transform * body.get_aabb().get_center() + Vector3(0.0, 0.1, 0.9)


func installed() -> bool:
	return GameState.flag("filter_installed")


## why it isn't running ("" when it is): what the hover label and the monologues go by
func blocked() -> String:
	if not installed():
		return "no intake"
	if _main.shutters.value < OPEN_ENOUGH or not _main.shutters.is_open:
		return "shutters shut"
	if _main.weather.rain() < MIN_RAIN:
		return "no rain"
	return ""


func running() -> bool:
	return blocked() == ""


## the filter's hover label
func label() -> String:
	match blocked():
		"no intake":
			return "WATER FILTER"
		"shutters shut":
			return "WATER FILTER (NEEDS AIR)"
		"no rain":
			return "WATER FILTER (DRY)"
	return "WATER FILTER (RUNNING)"


## the jug's hover label
func jug_label() -> String:
	if fill >= 1.0:
		return "CLEAN WATER (FULL)"
	if fill < 0.01:
		return "WATER JUG (EMPTY)"
	return "WATER JUG (%d%%)" % int(fill * 100.0)


## a click on the filter with nothing in hand (room/interactions.gd)
func click() -> void:
	var leak = _main.leak
	if installed():
		_main.interactions.say("filter_" + blocked().replace(" ", "_") if not running() else "filter_running")
		return
	if leak.leaking():
		_main.interactions.say("filter_hole_open")
		return
	GameState.set_flag("filter_installed")
	leak.make_way()
	UiSounds.play("pick")
	_main.interactions.say("filter_installed")


## a click on the jug: full, it goes into the inventory; otherwise a thought on why it isn't
func click_jug() -> void:
	if fill < 1.0:
		_main.interactions.say("jug_filling" if installed() else "jug_empty")
		return
	if not _main.ui.inventory.has_room():
		return
	_main.interactions.pick_up("jug", "water_jug")
	jug_here = false
	fill = 0.0


## the empty jug is back on the floor under the tap (the water went into the tank)
func return_jug() -> void:
	jug_here = true
	fill = 0.0
	_main.picker.groups["jug"].visible = true


## per frame, from main.gd. delta in seconds.
func update(delta: float) -> void:
	var on := installed()
	for n in _idle:
		n.visible = not on
	for n in _hole:
		n.visible = on
	var dripping := running() and jug_here and fill < 1.0
	if dripping:
		fill = minf(fill + _main.weather.rain() * delta / FILL_SECONDS, 1.0)
	if _drip:
		_drip.visible = dripping and fmod(_main.clock, DRIP_FRAMES) < DRIP_FRAMES * 0.5
	if _water:
		_water.visible = fill > 0.02
		# scale the level up from the jug's floor (a scale about the plane y = _water_floor)
		var k := maxf(fill, 0.02)
		_water.global_transform = Transform3D(Basis.from_scale(Vector3(1.0, k, 1.0)), Vector3(0.0, _water_floor * (1.0 - k), 0.0)) * _water_tf
