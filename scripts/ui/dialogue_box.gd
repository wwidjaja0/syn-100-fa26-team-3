extends RefCounted
## Stardew Valley-inspired bottom dialogue box for Ouroboros' Cabin.
##
## Supports internal monologue and radio transmissions with character-by-character
## typewriter animation, synthesized sound blips, speaker headers, and a random
## radio chatter scheduler.
##
## Owned, updated, and drawn by overlay.gd.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const UiSoundsAutoload := preload("res://scripts/ui/ui_sounds.gd")

const BOX := Rect2(36, 178, 408, 62)
const TITLE_H := 14
const TEXT_INSET := Vector2(8, 4)
const MAX_TEXT_WIDTH := 390
const LINE_SPACING := 9

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
var speaker := ""
var lines: Array = []
var current_line_idx := 0

var _dialogue_data: Dictionary = {}
var _radio_chatter_pool: Array = []
var _ambient_shuffle_bag: Array = []

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
var _pending_radio: Dictionary = {}
var _current_entry: Dictionary = {}

var _overlay: Control
var _palette: Array
var _accent: Color
var _radio_accent: Color
var _panel_col: Color
var _panel_hi: Color
var _panel_lo: Color


func _init(overlay: Control, palette: Array) -> void:
	_overlay = overlay
	_palette = palette
	_accent = Px.palette_color(palette, Color8(239, 180, 94))
	_radio_accent = Px.palette_color(palette, Color8(121, 183, 196))
	_panel_col = Px.palette_color(palette, Color(0.09, 0.06, 0.08))
	_panel_hi = Px.palette_color(palette, Color(0.36, 0.24, 0.17))
	_panel_lo = Px.palette_color(palette, Color(0.03, 0.02, 0.03))
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


func has_pending_radio() -> bool:
	return GameState.flag("radio_fixed") and not _pending_radio.is_empty()


func is_radio_lit() -> bool:
	return GameState.flag("radio_fixed") and (not _pending_radio.is_empty() or is_radio_talking())


func start(id: String) -> bool:
	if _dialogue_data.has(id):
		return start_entry(_dialogue_data[id], id)
	for item in _radio_chatter_pool:
		if item.get("id", "") == id:
			return start_entry(item, id)
	push_warning("DialogueBox: unknown dialogue id '%s'" % id)
	return false


func start_entry(entry: Dictionary, id := "") -> bool:
	var entry_style: String = entry.get("style", "monologue")
	if entry_style == "radio" and not GameState.flag("radio_fixed"):
		return false

	var seen_flag: String = entry.get("once_flag", "")
	if seen_flag == "" and entry_style == "monologue" and not entry.get("repeatable", false) and id != "":
		seen_flag = "dlg_seen_" + id
	if seen_flag != "":
		if GameState.flag(seen_flag):
			return false
		GameState.set_flag(seen_flag)

	active = true
	closing = false
	_current_entry = entry.duplicate()
	if id != "" and not _current_entry.has("id"):
		_current_entry["id"] = id
	_start_clock = _overlay.main.clock
	style = entry_style
	speaker = entry.get("speaker", "INTERNAL MONOLOGUE")
	lines = entry.get("lines", []).duplicate()
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
		_current_entry = {}
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
			if style == "radio" and not _current_entry.is_empty():
				GameState.add_radio_log(_current_entry)
				_current_entry = {}
			close()
		else:
			_chars_shown = 0.0
			_pause_frames = 0.0
			_sound_counter = 0
			UiSounds.play("click")


func _pick_next_radio_entry() -> Dictionary:
	if not GameState.flag("radio_fixed") or _radio_chatter_pool.is_empty():
		return {}

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

	return chosen


func arm_incoming_radio(_clock: float) -> bool:
	if not GameState.flag("radio_fixed") or _radio_chatter_pool.is_empty():
		return false
	if not _pending_radio.is_empty():
		UiSounds.play("radio_static")
		return true
	var chosen := _pick_next_radio_entry()
	if chosen.is_empty():
		return false
	_pending_radio = chosen
	UiSounds.play("radio_static")
	return true


func answer_pending_radio(clock: float) -> bool:
	if not has_pending_radio():
		return false
	var entry := _pending_radio
	_pending_radio = {}
	var ok := start_entry(entry)
	_next_chatter_clock = clock + randf_range(CHATTER_MIN_FRAMES, CHATTER_MAX_FRAMES)
	return ok


func trigger_random_radio(clock: float) -> bool:
	var chosen := _pick_next_radio_entry()
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
		_pending_radio = {}
	elif _chatter_armed and _pending_radio.is_empty() and not active and clock >= _next_chatter_clock:
		if not _overlay.main.landing_active and not _overlay.main.suppress_auto_dialogue:
			arm_incoming_radio(clock)

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

			for i in range(old_idx, new_idx):
				var ch := current_text[i]
				if ch != " ":
					_sound_counter += 1
					if _sound_counter % 2 == 0:
						UiSounds.play("type_radio" if style == "radio" else "type_mono")
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
	var r := Rect2(BOX.position.x, y, BOX.size.x, h)

	# Main background and frame
	_overlay.draw_rect(r, _panel_col)
	Px.frame(_overlay, r, _panel_hi)
	Px.frame(_overlay, r.grow(1), Px.INK)

	if scale_factor < 1.0:
		return

	# Header bar
	var header_r := Rect2(r.position.x, r.position.y, r.size.x, TITLE_H)
	_overlay.draw_rect(header_r, _panel_lo)
	Px.frame(_overlay, header_r, _panel_hi)
	_overlay.draw_rect(Rect2(r.position.x + 1, r.position.y + TITLE_H - 1, r.size.x - 2, 1), _panel_hi)

	var header_col: Color = _radio_accent if style == "radio" else _accent

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
		var wrapped_full := _wrap_text(full_line, MAX_TEXT_WIDTH)
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
