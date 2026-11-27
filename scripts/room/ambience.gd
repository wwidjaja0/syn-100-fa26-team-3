extends Node
## Things in the room that move on their own: the storm outside the window, the PA speaker's
## breathing status light, the lantern's slow glow, and two status lights:
##   the battery dock (by the power station): blinks green while the lead-acid battery charges,
##     holds green once it is full (flag "battery_charged"), dark once the battery is taken;
##   the ham radio: dark while it is broken, solid red once it has power, blinking red while a
##     call is waiting or someone is talking on it.
## Also evens out the lighting between renderers (see setup).

## The Compatibility renderer (the web build and the OpenGL fallback) adds each shadow-casting light
## in its own pass, in sRGB space, which over-brightens what it touches. Those lights are scaled by
## this there, a value fitted against Forward+ screenshots.
const COMPAT_SHADOW_LIGHT_SCALE := 0.2
const LANTERN_SWING := 0.04             # the lantern breathes +/- 4 % around its set brightness
const LED_ON := 1.0                     # status lights' glow when lit: brighter washes the colour out
const CHARGE_SECONDS := 75.0            # how long the battery charges once the game has started
const CHARGE_BLINK := 1.0               # blinks per second while charging
const DOCK_GLOW := 1.4                  # the green light the dock's LED throws on the battery
const DOCK_GLOW_RANGE := 0.75           # m
const RADIO_BLINK := 1.6                # blinks per second for a waiting call
const RADIO_LCD_MATS := [
	"mat_lcd_glass_39",
	"mat_lcd_digit_40", "mat_lcd_digit_41", "mat_lcd_digit_42",
	"mat_lcd_digit_43", "mat_lcd_digit_44", "mat_lcd_digit_45",
]

var _main: Node
var _materials: Node
var _lantern: OmniLight3D
var _lantern_energy := 1.0
var _radio_glow: OmniLight3D
var _charge_led := ""                   # the dock's and the radio's light materials (numbered names)
var _radio_led := ""
var _dock_glow: OmniLight3D            # made in setup(), in front of the dock's LED
var _charged_for := 0.0                 # seconds the battery has been charging
var _last_clock := 0.0


func setup(main: Node, lights: Node3D, materials: Node, lantern: OmniLight3D, compat: bool) -> void:
	_main = main
	_materials = materials
	_lantern = lantern
	_lantern_energy = lantern.light_energy
	_radio_glow = lights.get_node_or_null("radio_glow") as OmniLight3D
	var led := main.room.find_child("charge_led_*", true, false) as Node3D
	if led:
		# a small green light just in front of the LED, so the battery (in the cabin's dim corner)
		# picks up its blink
		_dock_glow = OmniLight3D.new()
		_dock_glow.name = "dock_glow"
		_dock_glow.light_color = Color8(64, 224, 84)
		_dock_glow.omni_range = DOCK_GLOW_RANGE
		_dock_glow.omni_attenuation = 1.5
		lights.add_child(_dock_glow)
		_dock_glow.global_position = led.global_transform * (led as MeshInstance3D).get_aabb().get_center() + Vector3(-0.08, 0.04, 0.12)
	for m: String in main.meta.materials:
		if m.begins_with("mat_charge_led_"):
			_charge_led = m
		elif m.begins_with("mat_radio_led_"):
			_radio_led = m
	if compat:
		for l: Light3D in lights.get_children():
			if l.shadow_enabled:
				l.light_energy *= COMPAT_SHADOW_LIGHT_SCALE


func update() -> void:
	var clock: float = _main.clock
	for sky in ["storm_window_emit", "wall_hole_view"]:                              # storm drift
		_materials.set_param(sky, "sky_w", clock * 2.2 / 600.0)
	_materials.set_param("pa_led", "emission_energy", 6.0 + 3.0 * sin(clock * 0.21))
	# slow and faint on purpose: a fast or strong flicker makes the toon light bands jump
	var n := sin(clock * 0.045) * 0.6 + sin(clock * 0.11 + 1.7) * 0.4
	_lantern.light_energy = _lantern_energy * (1.0 + LANTERN_SWING * n)

	var radio_lit: bool = _main.ui.dialogue != null and _main.ui.dialogue.is_radio_lit()
	_status_lights(clock, radio_lit)
	var lcd_energy := 3.0 * (0.82 + 0.18 * sin(clock * 0.75)) if radio_lit else 0.0
	for m: String in RADIO_LCD_MATS:
		_materials.set_param(m, "emission_energy", lcd_energy)

	if _radio_glow != null:
		if radio_lit:
			var target_glow := 1.6 + 0.6 * sin(clock * 0.65) + 0.25 * sin(clock * 1.9)
			_radio_glow.light_energy = lerpf(_radio_glow.light_energy, target_glow, 0.2)
		else:
			_radio_glow.light_energy = lerpf(_radio_glow.light_energy, 0.0, 0.15)


## the battery dock's green light and the radio's red one (see the top of this file)
func _status_lights(clock: float, radio_lit: bool) -> void:
	var secs := clock / 24.0
	if not _main.landing_active and not GameState.flag("battery_charged"):
		_charged_for += 1.0 / 24.0 * maxf(0.0, clock - _last_clock)
		if _charged_for >= CHARGE_SECONDS:
			GameState.set_flag("battery_charged")
	_last_clock = clock
	var charge := 0.0
	if not GameState.flag("took_battery"):
		charge = LED_ON if GameState.flag("battery_charged") or _blink(secs, CHARGE_BLINK) else 0.0
	_materials.set_param(_charge_led, "emission_energy", charge)
	if _dock_glow:
		_dock_glow.light_energy = DOCK_GLOW * charge / LED_ON
	var radio := 0.0
	if GameState.flag("radio_fixed"):
		radio = LED_ON if not radio_lit or _blink(secs, RADIO_BLINK) else 0.0
	_materials.set_param(_radio_led, "emission_energy", radio)


## on for the first 60 % of each blink
func _blink(secs: float, per_second: float) -> bool:
	return fmod(secs * per_second, 1.0) < 0.6
