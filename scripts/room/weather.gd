extends Node
## The weather outside the window. The cabin sits on top of Neahkahnie Mountain on the Oregon coast
## (pipeline/scene/make_window_view.py renders the real view from there); this picks what the sky
## over it is doing and hands toon.gdshader's window (the "storm_window_emit" material, kind 3) its
## w_* uniforms. It also tints the light the window throws into the room (the storm_window spot and
## the storm_moon_rim light) to match.
##
## The weather starts in the storm and moves on through PRESETS in CYCLE order, holding each for
## HOLD seconds and cross-fading over BLEND. The F9 debug menu can jump to any of them (set()).
##
## To add a kind of weather, add a preset below (every key, colours linear) and put it in CYCLE.

const HOLD := 150.0                     # s each weather lasts
const BLEND := 20.0                     # s to cross-fade into the next
const CYCLE := ["storm", "rain", "overcast", "marine fog", "clear", "wildfire smoke"]

## cover: cloud cover 0..1. storm: 1 for the storm's blue (day 2: orange) clouds, 0 for plain `cloud`.
## sky_top / sky_low: the clear sky. vis: m, how far the haze lets you see. haze: its colour.
## land: light on the land and sea. fog: the marine layer's amount, fog_top its height (m; the window is
## at 493 m) and fog_col its colour. rain: streaks down the glass. lightning: flashes per minute.
## light: the room's window light, times its colour (the storm's light is 1, 1, 1).
## heat: how hot the room gets with the shutters open a while (0..1, the post shader's heat haze round
## the screen's edges); heat_in: how much still gets in with them shut.
const PRESETS := {
	"storm": {
		"cover": 1.0, "storm": 1.0, "cloud": Vector3(0.10, 0.14, 0.22),
		"sky_top": Vector3(0.05, 0.12, 0.30), "sky_low": Vector3(0.20, 0.35, 0.55),
		"vis": 30000.0, "haze": Vector3(0.20, 0.30, 0.45), "land": Vector3(1.0, 1.0, 1.0),
		"fog": 0.0, "fog_top": 300.0, "fog_col": Vector3(0.5, 0.55, 0.62),
		"rain": 0.55, "lightning": 1.0, "light": Vector3(1.0, 1.0, 1.0), "heat": 0.45, "heat_in": 0.0,
	},
	"rain": {
		"cover": 1.0, "storm": 0.0, "cloud": Vector3(0.16, 0.19, 0.24),
		"sky_top": Vector3(0.10, 0.12, 0.16), "sky_low": Vector3(0.20, 0.23, 0.28),
		"vis": 9000.0, "haze": Vector3(0.17, 0.20, 0.25), "land": Vector3(0.75, 0.8, 0.85),
		"fog": 0.0, "fog_top": 250.0, "fog_col": Vector3(0.4, 0.44, 0.5),
		"rain": 1.0, "lightning": 0.0, "light": Vector3(0.55, 0.6, 0.65), "heat": 0.12, "heat_in": 0.0,
	},
	"overcast": {
		"cover": 1.0, "storm": 0.0, "cloud": Vector3(0.30, 0.33, 0.38),
		"sky_top": Vector3(0.25, 0.28, 0.33), "sky_low": Vector3(0.40, 0.43, 0.48),
		"vis": 22000.0, "haze": Vector3(0.36, 0.39, 0.44), "land": Vector3(0.9, 0.92, 0.95),
		"fog": 0.0, "fog_top": 250.0, "fog_col": Vector3(0.6, 0.63, 0.68),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(0.75, 0.78, 0.8), "heat": 0.35, "heat_in": 0.05,
	},
	# the Oregon coast's summer fog: the sea and the valleys under a bright layer of cloud, the
	# ridges and the summit above it in sun
	"marine fog": {
		"cover": 0.12, "storm": 0.0, "cloud": Vector3(0.9, 0.92, 0.95),
		"sky_top": Vector3(0.05, 0.20, 0.70), "sky_low": Vector3(0.18, 0.40, 0.85),
		"vis": 60000.0, "haze": Vector3(0.30, 0.48, 0.80), "land": Vector3(1.25, 1.2, 1.1),
		"fog": 1.0, "fog_top": 120.0, "fog_col": Vector3(0.72, 0.69, 0.64),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(1.4, 1.3, 1.1), "heat": 0.3, "heat_in": 0.0,
	},
	"clear": {
		"cover": 0.3, "storm": 0.0, "cloud": Vector3(0.85, 0.88, 0.92),
		"sky_top": Vector3(0.06, 0.25, 0.75), "sky_low": Vector3(0.45, 0.65, 0.90),
		"vis": 70000.0, "haze": Vector3(0.45, 0.62, 0.85), "land": Vector3(1.35, 1.3, 1.15),
		"fog": 0.0, "fog_top": 200.0, "fog_col": Vector3(0.9, 0.92, 0.95),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(1.6, 1.4, 1.1), "heat": 0.8, "heat_in": 0.2,
	},
	# smoke blown in from inland fires: a brown-orange sky, the sun a dull disc, the coast fading out
	"wildfire smoke": {
		"cover": 0.0, "storm": 0.0, "cloud": Vector3(0.5, 0.3, 0.15),
		"sky_top": Vector3(0.35, 0.16, 0.06), "sky_low": Vector3(0.80, 0.42, 0.12),
		"vis": 7000.0, "haze": Vector3(0.62, 0.33, 0.12), "land": Vector3(0.95, 0.65, 0.45),
		"fog": 0.0, "fog_top": 200.0, "fog_col": Vector3(0.7, 0.45, 0.25),
		"rain": 0.0, "lightning": 0.0, "light": Vector3(1.3, 0.7, 0.35), "heat": 0.95, "heat_in": 0.3,
	},
}
const SKY_MAT := "storm_window_emit"
const FLASH_FRAMES := 9.0               # 24 fps frames a lightning flash takes to fade
const FLASH_LIGHT := 0.8                # the window light's extra brightness at the flash's peak

var current := "storm"                  # the weather showing (or the one being faded out of)
var next := ""                          # the weather being faded into ("" when settled)

var _main: Node
var _materials: Node
var _lights: Array[Light3D] = []        # the window's lights...
var _light_base: Array = []             # ... their colours and energies as set in main.tscn
var _since := 0.0                       # s in the current weather
var _flash_at := -1e9                   # the last lightning strike (24 fps frames)
var _rng := RandomNumberGenerator.new()
var _now: Dictionary = PRESETS["storm"] # this frame's blend of presets


func setup(main: Node, lights: Node3D, materials: Node) -> void:
	_main = main
	_materials = materials
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


## jump straight to a weather (the debug menu)
func set_weather(name: String) -> void:
	if PRESETS.has(name):
		current = name
		next = ""
		_since = 0.0


## the weather after `name` in CYCLE
func after(name: String) -> String:
	return CYCLE[(CYCLE.find(name) + 1) % CYCLE.size()]


## per frame, from main.gd. delta in seconds; clock in 24 fps frames.
func update(delta: float, clock: float) -> void:
	_since += delta
	if next == "" and _since >= HOLD:
		next = after(current)
		_since = 0.0
	var w: Dictionary = PRESETS[current]
	if next != "":
		var t := smoothstep(0.0, 1.0, _since / BLEND)
		w = _mix(w, PRESETS[next], t)
		if _since >= BLEND:
			current = next
			next = ""
			_since = 0.0
	# lightning: occasional random strikes, each one smooth so it does not resemble a faulty lamp
	if _rng.randf() < w.lightning / 60.0 * delta:
		_flash_at = clock
	var age := clock - _flash_at
	var flash := 0.0
	if age < FLASH_FRAMES:
		flash = pow(1.0 - age / FLASH_FRAMES, 2.0)
	_now = w
	_apply(w, flash)


func _apply(w: Dictionary, flash: float) -> void:
	var m := _materials
	m.set_param(SKY_MAT, "w_cover", w.cover)
	m.set_param(SKY_MAT, "w_storm", w.storm)
	m.set_param(SKY_MAT, "w_cloud", w.cloud)
	m.set_param(SKY_MAT, "w_sky_top", w.sky_top)
	m.set_param(SKY_MAT, "w_sky_low", w.sky_low)
	m.set_param(SKY_MAT, "w_vis", w.vis)
	m.set_param(SKY_MAT, "w_haze", w.haze)
	m.set_param(SKY_MAT, "w_land", w.land)
	m.set_param(SKY_MAT, "w_fog", w.fog)
	m.set_param(SKY_MAT, "w_fog_top", w.fog_top)
	m.set_param(SKY_MAT, "w_fog_col", w.fog_col)
	m.set_param(SKY_MAT, "w_rain", w.rain)
	m.set_param(SKY_MAT, "w_flash", flash)
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
