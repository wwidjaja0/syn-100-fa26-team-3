extends Control
## The pause / settings menu (UI/PauseMenu), and the PAUSE button in the top-right corner.
##
## One panel, opened two ways:
##   * open_pause()            in the game: Esc from the room, or the PAUSE button. Headed PAUSED;
##                             the game is paused through the SceneTree while it is up.
##   * open_title_settings()   from the title screen's SETTINGS. Headed SETTINGS; the live
##                             background keeps running, and there are no quit buttons (the
##                             title screen has one).
## The in-game menu also has QUIT TO TITLE (asks once more, then starts a new game at the title
## screen: nothing is saved yet) and, off the web, QUIT TO DESKTOP.
## The X in the top-right corner (or Esc) closes it: resume() goes back to the game or the title.
## Settings (volumes, mutes, brightness, fullscreen) are saved to user://settings.cfg.
##
## This node keeps processing while the tree is paused, and takes all input while it is open.
## It is drawn with menu_draw.gd so it matches start_menu.gd and the microfiche panel.

signal title_settings_closed

const Px := preload("res://scripts/ui/pixel_draw.gd")
const Menu := preload("res://scripts/ui/menu_draw.gd")
const SETTINGS_PATH := "user://settings.cfg"

const PAUSE_BUTTON := Rect2(429, 6, 45, 15)
const MENU_W := 264.0
const ROW := 27.0                       # px between the slider rows
const SLIDERS := ["master", "music", "sfx", "brightness"]
const MUTABLE := ["master", "music", "sfx"]

var is_paused := false                  # the panel is open (in either context)
var title_context := false              # opened from the title screen
var pause_button_enabled := true
var dragging := ""                      # the slider being dragged, or ""
var volume := {"master": 1.0, "music": 0.8, "sfx": 0.8}
var muted := {"master": false, "music": false, "sfx": false}
var brightness := 1.0                   # 0.5 .. 1.5
var fullscreen := false

var _menu: Rect2                        # the panel; the rects below are laid out inside it
var _slider := {}                       # name -> Rect2
var _mute := {}                         # name -> Rect2
var _fullscreen: Rect2
var _to_title: Rect2
var _quit: Rect2
var _confirm_title := false             # QUIT TO TITLE was pressed once; again does it

@onready var game_ui: CanvasItem = owner.get_node("UI/Overlay")
@onready var post: ShaderMaterial = owner.get_node("Screen").material


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Menu.load_style()
	_load_settings()
	_apply_audio()
	_apply_brightness()
	if fullscreen:                       # leave the window alone unless the player asked for fullscreen
		_apply_fullscreen()
	post.set_shader_parameter("pause_amount", 0.0)
	_layout()
	z_index = -1


func _process(_delta: float) -> void:
	queue_redraw()


# ---------------------------------------------------------------- open / close
func open_pause() -> void:
	if is_paused or not pause_button_enabled:
		return
	_open(false)
	get_tree().paused = true


## the same settings from the title screen, without freezing its live background
func open_title_settings() -> void:
	if is_paused:
		return
	_open(true)


func _open(from_title: bool) -> void:
	is_paused = true
	title_context = from_title
	dragging = ""
	_confirm_title = false
	_layout()
	z_index = 10
	game_ui.visible = false
	post.set_shader_parameter("pause_amount", 1.0)
	queue_redraw()


## close the panel: back to the game, or to the title screen
func resume() -> void:
	if not is_paused:
		return
	post.set_shader_parameter("pause_amount", 0.0)
	is_paused = false
	dragging = ""
	z_index = -1
	_save_settings()
	if title_context:
		title_context = false
		title_settings_closed.emit()
	else:
		get_tree().paused = false
		game_ui.visible = true
	queue_redraw()


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false


## QUIT TO DESKTOP is only in the in-game pause menu, and never on the web
func _has_quit() -> bool:
	return not title_context and not OS.has_feature("web")


## Back to the title screen as a new game. Nothing is saved yet, so this resets the story state
## and the inventory, and reloads the scene (which resets the room and brings the title back).
func quit_to_title() -> void:
	_save_settings()
	GameState.reset()
	InventoryManager.clear()
	get_tree().paused = false
	get_tree().reload_current_scene()


## place the panel's parts; it is shorter without the quit buttons
func _layout() -> void:
	var h := 160.0 if title_context else (212.0 if _has_quit() else 186.0)
	_menu = Rect2((Px.W - MENU_W) / 2.0, floorf((Px.H - h) / 2.0), MENU_W, h)
	var x := _menu.position.x
	var y := _menu.position.y
	for i in SLIDERS.size():
		_slider[SLIDERS[i]] = Rect2(x + 99, y + 28 + i * ROW, 103, 9)
	for i in MUTABLE.size():
		_mute[MUTABLE[i]] = Rect2(x + 209, y + 24 + i * ROW, 42, 17)
	_fullscreen = Rect2(x + 13, y + 132, 238, 18)
	_to_title = Rect2(x + 13, y + 158, 238, 18)
	_quit = Rect2(x + 13, y + 184, 238, 18)


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and is_paused:
		if event.keycode == KEY_ESCAPE:
			UiSounds.play("back")
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
				UiSounds.play("click")
				open_pause()
				get_viewport().set_input_as_handled()
			return
		_handle_press(p)
		get_viewport().set_input_as_handled()
	elif is_paused:
		if dragging != "":
			_set_slider(dragging, p.x)
			_save_settings()
		dragging = ""
		get_viewport().set_input_as_handled()


func _handle_press(p: Vector2) -> void:
	var at := _hot_at(p)
	if at != "to_title":
		_confirm_title = false
	if at == "":
		return
	if at == "close":
		UiSounds.play("back")
		resume()
	elif at in SLIDERS:
		dragging = at
		_set_slider(at, p.x)
	elif at.begins_with("mute_"):
		var which := at.trim_prefix("mute_")
		muted[which] = not muted[which]
		UiSounds.play("click")
		_apply_audio()
		_save_settings()
	elif at == "fullscreen":
		UiSounds.play("click")
		fullscreen = not fullscreen
		_apply_fullscreen()
		_save_settings()
	elif at == "to_title":
		UiSounds.play("click")
		if _confirm_title:
			quit_to_title()
		_confirm_title = true
	elif at == "quit":
		get_tree().paused = false
		get_tree().quit()


## the name of the control under p: "close", a slider's name, "mute_<name>", "fullscreen",
## "to_title", "quit", "pause" (the corner button), or ""
func _hot_at(p: Vector2) -> String:
	if not is_paused:
		return "pause" if pause_button_enabled and visible and PAUSE_BUTTON.has_point(p) else ""
	if Menu.close_rect(_menu).has_point(p):
		return "close"
	for s in SLIDERS:
		if _slider[s].grow(4).has_point(p):
			return s
	for m in MUTABLE:
		if _mute[m].has_point(p):
			return "mute_" + m
	if _fullscreen.has_point(p) and _can_fullscreen():
		return "fullscreen"
	if not title_context and _to_title.has_point(p):
		return "to_title"
	if _has_quit() and _quit.has_point(p):
		return "quit"
	return ""


func _set_slider(which: String, pointer_x: float) -> void:
	var rect: Rect2 = _slider[which]
	var value := clampf((pointer_x - rect.position.x) / rect.size.x, 0.0, 1.0)
	var before := _slider_value(which)
	if which == "brightness":
		brightness = lerpf(0.5, 1.5, value)
		_apply_brightness()
	else:
		volume[which] = value
		muted[which] = false
		_apply_audio()
	if int(before * 20.0) != int(value * 20.0):      # a tick every 5 %
		UiSounds.play("tick")


func _slider_value(which: String) -> float:
	if which == "brightness":
		return brightness - 0.5
	return 0.0 if muted[which] else volume[which]


# ---------------------------------------------------------------- settings
func _apply_audio() -> void:
	_set_bus("Master", volume.master, muted.master)
	_set_bus("Music", volume.music, muted.music)
	_set_bus("SFX", volume.sfx, muted.sfx)


func _set_bus(bus_name: String, level: float, mute: bool) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(level, 0.0001)))
	AudioServer.set_bus_mute(bus, mute or level <= 0.001)


func _apply_brightness() -> void:
	post.set_shader_parameter("brightness", brightness)


## False when the game runs inside the Godot editor's Game tab ("Embed Game on Next Play"):
## an embedded game has no window of its own to make fullscreen. Run it floating, or exported.
func _can_fullscreen() -> bool:
	return not Engine.is_embedded_in_editor()


func _apply_fullscreen() -> void:
	if not _can_fullscreen():
		return
	get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		fullscreen = get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
		return
	for k in volume:
		volume[k] = clampf(float(cfg.get_value("audio", k, volume[k])), 0.0, 1.0)
		muted[k] = bool(cfg.get_value("audio", k + "_muted", muted[k]))
	brightness = clampf(float(cfg.get_value("video", "brightness", brightness)), 0.5, 1.5)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in volume:
		cfg.set_value("audio", k, volume[k])
		cfg.set_value("audio", k + "_muted", muted[k])
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("video", "fullscreen", fullscreen)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var cur := get_local_mouse_position().floor()
	var hot := _hot_at(cur)
	if not is_paused:
		if pause_button_enabled:
			Menu.button(self, PAUSE_BUTTON, "PAUSE", hot == "pause")
		return

	draw_rect(Rect2(0, 0, Px.W, Px.H), Color(0.02, 0.01, 0.02, 0.34))
	Menu.panel(self, _menu, "SETTINGS" if title_context else "PAUSED", hot == "close")
	for s in SLIDERS:
		var r: Rect2 = _slider[s]
		Px.text(self, s, Vector2(_menu.position.x + 13, r.position.y), Px.WHITE)
		_draw_slider(r, _slider_value(s), hot == s or dragging == s, s == "brightness")
	for m in MUTABLE:
		Menu.button(self, _mute[m], "MUTED" if muted[m] else "MUTE", hot == "mute_" + m, muted[m])
	if _can_fullscreen():
		Menu.button(self, _fullscreen, "FULLSCREEN: " + ("ON" if fullscreen else "OFF"),
				hot == "fullscreen", fullscreen)
	else:
		Menu.button(self, _fullscreen, "FULLSCREEN: NOT IN EDITOR VIEW", false, false, false)
	if not title_context:
		Menu.button(self, _to_title, "SURE? PROGRESS WILL BE LOST" if _confirm_title else "QUIT TO TITLE",
				hot == "to_title", _confirm_title)
	if _has_quit():
		Menu.button(self, _quit, "QUIT TO DESKTOP", hot == "quit")
	Menu.cursor(self, cur, hot != "")


func _draw_slider(rect: Rect2, value: float, hot: bool, centre_mark: bool) -> void:
	draw_rect(rect, Menu.panel_lo)
	Px.frame(self, rect, Px.WHITE if hot else Menu.panel_hi)
	draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2((rect.size.x - 4) * value, rect.size.y - 4)),
			Menu.accent)
	if centre_mark:                      # brightness: the default sits in the middle
		draw_rect(Rect2(rect.position.x + floorf(rect.size.x * 0.5), rect.position.y - 2, 1, rect.size.y + 4),
				Px.WHITE)
	var knob_x := rect.position.x + roundf((rect.size.x - 1) * value)
	draw_rect(Rect2(knob_x - 1, rect.position.y - 2, 3, rect.size.y + 4), Px.WHITE)
