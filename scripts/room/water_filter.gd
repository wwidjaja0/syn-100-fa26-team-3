extends Node
## The UV water purifier under the window, the rain catcher that feeds it, and the jerrycan it fills.
##
## A galvanised gutter hangs on the front of the window sill ("rain_catcher_*"). With the shutters
## open the storm blows in across the sill and runs off into it, down a pipe to the purifier: a
## sediment cartridge, an activated-carbon cartridge and a UV-C lamp ("uv_lamp", lit while it runs),
## powered from the power station. So it runs while the shutters are open and it is raining outside
## (weather.gd's rain), and drips ("filter_drip") into the jerrycan on the floor beside it (the "jug"
## group), whose level shows through its side ("jug_water").
##
## What comes out is near-pure water: rain is nature's distilled water, and the cartridges and the
## lamp take out what it picked up (grit, smoke, organics, anything living). Pure water has no salt
## and no buffer, so it doesn't fix a reef's pH by itself. Clicking the full jerrycan gives the player
## PURE WATER (items/pure_water.tres): poured into the tank it tops the water level back up
## (tank/tank_water.gd); with REEF SALT on the workbench it makes SALTWATER (crafting/crafting.gd). The
## jerrycan is gone from the floor until it comes back empty (return_jug()).

const MIN_RAIN := 0.05                  # less rain than this and the gutter stays dry
const OPEN_ENOUGH := 0.6                # shutters.value at which the window counts as open
const FILL_SECONDS := 80.0              # filling the 20 L jerrycan in a downpour (rain 1)
const DRIP_FRAMES := 6.0                # a drop falls from the tube this often while it runs
const LAMP_ENERGY := 3.0                # the UV window's glow while it runs
## the purifier stands in the window wall's shadow, so a little cool light picks it out
const FILL_COLOR := Color(0.55, 0.75, 1.0)
const FILL_ENERGY := 1.2
const FILL_RANGE := 1.6                 # m

var fill := 0.0                         # the jerrycan, 0 empty .. 1 full
var jug_here := true                    # false while the player has it

var _main: Node
var _materials: Node
var _drip: Node3D
var _gutter_water: Node3D
var _water: Node3D                      # the jerrycan's level, scaled up from its floor
var _water_tf: Transform3D
var _water_floor := 0.0                 # y of the bottom of the jerrycan's water
var _lamp := ""                         # the UV window's material (a numbered name)


func setup(main: Node, room: Node3D, materials: Node) -> void:
	_main = main
	_materials = materials
	_drip = room.find_child("filter_drip_*", true, false) as Node3D
	_gutter_water = room.find_child("rain_catcher_water", true, false) as Node3D
	for m: String in main.meta.materials:
		if m.begins_with("mat_uv_lamp_"):
			_lamp = m
	var water := room.find_child("jug_water_*", true, false) as MeshInstance3D
	if water:
		_water = water
		_water_tf = water.global_transform
		_water_floor = (water.global_transform * water.get_aabb()).position.y
	var board := room.find_child("uv_board_*", true, false) as MeshInstance3D
	if board:
		var light := OmniLight3D.new()
		light.name = "filter_fill"
		light.light_color = FILL_COLOR
		light.light_energy = FILL_ENERGY
		light.omni_range = FILL_RANGE
		light.omni_attenuation = 1.5
		main.get_node("WorldVP/Lights").add_child(light)
		light.global_position = board.global_transform * board.get_aabb().get_center() + Vector3(0.0, 0.0, 0.9)


## why it isn't running ("" when it is): what the hover label and the monologues go by
func blocked() -> String:
	if _main.shutters.value < OPEN_ENOUGH or not _main.shutters.is_open:
		return "shutters shut"
	if _main.weather.rain() < MIN_RAIN:
		return "no rain"
	return ""


func running() -> bool:
	return blocked() == ""


## the purifier's hover label
func label() -> String:
	match blocked():
		"shutters shut":
			return "UV PURIFIER (SHUTTERS SHUT)"
		"no rain":
			return "UV PURIFIER (NO RAIN)"
	return "UV PURIFIER (RUNNING)"


## the jerrycan's hover label
func jug_label() -> String:
	if fill >= 1.0:
		return "PURE WATER (FULL)"
	if fill < 0.01:
		return "JERRYCAN (EMPTY)"
	return "JERRYCAN (%d%%)" % int(fill * 100.0)


## a click on the purifier or its gutter: the player's thoughts on what it's doing
func click() -> void:
	if not GameState.flag("dlg_seen_filter_intro"):     # the first time: what it is (sets that flag)
		_main.interactions.say("filter_intro")
		return
	_main.interactions.say("filter_running" if running() else "filter_" + blocked().replace(" ", "_"))


## a click on the jerrycan: full, it goes into the inventory; otherwise a thought on why it isn't
func click_jug() -> void:
	if fill < 1.0:
		_main.interactions.say("jug_filling")
		return
	if not _main.ui.inventory.has_room():
		return
	_main.interactions.pick_up("jug", "pure_water")
	jug_here = false
	fill = 0.0


## the empty jerrycan is back under the tube (its water went into the tank)
func return_jug() -> void:
	jug_here = true
	fill = 0.0
	_main.picker.groups["jug"].visible = true


## per frame, from main.gd. delta in seconds.
func update(delta: float) -> void:
	var on := running()
	var dripping := on and jug_here and fill < 1.0
	if dripping:
		fill = minf(fill + _main.weather.rain() * delta / FILL_SECONDS, 1.0)
	if _drip:
		_drip.visible = dripping and fmod(_main.clock, DRIP_FRAMES) < DRIP_FRAMES * 0.5
	if _gutter_water:
		_gutter_water.visible = on
	if _lamp != "":
		_materials.set_param(_lamp, "emission_energy", LAMP_ENERGY if on else 0.0)
	if _water:
		_water.visible = fill > 0.02
		var k := maxf(fill, 0.02)           # scale the level up from the jerrycan's floor
		_water.global_transform = Transform3D(Basis.from_scale(Vector3(1.0, k, 1.0)), Vector3(0.0, _water_floor * (1.0 - k), 0.0)) * _water_tf
