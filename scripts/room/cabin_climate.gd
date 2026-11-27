extends Node
## The air inside the cabin, and the instruments above the workbench that show it.
##
## The cabin is sealed against the heat: shut, it sits near BASE_TEMP and BASE_HUMID (a little damper
## for the warm, open reef tank and any puddle under the window: room/leak.gd). Open the shutters
## and it moves toward the weather outside (room/weather.gd's temperature() and humidity()), fast;
## shut them and it settles back, slowly. The reef salt cakes in damp, warm air (room/salt_bag.gd)
## and the tank warms in hot air and evaporates faster in dry air (tank/tank_water.gd).
##
## The board above the workbench (08_wall_weather_instruments) reads it: the left dial is a
## hygrometer (relative humidity, 0 to 100 % across its scale), the right dial a barometer (low in a
## storm, high when it's clear), and the thermometer rises with the temperature. Its hover label
## gives the numbers (room/interactions.gd).

const BASE_TEMP := 31.0                 # degC, the sealed cabin
const BASE_HUMID := 0.52                # relative humidity, the sealed cabin
const TANK_HUMID := 0.06                # the reef tank's open water adds this much
const PUDDLE_HUMID := 0.15              # a full puddle on the floor adds this much
const OPEN_SECONDS := 40.0              # time constant toward the outside air, shutters open
const SHUT_SECONDS := 300.0             # time constant back to the cabin's own, shutters shut
const DIAL_SWEEP := deg_to_rad(140.0)   # the dials' scales run from -140 to +140 degrees off upright
const THERMO_LOW := 15.0                # degC at the thermometer's bottom and top
const THERMO_HIGH := 45.0

var temp := BASE_TEMP                   # degC
var humid := BASE_HUMID + TANK_HUMID    # relative humidity, 0..1

var _main: Node
var _dials: Array = []                  # [pivot, pointer's own angle] for the hygrometer, the barometer
var _mercury: MeshInstance3D
var _mercury_tf: Transform3D
var _mercury_floor := 0.0


func setup(main: Node, room: Node3D) -> void:
	_main = main
	var pointers := room.find_children("dark_gauge_pointer_*", "MeshInstance3D", true, false)
	var hubs := room.find_children("center_needle_hub_*", "MeshInstance3D", true, false)
	pointers.sort_custom(func(a, b): return _centre(a).x < _centre(b).x)
	hubs.sort_custom(func(a, b): return _centre(a).x < _centre(b).x)
	var start := [-0.48, 0.30]          # the pointers' angles as modelled (generate_assets.py)
	for i in mini(pointers.size(), hubs.size()):
		var pivot := Node3D.new()
		pivot.name = "gauge_pivot_%d" % i
		pointers[i].get_parent().add_child(pivot)
		pivot.global_transform = Transform3D(Basis(), _centre(hubs[i]))
		pointers[i].reparent(pivot, true)
		_dials.append([pivot, start[i] if i < start.size() else 0.0])
	_mercury = room.find_child("mercury_fill_*", true, false) as MeshInstance3D
	if _mercury:
		_mercury_tf = _mercury.global_transform
		_mercury_floor = (_mercury.global_transform * _mercury.get_aabb()).position.y


func _centre(n: Node3D) -> Vector3:
	var mi := n as MeshInstance3D
	return (mi.global_transform * mi.get_aabb()).get_center() if mi else n.global_position


## per frame, from main.gd. delta in seconds.
func update(delta: float) -> void:
	var shutters = _main.shutters
	var weather = _main.weather
	var open: float = shutters.heat / shutters.MAX_HEAT       # 0 shut .. 1 open a while
	var t_goal := lerpf(BASE_TEMP, weather.temperature(), open)
	var h_goal := clampf(lerpf(BASE_HUMID + TANK_HUMID, weather.humidity(), open) + PUDDLE_HUMID * _main.leak.level, 0.0, 1.0)
	var k := 1.0 - exp(-delta / lerpf(SHUT_SECONDS, OPEN_SECONDS, open))
	temp += (t_goal - temp) * k
	humid += (h_goal - humid) * k
	_show(weather)


## the needles and the thermometer
func _show(weather) -> void:
	var pressure: float = clampf(1.0 - 0.45 * weather.rain() - 0.35 * weather._now.cover * weather._now.storm - 0.15 * weather._now.cover, 0.0, 1.0)
	var reads := [humid, pressure]
	for i in _dials.size():
		var target := lerpf(-DIAL_SWEEP, DIAL_SWEEP, clampf(reads[i], 0.0, 1.0))
		var pivot: Node3D = _dials[i][0]
		pivot.global_transform = Transform3D(Basis(Vector3(0, 0, 1), -(target - _dials[i][1])), pivot.global_position)
	if _mercury:
		# the column as modelled is 49 % of the tube; scale it about its foot to the temperature
		var f := clampf((temp - THERMO_LOW) / (THERMO_HIGH - THERMO_LOW), 0.08, 1.0) / 0.49
		_mercury.global_transform = Transform3D(Basis.from_scale(Vector3(1, f, 1)), Vector3(0, _mercury_floor * (1.0 - f), 0)) * _mercury_tf


## the gauges' hover label
func label() -> String:
	return "CABIN %d C - HUMIDITY %d%%" % [roundi(temp), roundi(humid * 100.0)]
