extends Control
## The title screen (UI/StartMenu). The cabin keeps rendering behind it, but main.gd ignores
## gameplay input (main.landing_active) until START GAME calls main.start_game().
##
## Two pages:
##   "main"   the title and its buttons: START GAME, SETTINGS (opens pause_menu.gd's panel),
##            HOW TO PLAY, and QUIT TO DESKTOP (not on the web). Mouse, or Up / Down + Enter.
##   "how"    HOW TO PLAY, drawn by how_to_play.gd (also used by the pause menu and a new game).
## Panels are drawn with menu_draw.gd (title top-left, X top-right), like pause_menu.gd and the
## microfiche. Esc, Enter or the X closes the how-to-play page.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const Menu := preload("res://scripts/ui/menu_draw.gd")
const HowTo := preload("res://scripts/ui/how_to_play.gd")
const FONT := Px.FONT
const W := Px.W
const H := Px.H
const TITLE_SIZE := 14                  # the title is the 5x7 font at 2x

const BUTTON_RECTS := [
	Rect2(145, 105, 190, 19),
	Rect2(145, 131, 190, 19),
	Rect2(145, 157, 190, 19),
	Rect2(145, 183, 190, 19),
]

var active := true                      # the title screen is up and owns input
var page := "main"
var selected := 0                       # the highlighted button on the main page
var elapsed := 0.0

@onready var game := owner
@onready var game_ui: CanvasItem = owner.get_node("UI/Overlay")
@onready var pause_menu = owner.get_node("UI/PauseMenu")
@onready var post: ShaderMaterial = owner.get_node("Screen").material


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Menu.load_style()
	z_index = 20
	game_ui.visible = false
	pause_menu.pause_button_enabled = false
	pause_menu.title_settings_closed.connect(_return_from_settings)
	post.set_shader_parameter("landing_amount", 1.0)


func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	queue_redraw()


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if page == "how":
			if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_show_main()
		else:
			var entries := _entries()
			if event.keycode in [KEY_UP, KEY_W]:
				selected = wrapi(selected - 1, 0, entries.size())
			elif event.keycode in [KEY_DOWN, KEY_S]:
				selected = wrapi(selected + 1, 0, entries.size())
			elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_activate(entries[selected][0])

	elif event is InputEventMouseMotion:
		if page == "main":
			var at := _button_at(get_local_mouse_position())
			if at >= 0:
				selected = at

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p := get_local_mouse_position()
		if page == "how":
			if HowTo.over_close(p):
				_show_main()
		else:
			var at := _button_at(p)
			if at >= 0:
				selected = at
				_activate(_entries()[at][0])

	# the title screen owns all input, including the wheel and right-click
	get_viewport().set_input_as_handled()


func _entries() -> Array:
	var entries := [
		["start", "START GAME"],
		["settings", "SETTINGS"],
		["how", "HOW TO PLAY"],
	]
	if not OS.has_feature("web"):
		entries.append(["quit", "QUIT TO DESKTOP"])
	return entries


func _button_at(p: Vector2) -> int:
	for i in _entries().size():
		if BUTTON_RECTS[i].has_point(p):
			return i
	return -1


func _activate(action: String) -> void:
	match action:
		"start":
			UiSounds.play("start")
			active = false
			visible = false
			pause_menu.pause_button_enabled = true
			game.start_game()
		"settings":
			UiSounds.play("click")
			active = false
			visible = false
			pause_menu.open_title_settings()
		"how":
			UiSounds.play("click")
			page = "how"
		"quit":
			get_tree().quit()


func _show_main() -> void:
	UiSounds.play("back")
	page = "main"
	selected = 2                         # back on HOW TO PLAY
	queue_redraw()


func _return_from_settings() -> void:
	active = true
	visible = true
	page = "main"
	selected = 1
	queue_redraw()


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var cur := get_local_mouse_position().floor()
	var shade := 0.62 if page == "how" else 0.42
	draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.008, 0.012, shade))
	draw_rect(Rect2(0, 0, W, 7), Px.INK)             # letterbox bars
	draw_rect(Rect2(0, H - 7, W, 7), Px.INK)
	if page == "how":
		HowTo.draw(self, cur)
		Menu.cursor(self, cur, HowTo.over_close(cur))
	else:
		_draw_main(cur)
		Menu.cursor(self, cur, _button_at(cur) >= 0)


func _draw_main(cur: Vector2) -> void:
	var title := "OUROBOROS' CABIN"
	var pulse := 0.5 + 0.5 * sin(elapsed * 1.7)
	var tw := int(FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x) - 2
	var base := Vector2(floorf(W / 2.0 - tw / 2.0), 43 + TITLE_SIZE)
	for dy in [-2, 0, 2]:                # the title's ink outline, in 2x pixels like its letters
		for dx in [-2, 0, 2]:
			if dx != 0 or dy != 0:
				draw_string(FONT, base + Vector2(dx, dy), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Px.INK)
	draw_string(FONT, base, title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Menu.accent.lightened(0.12 * pulse))
	Menu.centred(self, "A CLIMATE SHELTER STORY", W / 2.0, 70, Px.WHITE, Px.INK)

	var entries := _entries()
	for i in entries.size():
		Menu.button(self, BUTTON_RECTS[i], entries[i][1], i == selected or BUTTON_RECTS[i].has_point(cur))
	Menu.centred(self, "STORM CYCLE // SHELTER 03", W / 2.0, 221, Menu.accent, Px.INK)
	Menu.centred(self, "UP / DOWN + ENTER", W / 2.0, 239, Menu.panel_hi, Px.INK)

