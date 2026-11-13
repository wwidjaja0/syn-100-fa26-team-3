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
##   radio_in  a radio transmission starts
##
## Speech: Undertale-style blips standing in for voice acting. Each character in
## data/dialogue.json has a "voice" (see add_voice), and the dialogue box calls speak(id) as
## letters appear. Voices share one player, so each blip cuts off the last, as Undertale's do.

const RATE := 22050
const VOICES := 4                       # sounds that can overlap
const TRIANGLE_STEPS := 8.0             # levels each side of zero in the triangle wave
const SMOOTHING := 0.35                 # 0..1: lower is duller (a one-pole low-pass)
const ATTACK := 90.0                    # samples to fade in over (~4 ms)
const RELEASE := 220.0                  # samples to fade out over (~10 ms)

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _voices := {}                       # character id -> [AudioStreamWAV, ...], one per pitch step
var _speech: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # the pause menu plays these while the game is paused
	_streams = {                                     # [[Hz, seconds], ...], loudness 0..1
		"click": _blip([[440.0, 0.035], [587.0, 0.06]], 0.45),
		"back": _blip([[523.0, 0.035], [392.0, 0.07]], 0.45),
		"pick": _blip([[587.0, 0.03], [784.0, 0.07]], 0.42),
		"tick": _blip([[659.0, 0.025]], 0.26),
		"start": _blip([[392.0, 0.07], [523.0, 0.07], [659.0, 0.07], [784.0, 0.18]], 0.45),
		"radio_in": _blip([[980.0, 0.025], [620.0, 0.03], [840.0, 0.04]], 0.30),
	}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	_speech = AudioStreamPlayer.new()
	_speech.bus = &"SFX"
	add_child(_speech)


func play(sound: String) -> void:
	if not _streams.has(sound):
		push_warning("UiSounds: no sound named '%s'" % sound)
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.play()


## build a character's speech blip. v (all optional):
##   pitch     Hz of the blip (default 220)
##   jitter    semitones the pitch may wander either way, picked per blip (0: one fixed note)
##   wave      "square", "triangle" or "saw"
##   duty      a square wave's high fraction: 0.5 round and full, 0.125 thin and nasal
##   length    seconds per blip
##   noise     0..1 hiss mixed in (radio static)
##   crush     hold every sample this many times: lower fidelity, a crunchy radio speaker
##   loudness  0..1
func add_voice(id: String, v: Dictionary) -> void:
	var jitter := int(v.get("jitter", 0))
	var pitch: float = v.get("pitch", 220.0)
	var steps: Array[AudioStreamWAV] = []
	for semis in range(-jitter, jitter + 1):
		steps.append(_voice_blip(pitch * pow(2.0, semis / 12.0), v))
	_voices[id] = steps


func has_voice(id: String) -> bool:
	return _voices.has(id)


## one blip of a character's voice
func speak(id: String) -> void:
	if not _voices.has(id):
		return
	_speech.stream = _voices[id].pick_random()
	_speech.play()


func _voice_blip(freq: float, v: Dictionary) -> AudioStreamWAV:
	var wave: String = v.get("wave", "square")
	var duty: float = v.get("duty", 0.5)
	var noise: float = v.get("noise", 0.0)
	var crush := maxi(int(v.get("crush", 1)), 1)
	var loudness: float = v.get("loudness", 0.2)
	var count := int(float(v.get("length", 0.04)) * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	var smooth := 0.0
	var held := 0.0
	for i in count:
		phase = fmod(phase + freq / RATE, 1.0)
		var s: float
		match wave:
			"triangle":
				s = roundf((1.0 - 4.0 * absf(phase - 0.5)) * TRIANGLE_STEPS) / TRIANGLE_STEPS
			"saw":
				s = 2.0 * phase - 1.0
			_:
				s = 1.0 if phase < duty else -1.0
		s = lerpf(s, randf_range(-1.0, 1.0), noise)
		smooth = lerpf(smooth, s, 0.5)
		if i % crush == 0:
			held = smooth
		var t := float(i) / count
		var envelope := minf(i / ATTACK, 1.0) * (1.0 - 0.5 * t) * minf((count - i) / RELEASE, 1.0)
		data.encode_s16(i * 2, int(held * loudness * envelope * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


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
