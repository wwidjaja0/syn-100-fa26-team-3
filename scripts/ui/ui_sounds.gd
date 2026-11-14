extends Node
## Autoload UiSounds: every UI sound (menus, inventory, map, BACK), on the SFX bus.
##
##     UiSounds.play("click")
##
## PLACEHOLDERS. There are no sound files yet, so each sound is built here at start-up: a few
## notes on a stepped triangle wave (the soft, hollow voice of an 8-bit console's triangle
## channel), faded in and out. To use real sounds, load them into `_streams` under the
## same names instead (e.g. `"click": preload("res://audio/ui_click.wav")`); nothing else changes.
##
## Only UI makes these sounds, and only when something is clicked or backed out of. Hovering is
## silent, and so is clicking an object in the room.
##
##   click   a button was pressed
##   back    a menu or the map closed, or a held item was put back (the X, Esc, right-click).
##           Leaving a close-up view (BACK) is silent, like entering one.
##   pick    an item was taken out of an inventory slot
##   tick    a slider moved a notch; the map zoomed a step
##   start   Start Game

const RATE := 22050
const VOICES := 4                       # sounds that can overlap
const TRIANGLE_STEPS := 8.0             # levels each side of zero in the triangle wave
const SMOOTHING := 0.35                 # 0..1: lower is duller (a one-pole low-pass)
const ATTACK := 90.0                    # samples to fade in over (~4 ms)
const RELEASE := 220.0                  # samples to fade out over (~10 ms)

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # the pause menu plays these while the game is paused
	_streams = {                                     # [[Hz, seconds], ...], loudness 0..1
		"click": _blip([[440.0, 0.035], [587.0, 0.06]], 0.45),
		"back": _blip([[523.0, 0.035], [392.0, 0.07]], 0.45),
		"pick": _blip([[587.0, 0.03], [784.0, 0.07]], 0.42),
		"tick": _blip([[659.0, 0.025]], 0.26),
		"start": _blip([[392.0, 0.07], [523.0, 0.07], [659.0, 0.07], [784.0, 0.18]], 0.45),
		"type_mono": _blip([[330.0, 0.018]], 0.18),
		"type_radio": _blip([[740.0, 0.014], [880.0, 0.014]], 0.20),
		"radio_in": _blip([[980.0, 0.025], [620.0, 0.03], [840.0, 0.04]], 0.30),
		"radio_static": _static_burst(0.55, 0.28),
	}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)


func play(sound: String) -> void:
	if not _streams.has(sound):
		push_warning("UiSounds: no sound named '%s'" % sound)
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.play()


## a run of notes that fades out, as a 16-bit mono stream. The voice is a triangle wave in
## TRIANGLE_STEPS levels, lightly smoothed: still chiptune, without a square wave's buzz.
func _blip(notes: Array, loudness: float) -> AudioStreamWAV:
	var total := 0.0
	for n in notes:
		total += n[1]
	var count := int(total * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var i := 0
	var phase := 0.25                                # carried across notes, so they join without a click
	var smooth := 0.0
	for n in notes:
		for k in int(n[1] * RATE):
			if i >= count:
				break
			phase = fmod(phase + n[0] / RATE, 1.0)
			var tri := 1.0 - 4.0 * absf(phase - 0.5)                 # -1..1
			tri = roundf(tri * TRIANGLE_STEPS) / TRIANGLE_STEPS
			smooth = lerpf(smooth, tri, SMOOTHING)                   # round the steps' edges off
			var t := float(i) / count
			var envelope := minf(i / ATTACK, 1.0) * exp(-3.0 * t) * minf((count - i) / RELEASE, 1.0)
			data.encode_s16(i * 2, int(smooth * loudness * envelope * 32767.0))
			i += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


## band-limited radio static burst with a faint carrier warble for incoming transmissions
func _static_burst(duration: float, loudness: float) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x52414449
	var lp := 0.0
	var prev_lp := 0.0
	var carrier_phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var white := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, white, 0.42)
		var band := lp - prev_lp * 0.65
		prev_lp = lp
		var crackle := 1.0 if rng.randf() > 0.015 else 1.8
		var freq := 780.0 + 140.0 * sin(TAU * 3.5 * t)
		carrier_phase = fmod(carrier_phase + freq / RATE, 1.0)
		var carrier := 0.14 * sin(TAU * carrier_phase)
		var env := minf(i / (ATTACK * 2.0), 1.0) * (1.0 - 0.35 * t) * minf((count - i) / (RELEASE * 4.0), 1.0)
		var sample := clampf((band * crackle + carrier) * loudness * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
