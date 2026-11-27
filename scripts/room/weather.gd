extends Node
## The weather outside the window. The cabin sits on top of Neahkahnie Mountain on the Oregon coast
## (pipeline/scene/make_window_view.py renders the real view from there); this picks what the sky
## over it is doing and hands toon.gdshader's window (the "storm_window_emit" material, kind 3) its
## w_* uniforms, and the same to the hole in the wall under the window ("wall_hole_view"). It also
## tints the light the window throws into the room (the storm_window spot and the storm_moon_rim light)
## to match.
##
## The weather is random. It holds each weather for HOLD seconds, then cross-fades over BLEND into
## another picked at random from today's choices, and each new day (GameState.day, moved on by the
## hanging lamp: room/pendant.gd) starts on a fresh random one, swapped in while the screen is black.
## Day 1 is the tutorial: it starts in the storm and stays rainy (TUTORIAL: storm and rain only), so
## the leak under the window and the water filter have water to work with. From day 2 any of CYCLE
## can come. The F9 debug menu steps through CYCLE in order (after(), set_weather()).
##
## To add a kind of weather, add a preset below (every key, colours linear) and put it in CYCLE.

const HOLD := 150.0                     # s each weather lasts
const BLEND := 20.0                     # s to cross-fade into the next
const CYCLE := ["storm", "rain", "overcast", "marine fog", "clear", "wildfire smoke"]
const TUTORIAL := ["storm", "rain"]     # day 1's choices: it stays rainy
const TUTORIAL_DAYS := 1

## cover: cloud cover 0..1. storm: 1 for the storm's blue (day 2: orange) clouds, 0 for plain `cloud`.
## sky_top / sky_low: the clear sky. vis: m, how far the haze lets you see. haze: its colour.
## land: light on the land and sea. fog: the marine layer's amount, fog_top its height (m; the window is
## at 493 m) and fog_col its colour. rain: streaks down the glass. lightning: flashes per minute.
## light: the room's window light, times its colour (the storm's light is 1, 1, 1).
## heat: how hot the room gets with the shutters open a while (0..1, the post shader's heat haze round
## the screen's edges); heat_in: how much still gets in with them shut. temp: the temperature outside,
## degC (the top-left corner shows it; above the tank's, an open window warms the tank: tank/tank_water.gd).
## humid: the relative humidity outside, 0..1 (room/cabin_climate.gd lets it in through the open window,
## where it cakes the reef salt).
## rain also sets how fast water runs in through the hole under the window (room/leak.gd) and how hard
## the water filter runs (room/water_filter.gd).
const PRESETS := {
	"storm": {
		"cover": 1.0, "storm": 1.0, "cloud": Vector3(0.10, 0.14, 0.22),
		"sky_top": Vector3(0.05, 0.12, 0.30), "sky_low": Vector3(0.20, 0.35, 0.55),
		"vis": 30000.0, "haze": Vector3(0.20, 0.30, 0.45), "land": Vector3(1.0, 1.0, 1.0),
		"fog": 0.0, "fog_top": 300.0, "fog_col": Vector3(0.5, 0.55, 0.62),
		"rain": 0.55, "lightning": 4.0, "light": Vector3(1.0, 1.0, 1.0), "heat": 0.45, "heat_in": 0.0, "temp": 33.0, "humid": 0.95,
	},
	"rain": {
		"cover": 1.0, "storm": 0.0, "cloud": Vector3(0.16, 0.19, 0.24),
		"sky_top": Vector3(0.10, 0.12, 0.16), "sky_low": Vector3(0.20, 0.23, 0.28),
		"vis": 9000.0, "haze": Vector3(0.17, 0.20, 0.25), "land": Vector3(0.75, 0.8, 0.85),
		"fog": 0.0, "fog_top": 250.0, "fog_col": Vector3(0.4, 0.44, 0.5),
		"rain": 1.0, "lightning": 0.0, "light": Vector3(0.55, 0.6, 0.65), "heat": 0.12, "heat_in": 0.0, "temp": 28.0, "humid": 0.97,
	},
	"overcast": {
		"cover": 1.0, "storm": 0.0, "cloud": Vector3(0.30, 0.33, 0.38),
		"sky_top": Vector3(0.25, 0.28, 0.33), "sky_low": Vector3(0.40, 0.43, 0.48),
		"vis": 22000.0, "haze": Vector3(0.36, 0.39, 0.44), "land": Vector3(0.9, 0.92, 0.95),
		"fog": 0.0, "fog_top": 250.0, "fog_col": Vector3(0.6, 0.63, 0.68),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(0.75, 0.78, 0.8), "heat": 0.35, "heat_in": 0.05, "temp": 34.0, "humid": 0.75,
	},
	# the Oregon coast's summer fog: the sea and the valleys under a bright layer of cloud, the
	# ridges and the summit above it in sun
	"marine fog": {
		"cover": 0.12, "storm": 0.0, "cloud": Vector3(0.9, 0.92, 0.95),
		"sky_top": Vector3(0.05, 0.20, 0.70), "sky_low": Vector3(0.18, 0.40, 0.85),
		"vis": 60000.0, "haze": Vector3(0.30, 0.48, 0.80), "land": Vector3(1.25, 1.2, 1.1),
		"fog": 1.0, "fog_top": 120.0, "fog_col": Vector3(0.72, 0.69, 0.64),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(1.4, 1.3, 1.1), "heat": 0.3, "heat_in": 0.0, "temp": 26.0, "humid": 0.98,
	},
	"clear": {
		"cover": 0.3, "storm": 0.0, "cloud": Vector3(0.85, 0.88, 0.92),
		"sky_top": Vector3(0.06, 0.25, 0.75), "sky_low": Vector3(0.45, 0.65, 0.90),
		"vis": 70000.0, "haze": Vector3(0.45, 0.62, 0.85), "land": Vector3(1.35, 1.3, 1.15),
		"fog": 0.0, "fog_top": 200.0, "fog_col": Vector3(0.9, 0.92, 0.95),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(1.6, 1.4, 1.1), "heat": 0.8, "heat_in": 0.2, "temp": 41.0, "humid": 0.35,
	},
	# smoke blown in from inland fires: a brown-orange sky, the sun a dull disc, the coast fading out
	"wildfire smoke": {
		"cover": 0.0, "storm": 0.0, "cloud": Vector3(0.5, 0.3, 0.15),
		"sky_top": Vector3(0.35, 0.16, 0.06), "sky_low": Vector3(0.80, 0.42, 0.12),
		"vis": 7000.0, "haze": Vector3(0.62, 0.33, 0.12), "land": Vector3(0.95, 0.65, 0.45),
		"fog": 0.0, "fog_top": 200.0, "fog_col": Vector3(0.7, 0.45, 0.25),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(1.3, 0.7, 0.35), "heat": 0.95, "heat_in": 0.3, "temp": 44.0, "humid": 0.30,
	},
}
const SKY_MATS := ["storm_window_emit", "wall_hole_view"]   # the window, and the hole under it
const FLASH_FRAMES := 5.0               # 24 fps frames a lightning flash takes to fade
const FLASH_LIGHT := 3.0                # the window light's extra brightness at the flash's peak

var current := "storm"                  # the weather showing (or the one being faded out of)
var next := ""                          # the weather being faded into ("" when settled)

var _main: Node
var _materials: Node
var _lights: Array[Light3D] = []        # the window's lights...
var _light_base: Array = []             # ... their colours and energies as set in main.tscn
var _since := 0.0                       # s in the current weather
var _flash_at := -1e9                   # the last lightning strike (24 fps frames)
var _rng := RandomNumberGenerator.new()
var _day := 1                           # the day the weather was last picked for
var _now: Dictionary = PRESETS["storm"] # this frame's blend of presets


func setup(main: Node, lights: Node3D, materials: Node) -> void:
	_main = main
	_materials = materials
	_rng.randomize()
	_day = GameState.day
	for n in ["storm_window", "storm_moon_rim"]:
		var l := lights.get_node_or_null(n) as Light3D
		if l:
			_lights.append(l)
			_light_base.append([l.light_color, l.light_energy])
	_apply(PRESETS[current], 0.0)


## how hot it is in the room, 0..1, for the post shader's heat haze. open: 0 with the shutters shut ..
## 1 once they have been open a while (shutters.gd's heat ramp)
func heat(open: float) -> float:
	return lerpf(_now.heat_in, _now.heat, clampf(open, 0.0, 1.0))


## the temperature outside now, degC (cross-fades with the weather)
func temperature() -> float:
	return _now.temp


## the relative humidity outside now, 0..1
func humidity() -> float:
	return _now.humid


## how hard it is raining now, 0..1
func rain() -> float:
	return _now.rain


## jump straight to a weather (the debug menu)
func set_weather(name: String) -> void:
	if PRESETS.has(name):
		current = name
		next = ""
		_since = 0.0


## the weather after `name` in CYCLE (the debug menu's W line)
func after(name: String) -> String:
	return CYCLE[(CYCLE.find(name) + 1) % CYCLE.size()]


## what the weather can be today: rainy only through the tutorial
func choices() -> Array:
	return TUTORIAL if GameState.day <= TUTORIAL_DAYS else CYCLE


## a random weather from today's choices, other than `name` when there's another to pick
func pick(name: String) -> String:
	var options := choices().filter(func(w): return w != name)
	if options.is_empty():
		return name
	return options[_rng.randi() % options.size()]


## per frame, from main.gd. delta in seconds; clock in 24 fps frames.
func update(delta: float, clock: float) -> void:
	_since += delta
	if GameState.day != _day:           # a new day: a new weather, straight away
		_day = GameState.day
		set_weather(pick(current))
	elif next == "" and _since >= HOLD:
		next = pick(current)
		_since = 0.0
	var w: Dictionary = PRESETS[current]
	if next != "":
		var t := smoothstep(0.0, 1.0, _since / BLEND)
		w = _mix(w, PRESETS[next], t)
		if _since >= BLEND:
			current = next
			next = ""
			_since = 0.0
	# lightning: strikes at random, `lightning` a minute on average, each a bright flicker
	if _rng.randf() < w.lightning / 60.0 * delta:
		_flash_at = clock
	var age := clock - _flash_at
	var flash := 0.0
	if age < FLASH_FRAMES:
		flash = (1.0 - age / FLASH_FRAMES) * (1.0 if int(age) % 2 == 0 else 0.5)
	_now = w
	_apply(w, flash)


func _apply(w: Dictionary, flash: float) -> void:
	for sky: String in SKY_MATS:
		var m := _materials
		m.set_param(sky, "w_cover", w.cover)
		m.set_param(sky, "w_storm", w.storm)
		m.set_param(sky, "w_cloud", w.cloud)
		m.set_param(sky, "w_sky_top", w.sky_top)
		m.set_param(sky, "w_sky_low", w.sky_low)
		m.set_param(sky, "w_vis", w.vis)
		m.set_param(sky, "w_haze", w.haze)
		m.set_param(sky, "w_land", w.land)
		m.set_param(sky, "w_fog", w.fog)
		m.set_param(sky, "w_fog_top", w.fog_top)
		m.set_param(sky, "w_fog_col", w.fog_col)
		m.set_param(sky, "w_rain", w.rain)
		m.set_param(sky, "w_flash", flash)
	var tint: Vector3 = w.light
	var bright := maxf(tint.x, maxf(tint.y, tint.z))
	for i in _lights.size():
		var base: Color = _light_base[i][0]
		var c := Color(base.r * tint.x, base.g * tint.y, base.b * tint.z) / bright
		_lights[i].light_color = c.lerp(Color.WHITE, flash * 0.6)
		_lights[i].light_energy = _light_base[i][1] * bright * (1.0 + FLASH_LIGHT * flash)


## a blend of two presets, t of the way from a to b
static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = lerp(a[k], b[k], t)
	return out
