extends Node
## What the cabin does to the reef tank's water. It moves the values in tank/tank_panel.gd's
## readings (the panel and its bars follow).
##
##   the open window: with the shutters open and the weather outside hotter than the tank, the water
##     warms toward the outside temperature (room/weather.gd's temperature()), faster the bigger the
##     gap. A cooler day outside does not cool it: the cabin's still air keeps the heat in.
##   clean water: a full jug from the water filter (room/water_filter.gd) put in one of the tank
##     panel's slots is a water change. It dilutes the tank's dissolved CO2 and brings in oxygen, so pH
##     and oxygen move part of the way toward the middle of their safe bands; the empty jug goes back
##     under the filter's tap.
##
## Rates are first guesses, to be balanced with the rest of the tank's chemistry (issue #35).

const TEMP := 0                         # rows of tank_panel.gd's readings
const PH := 1
const OXYGEN := 2
const WARM_PER_DEGREE := 1.0 / 420.0    # degC a second, per degC hotter outside, shutters fully open
const TEMP_CAP := 34.0                  # the gauge's top: the water stops climbing here
const WATER_CHANGE := 0.35              # share of the gap to the targets one jug closes
const PH_TARGET := 8.15
const OXYGEN_TARGET := 6.5

var _main: Node


func setup(main: Node) -> void:
	_main = main
	main.tank_panel.changed.connect(_on_slots_changed)


## per frame, from main.gd. delta in seconds.
func update(delta: float) -> void:
	var r: Array = _main.tank_panel.readings
	var shutters = _main.shutters
	var open: float = shutters.heat / shutters.MAX_HEAT          # 0 shut .. 1 open a while
	var outside: float = _main.weather.temperature()
	var temp: float = r[TEMP].value
	if open > 0.0 and outside > temp and temp < TEMP_CAP:
		r[TEMP].value = minf(temp + (outside - temp) * WARM_PER_DEGREE * open * delta, minf(outside, TEMP_CAP))


## an item went into (or came out of) a tank slot: a jug of clean water is poured in at once
func _on_slots_changed() -> void:
	var panel = _main.tank_panel
	for i in panel.contents.size():
		var item: ItemData = panel.contents[i]
		if item != null and item.id == "water_jug":
			panel.contents[i] = null
			var r: Array = panel.readings
			r[PH].value += (PH_TARGET - r[PH].value) * WATER_CHANGE
			r[OXYGEN].value += (OXYGEN_TARGET - r[OXYGEN].value) * WATER_CHANGE
			_main.water_filter.return_jug()
			_main.interactions.say("tank_water_change")
