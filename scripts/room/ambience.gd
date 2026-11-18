extends Node
## Things in the room that move on their own: the storm outside the window, the PA speaker's
## breathing status light, and the lantern's slow glow. Also evens out the lighting between
## renderers (see setup).

## The Compatibility renderer (the web build and the OpenGL fallback) adds each shadow-casting light
## in its own pass, in sRGB space, which over-brightens what it touches. Those lights are scaled by
## this there, a value fitted against Forward+ screenshots.
const COMPAT_SHADOW_LIGHT_SCALE := 0.2
const LANTERN_SWING := 0.04             # the lantern breathes +/- 4 % around its set brightness
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


func setup(main: Node, lights: Node3D, materials: Node, lantern: OmniLight3D, compat: bool) -> void:
	_main = main
	_materials = materials
	_lantern = lantern
	_lantern_energy = lantern.light_energy
	_radio_glow = lights.get_node_or_null("radio_glow") as OmniLight3D
	if compat:
		for l: Light3D in lights.get_children():
			if l.shadow_enabled:
				l.light_energy *= COMPAT_SHADOW_LIGHT_SCALE


func update() -> void:
	var clock: float = _main.clock
	_materials.set_param("storm_window_emit", "sky_w", clock * 2.2 / 600.0)          # storm drift
	_materials.set_param("pa_led", "emission_energy", 6.0 + 3.0 * sin(clock * 0.21))
	# slow and faint on purpose: a fast or strong flicker makes the toon light bands jump
	var n := sin(clock * 0.045) * 0.6 + sin(clock * 0.11 + 1.7) * 0.4
	_lantern.light_energy = _lantern_energy * (1.0 + LANTERN_SWING * n)

	var radio_lit: bool = _main.ui.dialogue != null and _main.ui.dialogue.is_radio_lit()
	var lcd_energy := 3.0 * (0.82 + 0.18 * sin(clock * 0.75)) if radio_lit else 0.0
	for m: String in RADIO_LCD_MATS:
		_materials.set_param(m, "emission_energy", lcd_energy)

	if _radio_glow != null:
		if radio_lit:
			var target_glow := 1.6 + 0.6 * sin(clock * 0.65) + 0.25 * sin(clock * 1.9)
			_radio_glow.light_energy = lerpf(_radio_glow.light_energy, target_glow, 0.2)
		else:
			_radio_glow.light_energy = lerpf(_radio_glow.light_energy, 0.0, 0.15)
