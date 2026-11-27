extends Node
## What the cabin does to the saltwater reef tank's water. It moves the values in
## tank/tank_panel.gd's readings (the panel and its bars follow).
##
##   the warm air: when the cabin (room/cabin_climate.gd) is hotter than the water, the water warms
##     toward it, faster the bigger the gap. Cooler air doesn't cool it: the tank's lamp and pumps
##     keep it warm, so cooling is a job for the player (issue #35).
##   evaporation: the open tank loses water, faster when it's warm and the air is dry (about 1-2 % a
##     day, as a real one does; overnight, at lights out, it loses NIGHT_SHARE of a day's worth). The salt stays
##     behind, so the level drops and the salinity climbs. And it undoes a water change: while the water
##     turns over, the cabin's CO2-heavy air dissolves back in and the oxygen drains off again, so pH and
##     oxygen drift back toward where the cabin pushes them (PH_CABIN, OXYGEN_CABIN), DRIFT_LITRES of
##     evaporation at a time. Water changes buy time; the lasting fixes are the crafted ones (#35).
##   PURE WATER (from the UV purifier, room/water_filter.gd) in a tank slot is a top-off: it puts back
##     what evaporated, so the level rises and the salinity falls. It has no salt and no buffer, so it
##     does nothing for pH (it thins the buffer a little).
##   SALTWATER (pure water + reef salt, crafting/crafting.gd) in a tank slot is a water change, the
##     canon fix: JUG_LITRES of old water out, the same of new seawater in, at 35 ppt and pH 8.2 with
##     oxygen in it. Salinity and temperature mix by volume. pH and oxygen move CHANGE_SHARE of the way:
##     more than a real 20 L change in a 260 L tank would (about 8 %), so it shows within a few jugs.
## Either way the empty jerrycan goes back under the purifier.

const TEMP := 0                         # rows of tank_panel.gd's readings
const PH := 1
const OXYGEN := 2
const SALINITY := 3
const LEVEL := 4
const FULL_LITRES := 260.0              # the tank at 100 %
const JUG_LITRES := 20.0
const WARM_PER_DEGREE := 1.0 / 420.0    # degC a second, per degC the cabin is warmer than the water
const TEMP_CAP := 34.0                  # the gauge's top: the water stops climbing here
## A warm, open reef tank loses about 1-2 % of its water a day: 4 L of 260 at EVAP_TEMP in half-saturated
## air, doubling every EVAP_SPAN degC warmer and in proportion to how dry the air is. Topping off every
## few days is normal reef keeping; leave it a week and the salinity creeps past 38 ppt.
const EVAP_PER_DAY := 4.0               # litres
const EVAP_TEMP := 30.0
const EVAP_SPAN := 10.0
const DAY_SECONDS := 720.0              # the play time a day's rates are spread over (12 min)
const NIGHT_SHARE := 0.4                # lights out to morning (pendant.gd) evaporates this much of a day's
const MIN_LEVEL := 60.0                 # % the water can't evaporate below (weeks of neglect)
const DRIFT_LITRES := 3.0               # evaporating this much takes pH and oxygen ~63 % back
const PH_CABIN := 7.74                  # where the cabin's air holds the pH...
const OXYGEN_CABIN := 3.6               # ...and the oxygen, mg/L
const NEW_SALINITY := 35.0              # freshly mixed seawater
const NEW_PH := 8.2
const NEW_OXYGEN := 6.8
const PURE_OXYGEN := 7.0                # rainwater is near saturated with oxygen
const PURE_PH_DROP := 0.01              # what a jerrycan of unbuffered water does to the pH
const CHANGE_SHARE := 0.3               # share of the gap a saltwater change closes for pH and oxygen

var _main: Node
var _day := 1


func setup(main: Node) -> void:
	_main = main
	_day = GameState.day
	main.tank_panel.changed.connect(_on_slots_changed)


func litres() -> float:
	return _main.tank_panel.readings[LEVEL].value / 100.0 * FULL_LITRES


## per frame, from main.gd. delta in seconds.
func update(delta: float) -> void:
	var r: Array = _main.tank_panel.readings
	var climate = _main.climate
	var temp: float = r[TEMP].value
	if climate.temp > temp and temp < TEMP_CAP:
		r[TEMP].value = minf(temp + (climate.temp - temp) * WARM_PER_DEGREE * delta, minf(climate.temp, TEMP_CAP))
	evaporate(evap_rate() * delta)
	if GameState.day != _day:           # the night just passed: its share of a day's evaporation
		_day = GameState.day
		evaporate(evap_rate() * DAY_SECONDS * NIGHT_SHARE)


## litres a second evaporating now
func evap_rate() -> float:
	var r: Array = _main.tank_panel.readings
	var dry: float = (1.0 - _main.climate.humid) / 0.5
	return EVAP_PER_DAY / DAY_SECONDS * pow(2.0, (r[TEMP].value - EVAP_TEMP) / EVAP_SPAN) * dry


## water out, salt stays, and the cabin's air takes back pH and oxygen
func evaporate(lost: float) -> void:
	var r: Array = _main.tank_panel.readings
	var v := litres()
	lost = minf(lost, v - FULL_LITRES * MIN_LEVEL / 100.0)
	if lost <= 0.0:
		return
	r[SALINITY].value *= v / (v - lost)
	r[LEVEL].value = (v - lost) / FULL_LITRES * 100.0
	var k := 1.0 - exp(-lost / DRIFT_LITRES)
	r[PH].value += (PH_CABIN - r[PH].value) * k
	r[OXYGEN].value += (OXYGEN_CABIN - r[OXYGEN].value) * k


## an item went into a tank slot: a jerrycan of pure water or saltwater is poured in at once
func _on_slots_changed() -> void:
	var panel = _main.tank_panel
	for i in panel.contents.size():
		var item: ItemData = panel.contents[i]
		if item == null or not item.id in ["pure_water", "saltwater"]:
			continue
		panel.contents[i] = null
		if item.id == "pure_water":
			top_off()
		else:
			water_change()
		_main.water_filter.return_jug()


## PURE WATER: back up toward full (any extra spills), the salt spread through more water
func top_off() -> void:
	var r: Array = _main.tank_panel.readings
	var v := litres()
	var add := minf(JUG_LITRES, FULL_LITRES - v)
	if add <= 0.0:
		_main.interactions.say("tank_full")
		return
	var f := add / (v + add)
	r[SALINITY].value *= v / (v + add)
	r[TEMP].value += (_main.climate.temp - r[TEMP].value) * f
	r[OXYGEN].value += (PURE_OXYGEN - r[OXYGEN].value) * f
	r[PH].value -= PURE_PH_DROP * add / JUG_LITRES
	r[LEVEL].value = (v + add) / FULL_LITRES * 100.0
	_main.interactions.say("tank_top_off")


## SALTWATER: a water change, the level unchanged
func water_change() -> void:
	var r: Array = _main.tank_panel.readings
	var f := minf(JUG_LITRES / litres(), 1.0)
	r[SALINITY].value += (NEW_SALINITY - r[SALINITY].value) * f
	r[TEMP].value += (_main.climate.temp - r[TEMP].value) * f
	r[PH].value += (NEW_PH - r[PH].value) * CHANGE_SHARE
	r[OXYGEN].value += (NEW_OXYGEN - r[OXYGEN].value) * CHANGE_SHARE
	_main.interactions.say("tank_water_change")
