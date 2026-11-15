extends RefCounted
## Stardew Valley-inspired bottom dialogue box for Ouroboros' Cabin.
##
## Supports internal monologue and radio transmissions with character-by-character
## typewriter animation, speaker portraits, per-character voice blips, speaker headers, and a
## random radio chatter scheduler.
##
## Portraits: the player ("you") sits on the left; whoever else speaks in the entry sits on the
## right, so a transmission reads as someone talking to you. The one speaking moves their mouth
## with their voice; the other is dimmed. Characters, their names and voices are in
## data/dialogue.json "characters"; their portraits in portraits.gd.
##
## A line is a string (said by the entry's "character", the player by default) or
## {"who": character id, "text": "..."}, so one entry can go back and forth between speakers.
##
## Owned, updated, and drawn by overlay.gd.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const Portraits := preload("res://scripts/ui/portraits.gd")

const BOX := Rect2(36, 178, 408, 62)    # the whole strip: portrait frames at each end, text between
const PLAYER := "you"
const PORTRAIT := 62                    # the square portrait frames
const PORTRAIT_GAP := 4
const ART_SCALE := 2                    # portraits.gd's 28x28 maps, drawn 2x
const NAME_H := 11
const TITLE_H := 14
const TEXT_INSET := Vector2(8, 4)
const LINE_SPACING := 9

const VOICE_EVERY := 2                  # a blip every this many letters, unless the voice says
const MOUTH_FRAMES := 2.0               # how long a blip holds the mouth open
const BLINK_EVERY := 84.0               # frames between a speaker's blinks
const BLINK_FRAMES := 3.0
const SCANLINE_EVERY := 4               # a transmission's portrait: one dark row in this many

const CHARS_PER_FRAME := 1.35            # ~32 characters per second at 24 fps
const PUNCTUATION_PAUSE := 4.0          # frames to pause on . , ! ? : -
const OPEN_FRAMES := 5.0
const CLOSE_FRAMES := 3.0

const CHATTER_MIN_FRAMES := 480.0       # 20 seconds at 24 fps
const CHATTER_MAX_FRAMES := 1080.0      # 45 seconds at 24 fps
const CHATTER_FIRST_MIN := 240.0        # 10 seconds
const CHATTER_FIRST_MAX := 432.0        # 18 seconds

var active := false
var closing := false
var style := "monologue"                # "monologue" or "radio"
var speaker := ""                       # the header: who or what the box is showing
var lines: Array = []
var line_who: Array = []                # the character id saying each line
var current_line_idx := 0

var _dialogue_data: Dictionary = {}
var _radio_chatter_pool: Array = []
var _ambient_shuffle_bag: Array = []
var _characters: Dictionary = {}
var _portraits: Dictionary = {}         # character id -> portraits.gd frames, built on first use
var _right := ""                        # the character in the right-hand frame ("" for none)
var _mouth_until := -1e9

var _chars_shown := 0.0
var _pause_frames := 0.0
var _sound_counter := 0
var _open_t := 0.0
var _closed_t := 0.0
var _start_clock := 0.0
var _close_clock := 0.0

var _next_chatter_clock := 999999.0
var _chatter_armed := false
var _first_chatter_done := false

var _overlay: Control
var _palette: Array
var _accent: Color
var _radio_accent: Color
var _panel_col: Color
var _panel_hi: Color
var _panel_lo: Color
var _scan_col: Color


func _init(overlay: Control, palette: Array) -> void:
	_overlay = overlay
	_palette = palette
	_accent = Px.palette_color(palette, Color8(239, 180, 94))
	_radio_accent = Px.palette_color(palette, Color8(121, 183, 196))
	_panel_col = Px.palette_color(palette, Color(0.09, 0.06, 0.08))
	_panel_hi = Px.palette_color(palette, Color(0.36, 0.24, 0.17))
	_panel_lo = Px.palette_color(palette, Color(0.03, 0.02, 0.03))
	_scan_col = Px.palette_color(palette, Color8(30, 80, 102))
	_load_data()


func _load_data() -> void:
	var path := "res://data/dialogue.json"
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_dialogue_data = parsed.get("dialogues", {})
		_radio_chatter_pool = parsed.get("radio_chatter", [])
		_characters = parsed.get("characters", {})
		for id: String in _characters:
			if _characters[id].has("voice"):
				UiSounds.add_voice(id, _characters[id].voice)


func arm_radio_chatter(clock: float, fast_first := false) -> void:
	if not GameState.flag("radio_fixed"):
		return
	_chatter_armed = true
	if fast_first and not _first_chatter_done:
		_next_chatter_clock = clock + randf_range(CHATTER_FIRST_MIN, CHATTER_FIRST_MAX)
	else:
		_next_chatter_clock = clock + randf_range(CHATTER_MIN_FRAMES, CHATTER_MAX_FRAMES)


func is_active() -> bool:
	return active


func is_radio_talking() -> bool:
	return active and not closing and style == "radio"


## the character id saying the current line ("" when the box is shut)
func speaking() -> String:
	if not active or current_line_idx >= line_who.size():
		return ""
	return line_who[current_line_idx]


## letters and digits make a voice blip; spaces and punctuation are silent, as in Undertale
func _voiced(ch: String) -> bool:
	var c := ch.unicode_at(0)
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57)


func start(id: String) -> bool:
	if _dialogue_data.has(id):
		return start_entry(_dialogue_data[id], id)
	for item in _radio_chatter_pool:
		if item.get("id", "") == id:
			return start_entry(item, id)
	push_warning("DialogueBox: unknown dialogue id '%s'" % id)
	return false


func start_entry(entry: Dictionary, _id := "") -> bool:
	if entry.get("style", "monologue") == "radio" and not GameState.flag("radio_fixed"):
		return false
	if entry.has("once_flag") and GameState.flag(entry.once_flag):
		return false
	if entry.has("once_flag"):
		GameState.set_flag(entry.once_flag)

	active = true
	closing = false
	_start_clock = _overlay.main.clock
	style = entry.get("style", "monologue")
	speaker = entry.get("speaker", "INTERNAL MONOLOGUE")
	var said_by: String = entry.get("character", PLAYER)
	lines = []
	line_who = []
	for line in entry.get("lines", []):
		if line is Dictionary:
			lines.append(line.get("text", ""))
			line_who.append(line.get("who", said_by))
		else:
			lines.append(str(line))
			line_who.append(said_by)
	_right = ""
	for who: String in line_who:
		if who != PLAYER:
			_right = who
			break
	_mouth_until = -1e9
	current_line_idx = 0
	_chars_shown = 0.0
	_pause_frames = 0.0
	_sound_counter = 0

	if style == "radio":
		UiSounds.play("radio_in")

	return true


func close() -> void:
	if active and not closing:
		closing = true
		_close_clock = _overlay.main.clock
		UiSounds.play("back")


func skip_or_advance() -> void:
	if not active or closing:
		return
	if current_line_idx >= lines.size():
		close()
		return

	var current_text: String = lines[current_line_idx]
	if _chars_shown < current_text.length():
		# finish current line immediately
		_chars_shown = float(current_text.length())
		_pause_frames = 0.0
		UiSounds.play("tick")
	else:
		# advance to next line
		current_line_idx += 1
		if current_line_idx >= lines.size():
			close()
		else:
			_chars_shown = 0.0
			_pause_frames = 0.0
			_sound_counter = 0
			UiSounds.play("click")


func trigger_random_radio(clock: float) -> bool:
	if not GameState.flag("radio_fixed") or _radio_chatter_pool.is_empty():
		return false

	# 1. Check priority (unseen story messages)
	var unseen_priority: Array = []
	var ambient: Array = []
	for item in _radio_chatter_pool:
		if item.get("priority", false):
			var flag: String = item.get("once_flag", "")
			if flag == "" or not GameState.flag(flag):
				unseen_priority.append(item)
		else:
			ambient.append(item)

	var chosen: Dictionary = {}
	if not unseen_priority.is_empty() and (not _first_chatter_done or randf() < 0.75):
		chosen = unseen_priority[0]
		_first_chatter_done = true
	elif not ambient.is_empty():
		if _ambient_shuffle_bag.is_empty():
			_ambient_shuffle_bag = ambient.duplicate()
			_ambient_shuffle_bag.shuffle()
		chosen = _ambient_shuffle_bag.pop_back()
	elif not unseen_priority.is_empty():
		chosen = unseen_priority[0]
		_first_chatter_done = true

	if chosen.is_empty():
		return false

	var ok := start_entry(chosen)
	_next_chatter_clock = clock + randf_range(CHATTER_MIN_FRAMES, CHATTER_MAX_FRAMES)
	return ok


func update(clock: float, step: float) -> void:
	# Random radio chatter check (only when the radio has been repaired)
	if not GameState.flag("radio_fixed"):
		_chatter_armed = false
		_first_chatter_done = false
	elif _chatter_armed and clock >= _next_chatter_clock:
		var can_chatter: bool = not active and _overlay.panel == "" and _overlay.main.active_view() == null \
				and not _overlay.main.landing_active and not _overlay.main.debug_menu.open \
				and _overlay.inventory.held == null and not _overlay.main.room_camera.panning()
		if can_chatter:
			trigger_random_radio(clock)

	if not active:
		return

	if closing:
		var close_progress := (clock - _close_clock) / CLOSE_FRAMES
		if close_progress >= 1.0:
			active = false
			closing = false
			current_line_idx = 0
			lines.clear()
		return

	if current_line_idx >= lines.size():
		close()
		return

	var current_text: String = lines[current_line_idx]
	if _chars_shown < current_text.length():
		if _pause_frames > 0.0:
			_pause_frames -= step
		else:
			var old_idx := int(_chars_shown)
			_chars_shown += CHARS_PER_FRAME * (step / 1.0)
			var new_idx := mini(int(_chars_shown), current_text.length())

			var who := speaking()
			var every := maxi(int(_characters.get(who, {}).get("voice", {}).get("every", VOICE_EVERY)), 1)
			for i in range(old_idx, new_idx):
				var ch := current_text[i]
				if _voiced(ch):
					_sound_counter += 1
					if (_sound_counter - 1) % every == 0:
						UiSounds.speak(who)
						_mouth_until = clock + MOUTH_FRAMES
				if ch in [".", ",", "!", "?", ":", "-"]:
					_pause_frames = PUNCTUATION_PAUSE
					break


# ---------------------------------------------------------------- drawing
func draw(now: float, cur: Vector2) -> void:
	if not active:
		return

	var scale_factor := 1.0
	if closing:
		scale_factor = clampf(1.0 - (now - _close_clock) / CLOSE_FRAMES, 0.0, 1.0)
	else:
		scale_factor = clampf((now - _start_clock) / OPEN_FRAMES, 0.0, 1.0)

	if scale_factor <= 0.0:
		return

	# Height grows from center
	var full_h := BOX.size.y
	var h := full_h * scale_factor
	var y := BOX.position.y + (full_h - h) * 0.5
	var left_r := Rect2(BOX.position.x, y, PORTRAIT, h)
	var right_r := Rect2(BOX.end.x - PORTRAIT, y, PORTRAIT, h)
	var text_x := left_r.end.x + PORTRAIT_GAP
	var text_end := right_r.position.x - PORTRAIT_GAP if _right != "" else BOX.end.x
	var r := Rect2(text_x, y, text_end - text_x, h)

	# Main background and frame
	_overlay.draw_rect(r, _panel_col)
	Px.frame(_overlay, r, _panel_hi)
	Px.frame(_overlay, r.grow(1), Px.INK)

	var header_col: Color = _radio_accent if style == "radio" else _accent
	_draw_portrait(left_r, PLAYER, now, scale_factor >= 1.0, header_col)
	if _right != "":
		_draw_portrait(right_r, _right, now, scale_factor >= 1.0, header_col)

	if scale_factor < 1.0:
		return

	# Header bar
	var header_r := Rect2(r.position.x, r.position.y, r.size.x, TITLE_H)
	_overlay.draw_rect(header_r, _panel_lo)
	Px.frame(_overlay, header_r, _panel_hi)
	_overlay.draw_rect(Rect2(r.position.x + 1, r.position.y + TITLE_H - 1, r.size.x - 2, 1), _panel_hi)

	# Draw header badge/icon
	var badge_x := r.position.x + 8
	var badge_y := r.position.y + 4
	if style == "radio":
		# Animated 5-bar signal equalizer
		for b in 5:
			var wave := 2.0
			if _chars_shown < lines[current_line_idx].length() if current_line_idx < lines.size() else false:
				wave = 1.0 + 3.0 * (0.5 + 0.5 * sin(now * 0.45 + b * 1.3))
			var bx := badge_x + b * 3
			var by := badge_y + 6 - int(wave)
			_overlay.draw_rect(Rect2(bx, by, 2, int(wave) + 1), header_col)
		badge_x += 18
	else:
		# Monologue thought dots: 3 small roundish dots
		_overlay.draw_rect(Rect2(badge_x, badge_y + 4, 2, 2), header_col)
		_overlay.draw_rect(Rect2(badge_x + 4, badge_y + 3, 2, 2), header_col)
		_overlay.draw_rect(Rect2(badge_x + 8, badge_y + 2, 3, 3), header_col)
		badge_x += 15

	Px.text(_overlay, speaker, Vector2(badge_x, r.position.y + 4), header_col, Px.INK)

	# Page counter top right (e.g. "1/3")
	if lines.size() > 1:
		var counter_text := "%d/%d" % [mini(current_line_idx + 1, lines.size()), lines.size()]
		var cx := r.end.x - Px.text_width(counter_text) - 8
		Px.text(_overlay, counter_text, Vector2(cx, r.position.y + 4), _panel_hi)

	# Text area
	if current_line_idx < lines.size():
		var full_line: String = lines[current_line_idx]
		var shown_count := mini(int(_chars_shown), full_line.length())
		var visible_text := full_line.substr(0, shown_count)

		# Wrap the full line to calculate fixed row positions so text doesn't jump
		var wrapped_full := _wrap_text(full_line, int(r.size.x - TEXT_INSET.x * 2 - 2))
		var text_top := r.position.y + TITLE_H + TEXT_INSET.y
		var text_left := r.position.x + TEXT_INSET.x

		var chars_left := shown_count
		for row_idx in wrapped_full.size():
			if chars_left <= 0:
				break
			var row_str: String = wrapped_full[row_idx]
			var row_take := mini(chars_left, row_str.length())
			var slice := row_str.substr(0, row_take)
			Px.text(_overlay, slice, Vector2(text_left, text_top + row_idx * LINE_SPACING), Px.WHITE, Px.INK)
			chars_left -= row_str.length()
			if chars_left > 0 and row_idx < wrapped_full.size() - 1:
				chars_left -= 1 # space

		# Continue prompt arrow when line is fully displayed
		if shown_count >= full_line.length():
			var bob := int(fmod(now / 4.0, 2.0))
			var arrow_x := r.end.x - 12
			var arrow_y := r.end.y - 10 + bob
			for dy in 3:
				_overlay.draw_rect(Rect2(arrow_x - dy, arrow_y + dy, dy * 2 + 1, 1), header_col)


## a portrait frame: the character's face (once the box has opened) and a name plate. The one
## speaking is lit, blinks now and then, and opens their mouth on each voice blip; the other is
## dimmed. Someone heard over the radio gets scanlines and a rolling bar across their face.
func _draw_portrait(r: Rect2, id: String, now: float, opened: bool, accent: Color) -> void:
	_overlay.draw_rect(r, _panel_lo)
	Px.frame(_overlay, r, _panel_hi)
	Px.frame(_overlay, r.grow(1), Px.INK)
	if not opened:
		return

	var talking := id == speaking() and not closing
	var frames := _portrait(id)
	var size := Vector2.ONE * Portraits.SIZE * ART_SCALE
	var art := Rect2((r.position + (r.size - size) / 2.0).floor(), size)
	if not frames.is_empty():
		var tex: Texture2D = frames.dim
		if talking:
			tex = frames.talk if now < _mouth_until else frames.idle
			if fmod(now + id.hash() % 40, BLINK_EVERY) < BLINK_FRAMES:
				tex = frames.blink
		_overlay.draw_texture_rect(tex, art, false)
		if style == "radio" and id != PLAYER:
			for row in range(0, int(size.y), SCANLINE_EVERY):
				_overlay.draw_rect(Rect2(art.position.x, art.position.y + row, size.x, 1), _panel_lo)
			if talking:
				var bar := fmod(now * 1.5, size.y)
				_overlay.draw_rect(Rect2(art.position.x, art.position.y + floorf(bar), size.x, 1), _scan_col)
	Px.frame(_overlay, art.grow(1), _panel_hi)

	var name: String = _characters.get(id, {}).get("name", id.to_upper())
	var plate_w := Px.text_width(name) + 8
	var plate := Rect2(floorf(r.get_center().x - plate_w / 2.0), r.end.y - NAME_H - 1, plate_w, NAME_H)
	_overlay.draw_rect(plate, _panel_col)
	Px.frame(_overlay, plate, accent if talking else _panel_hi)
	Px.text(_overlay, name, plate.position + Vector2(4, 2), Px.WHITE if talking else Px.GREY)


func _portrait(id: String) -> Dictionary:
	if not _portraits.has(id):
		_portraits[id] = Portraits.build(id, _characters.get(id, {}).get("portrait", ""), _palette)
	return _portraits[id]


func _wrap_text(text: String, max_width: int) -> Array[String]:
	var words := text.split(" ")
	var result: Array[String] = []
	var cur := ""
	for w in words:
		if w.is_empty():
			continue
		var test := cur + (" " if cur != "" else "") + w
		if Px.text_width(test) <= max_width:
			cur = test
		else:
			if cur != "":
				result.append(cur)
			cur = w
	if cur != "":
		result.append(cur)
	return result
