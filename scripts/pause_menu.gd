extends Control
## Always-processing pixel UI for pausing and the small set of global settings.
## The game itself is paused through SceneTree, while this node keeps receiving input.

signal title_settings_closed

const W := 480
const H := 270
const FONT := preload("res://ui/pixel_font.fnt")
const ARROW := preload("res://ui/cursor_arrow.png")
const HAND := preload("res://ui/cursor_hand.png")
const SETTINGS_PATH := "user://settings.cfg"

const WHITE := Color(1, 1, 1)
const INK := Color8(14, 5, 5)
const PANEL := Color8(34, 22, 28)
const PANEL_HI := Color8(119, 79, 57)
const TRACK := Color8(68, 49, 52)
const ACCENT := Color8(239, 180, 94)

const PAUSE_BUTTON := Rect2(429, 6, 45, 15)
const MENU := Rect2(108, 19, 264, 232)
const RESUME := Rect2(121, 43, 238, 18)
const MASTER_SLIDER := Rect2(207, 79, 103, 9)
const MUSIC_SLIDER := Rect2(207, 106, 103, 9)
const SFX_SLIDER := Rect2(207, 133, 103, 9)
const BRIGHTNESS_SLIDER := Rect2(207, 160, 103, 9)
const MASTER_MUTE := Rect2(317, 75, 42, 17)
const MUSIC_MUTE := Rect2(317, 102, 42, 17)
const SFX_MUTE := Rect2(317, 129, 42, 17)
const FULLSCREEN := Rect2(121, 184, 238, 18)
const QUIT := Rect2(121, 215, 238, 18)

var is_paused := false
var title_context := false
var pause_button_enabled := true
var dragging := ""
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 0.8
var brightness := 1.0
var master_muted := false
var music_muted := false
var sfx_muted := false
var fullscreen := false

@onready var game_ui: CanvasItem = owner.get_node("UI/Overlay")
@onready var post: ShaderMaterial = owner.get_node("Screen").material


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	_apply_settings()
	z_index = -1


func _process(_delta: float) -> void:
	queue_redraw()


func open_pause() -> void:
	if is_paused or not pause_button_enabled:
		return
	is_paused = true
	title_context = false
	dragging = ""
	z_index = 10
	game_ui.visible = false
	post.set_shader_parameter("pause_amount", 1.0)
	get_tree().paused = true
	queue_redraw()


## Show the same persisted settings from the landing page without freezing its live background.
func open_title_settings() -> void:
	if is_paused:
		return
	is_paused = true
	title_context = true
	dragging = ""
	z_index = 10
	game_ui.visible = false
	post.set_shader_parameter("pause_amount", 1.0)
	queue_redraw()


func resume() -> void:
	if not is_paused:
		return
	if title_context:
		post.set_shader_parameter("pause_amount", 0.0)
		is_paused = false
		title_context = false
		dragging = ""
		z_index = -1
		_save_settings()
		title_settings_closed.emit()
		queue_redraw()
		return
	get_tree().paused = false
	post.set_shader_parameter("pause_amount", 0.0)
	game_ui.visible = true
	is_paused = false
	dragging = ""
	z_index = -1
	_save_settings()
	queue_redraw()


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and is_paused:
		if event.keycode == KEY_ESCAPE:
			resume()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and is_paused:
		if dragging != "":
			_set_slider(dragging, get_local_mouse_position().x)
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if is_paused:
			get_viewport().set_input_as_handled()
		return

	var p := get_local_mouse_position()
	if event.pressed:
		if not is_paused:
			if pause_button_enabled and PAUSE_BUTTON.has_point(p):
				open_pause()
				get_viewport().set_input_as_handled()
			return
		_handle_press(p)
		get_viewport().set_input_as_handled()
	else:
		if is_paused:
			if dragging != "":
				_set_slider(dragging, p.x)
				_save_settings()
			dragging = ""
			get_viewport().set_input_as_handled()


func _handle_press(p: Vector2) -> void:
	if RESUME.has_point(p):
		resume()
		return
	for entry in [
		["master", MASTER_SLIDER],
		["music", MUSIC_SLIDER],
		["sfx", SFX_SLIDER],
		["brightness", BRIGHTNESS_SLIDER],
	]:
		if entry[1].grow(4).has_point(p):
			dragging = entry[0]
			_set_slider(dragging, p.x)
			return
	if MASTER_MUTE.has_point(p):
		master_muted = not master_muted
		_apply_audio()
		_save_settings()
	elif MUSIC_MUTE.has_point(p):
		music_muted = not music_muted
		_apply_audio()
		_save_settings()
	elif SFX_MUTE.has_point(p):
		sfx_muted = not sfx_muted
		_apply_audio()
		_save_settings()
	elif FULLSCREEN.has_point(p):
		fullscreen = not fullscreen
		_apply_fullscreen()
		_save_settings()
	elif not OS.has_feature("web") and QUIT.has_point(p):
		get_tree().paused = false
		get_tree().quit()


func _set_slider(which: String, pointer_x: float) -> void:
	var rect := BRIGHTNESS_SLIDER if which == "brightness" else (
			MASTER_SLIDER if which == "master" else MUSIC_SLIDER if which == "music" else SFX_SLIDER)
	var value := clampf((pointer_x - rect.position.x) / rect.size.x, 0.0, 1.0)
	match which:
		"master":
			master_volume = value
			master_muted = false
			_apply_audio()
		"music":
			music_volume = value
			music_muted = false
			_apply_audio()
		"sfx":
			sfx_volume = value
			sfx_muted = false
			_apply_audio()
		"brightness":
			brightness = lerpf(0.5, 1.5, value)
			_apply_brightness()


func _apply_settings() -> void:
	_apply_audio()
	_apply_brightness()
	_apply_fullscreen()
	post.set_shader_parameter("pause_amount", 0.0)


func _apply_audio() -> void:
	_set_bus("Master", master_volume, master_muted)
	_set_bus("Music", music_volume, music_muted)
	_set_bus("SFX", sfx_volume, sfx_muted)


func _set_bus(bus_name: String, volume: float, muted: bool) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, muted or volume <= 0.001)


func _apply_brightness() -> void:
	post.set_shader_parameter("brightness", brightness)


func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	master_muted = bool(cfg.get_value("audio", "master_muted", master_muted))
	music_muted = bool(cfg.get_value("audio", "music_muted", music_muted))
	sfx_muted = bool(cfg.get_value("audio", "sfx_muted", sfx_muted))
	brightness = clampf(float(cfg.get_value("video", "brightness", brightness)), 0.5, 1.5)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.set_value("audio", "sfx_muted", sfx_muted)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("video", "fullscreen", fullscreen)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))


func _draw() -> void:
	var cur := get_local_mouse_position().floor()
	if not is_paused:
		if pause_button_enabled:
			_button(PAUSE_BUTTON, "PAUSE", PAUSE_BUTTON.has_point(cur))
		return

	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.01, 0.02, 0.34))
	draw_rect(MENU, INK)
	_frame(MENU, WHITE)
	_frame(MENU.grow(-2), PANEL_HI)
	var heading := "SETTINGS" if title_context else "PAUSED"
	text(heading, Vector2(MENU.get_center().x - text_width(heading) / 2.0, 27), ACCENT)
	_button(RESUME, "BACK TO TITLE" if title_context else "RESUME", RESUME.has_point(cur))

	text("MASTER", Vector2(121, 78), WHITE)
	_slider(MASTER_SLIDER, 0.0 if master_muted else master_volume, cur, false)
	_button(MASTER_MUTE, "MUTED" if master_muted else "MUTE",
			MASTER_MUTE.has_point(cur), master_muted)
	text("MUSIC", Vector2(121, 105), WHITE)
	_slider(MUSIC_SLIDER, 0.0 if music_muted else music_volume, cur, false)
	_button(MUSIC_MUTE, "MUTED" if music_muted else "MUTE",
			MUSIC_MUTE.has_point(cur), music_muted)
	text("SFX", Vector2(121, 132), WHITE)
	_slider(SFX_SLIDER, 0.0 if sfx_muted else sfx_volume, cur, false)
	_button(SFX_MUTE, "MUTED" if sfx_muted else "MUTE",
			SFX_MUTE.has_point(cur), sfx_muted)
	text("BRIGHTNESS", Vector2(121, 159), WHITE)
	_slider(BRIGHTNESS_SLIDER, (brightness - 0.5) / 1.0, cur, true)
	_button(FULLSCREEN, "FULLSCREEN: " + ("ON" if fullscreen else "OFF"),
			FULLSCREEN.has_point(cur), fullscreen)
	if not OS.has_feature("web"):
		_button(QUIT, "QUIT TO DESKTOP", QUIT.has_point(cur))

	var hot := _interactive_at(cur)
	var cursor_tex: Texture2D = HAND if hot else ARROW
	draw_texture(cursor_tex, cur - Vector2(3, 2), WHITE)


func _interactive_at(p: Vector2) -> bool:
	if RESUME.has_point(p) or FULLSCREEN.has_point(p):
		return true
	if not OS.has_feature("web") and QUIT.has_point(p):
		return true
	for r in [MASTER_SLIDER, MUSIC_SLIDER, SFX_SLIDER, BRIGHTNESS_SLIDER,
			MASTER_MUTE, MUSIC_MUTE, SFX_MUTE]:
		if r.grow(4).has_point(p):
			return true
	return false


func _slider(rect: Rect2, value: float, cursor: Vector2, default_marker: bool) -> void:
	draw_rect(rect, TRACK)
	_frame(rect, WHITE if rect.grow(4).has_point(cursor) else PANEL_HI)
	var fill := Rect2(rect.position + Vector2(2, 2),
			Vector2((rect.size.x - 4) * value, rect.size.y - 4))
	draw_rect(fill, ACCENT)
	if default_marker:
		var x := rect.position.x + rect.size.x * 0.5
		draw_rect(Rect2(x, rect.position.y - 2, 1, rect.size.y + 4), WHITE)
	var knob_x := rect.position.x + roundf((rect.size.x - 1) * value)
	draw_rect(Rect2(knob_x - 1, rect.position.y - 2, 3, rect.size.y + 4), WHITE)


func _button(rect: Rect2, label: String, hovered: bool, active := false) -> void:
	draw_rect(rect, PANEL_HI if active else PANEL)
	_frame(rect, WHITE if hovered else (ACCENT if active else PANEL_HI))
	var x := rect.get_center().x - text_width(label) / 2.0
	var y := rect.position.y + (rect.size.y - 8.0) / 2.0
	text(label, Vector2(x, y), WHITE, INK)


static func text_width(s: String) -> int:
	return int(FONT.get_string_size(s.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x) - 1


func text(s: String, pos: Vector2, color: Color, shadow = null) -> void:
	var base := pos.floor() + Vector2(0, 7)
	s = s.to_upper()
	if shadow != null:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx != 0 or dy != 0:
					draw_string(FONT, base + Vector2(dx, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, shadow)
	draw_string(FONT, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, color)


func _frame(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1)), color)
	draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1, 0), Vector2(1, rect.size.y)), color)
