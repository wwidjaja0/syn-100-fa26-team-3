extends Control
## Opening landing page. The cabin keeps rendering behind this overlay, but Main
## gates all gameplay input until START GAME is chosen.

const W := 480
const H := 270
const FONT := preload("res://ui/pixel_font.fnt")
const ARROW := preload("res://ui/cursor_arrow.png")
const HAND := preload("res://ui/cursor_hand.png")

const WHITE := Color(1, 1, 1)
const INK := Color8(14, 5, 5)
const PANEL := Color8(34, 22, 28)
const PANEL_HI := Color8(119, 79, 57)
const ACCENT := Color8(239, 180, 94)

const BUTTON_RECTS := [
	Rect2(145, 105, 190, 19),
	Rect2(145, 131, 190, 19),
	Rect2(145, 157, 190, 19),
	Rect2(145, 183, 190, 19),
]
const HELP_PANEL := Rect2(48, 34, 384, 204)
const BACK := Rect2(145, 211, 190, 19)

var active := true
var page := "main"
var selected := 0
var elapsed := 0.0

@onready var game := owner
@onready var game_ui: CanvasItem = owner.get_node("UI/Overlay")
@onready var pause_menu = owner.get_node("UI/PauseMenu")
@onready var post: ShaderMaterial = owner.get_node("Screen").material


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	game_ui.visible = false
	pause_menu.pause_button_enabled = false
	pause_menu.title_settings_closed.connect(_return_from_settings)
	post.set_shader_parameter("landing_amount", 1.0)


func _process(delta: float) -> void:
	if active:
		elapsed += delta
		queue_redraw()


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
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if page == "main":
			var at := _button_at(get_local_mouse_position())
			if at >= 0:
				selected = at
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p := get_local_mouse_position()
			if page == "how":
				if BACK.has_point(p):
					_show_main()
			else:
				var at := _button_at(p)
				if at >= 0:
					selected = at
					_activate(_entries()[at][0])
		get_viewport().set_input_as_handled()
		return

	# The landing page owns input, including wheel and right-click events.
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
	var count := _entries().size()
	for i in count:
		if BUTTON_RECTS[i].has_point(p):
			return i
	return -1


func _activate(action: String) -> void:
	match action:
		"start":
			active = false
			visible = false
			pause_menu.pause_button_enabled = true
			game.start_game()
		"settings":
			active = false
			visible = false
			pause_menu.open_title_settings()
		"how":
			page = "how"
		"quit":
			get_tree().quit()


func _show_main() -> void:
	page = "main"
	selected = 0
	queue_redraw()


func _return_from_settings() -> void:
	active = true
	visible = true
	page = "main"
	selected = 1
	queue_redraw()


func _draw() -> void:
	var cur := get_local_mouse_position().floor()
	draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.008, 0.012, 0.42))
	draw_rect(Rect2(0, 0, W, 7), INK)
	draw_rect(Rect2(0, H - 7, W, 7), INK)
	if page == "how":
		_draw_how_to_play(cur)
	else:
		_draw_main(cur)

	var cursor_tex: Texture2D = HAND if _interactive_at(cur) else ARROW
	draw_texture(cursor_tex, cur - Vector2(3, 2), WHITE)


func _draw_main(cur: Vector2) -> void:
	var title := "OUROBOROS' CABIN"
	var pulse := 0.5 + 0.5 * sin(elapsed * 1.7)
	var title_color := ACCENT.lightened(0.12 * pulse)
	draw_rect(Rect2(103, 58, 48, 1), PANEL_HI)
	draw_rect(Rect2(329, 58, 48, 1), PANEL_HI)
	text(title, Vector2(W / 2.0 - text_width(title, 14) / 2.0, 43), title_color, INK, 14)
	var subtitle := "A CLIMATE SHELTER STORY"
	text(subtitle, Vector2(W / 2.0 - text_width(subtitle) / 2.0, 73), WHITE, INK)

	var entries := _entries()
	for i in entries.size():
		var hot: bool = i == selected or BUTTON_RECTS[i].has_point(cur)
		_button(BUTTON_RECTS[i], entries[i][1], hot)
	var status := "STORM CYCLE // SHELTER 03"
	text(status, Vector2(W / 2.0 - text_width(status) / 2.0, 221), ACCENT)
	text("UP / DOWN + ENTER", Vector2(W / 2.0 - text_width("UP / DOWN + ENTER") / 2.0, 239),
			PANEL_HI)


func _draw_how_to_play(cur: Vector2) -> void:
	draw_rect(HELP_PANEL, PANEL)
	_frame(HELP_PANEL, WHITE)
	_frame(HELP_PANEL.grow(-2), PANEL_HI)
	var heading := "HOW TO PLAY"
	text(heading, Vector2(W / 2.0 - text_width(heading, 10) / 2.0, 45), ACCENT, INK, 10)
	text("POINT AND CLICK TO INSPECT OR USE OBJECTS.", Vector2(65, 75), WHITE)
	text("MOVE TO THE SCREEN EDGES, OR USE A / D, TO LOOK.", Vector2(65, 94), WHITE)
	text("CLICK AN INVENTORY ITEM, THEN CLICK ITS TARGET.", Vector2(65, 113), WHITE)
	text("RIGHT-CLICK STEPS BACK OR PUTS AN ITEM AWAY.", Vector2(65, 132), WHITE)
	text("ESC LEAVES A VIEW; FROM THE ROOM IT PAUSES.", Vector2(65, 151), WHITE)
	text("USE THE WHEEL OR - / + TO ZOOM THE MICROFICHE.", Vector2(65, 170), WHITE)
	_button(BACK, "BACK", BACK.has_point(cur))


func _interactive_at(p: Vector2) -> bool:
	if page == "how":
		return BACK.has_point(p)
	return _button_at(p) >= 0


func _button(rect: Rect2, label: String, hot: bool) -> void:
	draw_rect(rect, PANEL_HI if hot else PANEL)
	_frame(rect, WHITE if hot else PANEL_HI)
	var x := rect.get_center().x - text_width(label) / 2.0
	var y := rect.position.y + (rect.size.y - 8.0) / 2.0
	text(label, Vector2(x, y), WHITE, INK)


static func text_width(s: String, size := 7) -> int:
	return int(FONT.get_string_size(s.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x) - 1


func text(s: String, pos: Vector2, color: Color, shadow = null, size := 7) -> void:
	var base := pos.floor() + Vector2(0, size)
	s = s.to_upper()
	if shadow != null:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx != 0 or dy != 0:
					draw_string(FONT, base + Vector2(dx, dy), s,
							HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	draw_string(FONT, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _frame(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1)), color)
	draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1, 0), Vector2(1, rect.size.y)), color)
