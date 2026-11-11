extends Control
## The title screen (UI/StartMenu). The cabin keeps rendering behind it, but main.gd ignores
## gameplay input (main.landing_active) until START GAME calls main.start_game().
##
## Two pages:
##   "main"   the title and its buttons: START GAME, SETTINGS (opens pause_menu.gd's panel),
##            HOW TO PLAY, and QUIT TO DESKTOP (not on the web). Mouse, or Up / Down + Enter.
##   "how"    HOW TO PLAY: one card per control, each a small drawn diagram with two short lines
##            under it. To add a control, add a line to HOW_CARDS and a case to _draw_icon().
## Panels are drawn with menu_draw.gd (title top-left, X top-right), like pause_menu.gd and the
## microfiche. Esc, Enter or the X closes the how-to-play page.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const Menu := preload("res://scripts/ui/menu_draw.gd")
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
const HELP_PANEL := Rect2(48, 34, 384, 204)
const CARD := Vector2(120, 86)          # how-to-play cards: 3 across, 2 down
const CARD_STEP := Vector2(126, 90)
## [icon, the input, what it does]
const HOW_CARDS := [
	["left_click", "LEFT CLICK", "USE OR PICK UP"],
	["look", "SCREEN EDGE OR A / D", "LOOK AROUND"],
	["item", "ITEM, THEN TARGET", "USE AN ITEM ON IT"],
	["right_click", "RIGHT CLICK", "STEP BACK"],
	["esc", "ESC", "LEAVE A VIEW / PAUSE"],
	["wheel", "WHEEL OR - / +", "ZOOM THE MAP"],
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
			if Menu.close_rect(HELP_PANEL).has_point(p):
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
	draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.008, 0.012, 0.42))
	draw_rect(Rect2(0, 0, W, 7), Px.INK)             # letterbox bars
	draw_rect(Rect2(0, H - 7, W, 7), Px.INK)
	if page == "how":
		_draw_how_to_play(cur)
		Menu.cursor(self, cur, Menu.close_rect(HELP_PANEL).has_point(cur))
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


func _draw_how_to_play(cur: Vector2) -> void:
	Menu.panel(self, HELP_PANEL, "HOW TO PLAY", Menu.close_rect(HELP_PANEL).has_point(cur))
	for i in HOW_CARDS.size():
		var card: Array = HOW_CARDS[i]
		var r := Rect2(HELP_PANEL.position + Vector2(6, 22) + Vector2(i % 3, i / 3) * CARD_STEP, CARD)
		draw_rect(r, Menu.panel_lo)
		Px.frame(self, r, Menu.panel_hi)
		var cx := r.get_center().x
		_draw_icon(card[0], Vector2(cx, r.position.y + 31))
		Menu.centred(self, card[1], cx, r.position.y + 61, Menu.accent)
		Menu.centred(self, card[2], cx, r.position.y + 72, Px.WHITE)


## the diagram on a how-to-play card, centred on c (about 60 x 40 px to work in)
func _draw_icon(icon: String, c: Vector2) -> void:
	c = c.floor()
	match icon:
		"left_click":
			_mouse(c, "left")
		"right_click":
			_mouse(c, "right")
		"wheel":
			_mouse(c - Vector2(16, 0), "wheel")
			_key(c + Vector2(2, -6), "-")
			_key(c + Vector2(18, -6), "+")
		"esc":
			_key(c - Vector2(13, 7), "ESC")
		"look":                          # a screen with the pan chevrons at its edges, and the A / D keys
			var screen := Rect2(c - Vector2(24, 20), Vector2(48, 24))
			draw_rect(screen, Menu.panel_col)
			Px.frame(self, screen, Px.WHITE)
			_chevron(Vector2(screen.position.x + 5, screen.get_center().y), -1)
			_chevron(Vector2(screen.end.x - 6, screen.get_center().y), 1)
			_key(c + Vector2(-16, 8), "A")
			_key(c + Vector2(3, 8), "D")
		"item":                          # an inventory slot, an arrow, and an outlined object
			var slot := Rect2(c - Vector2(27, 9), Vector2(18, 18))
			draw_rect(slot, Menu.panel_col)
			Px.frame(self, slot, Px.WHITE)
			draw_rect(Rect2(slot.position + Vector2(5, 5), Vector2(8, 8)), Menu.accent)
			draw_rect(Rect2(c.x - 5, c.y, 9, 1), Px.WHITE)
			_chevron(Vector2(c.x + 4, c.y), 1, Px.WHITE)
			var target := Rect2(c + Vector2(10, -11), Vector2(17, 22))
			draw_rect(target.grow(-2), Menu.panel_hi)
			for i in range(0, 22, 2):    # a dotted outline, like the hover outline in the room
				draw_rect(Rect2(target.position + Vector2(0, i), Vector2.ONE), Px.WHITE)
				draw_rect(Rect2(target.position + Vector2(16, i + 1), Vector2.ONE), Px.WHITE)
			for i in range(0, 17, 2):
				draw_rect(Rect2(target.position + Vector2(i, 0), Vector2.ONE), Px.WHITE)
				draw_rect(Rect2(target.position + Vector2(i, 21), Vector2.ONE), Px.WHITE)


## a mouse, 19 x 28, with one part lit: "left", "right" or "wheel"
func _mouse(c: Vector2, lit: String) -> void:
	var body := Rect2(c - Vector2(9, 14), Vector2(19, 28))
	draw_rect(body, Menu.panel_col)
	if lit == "left":
		draw_rect(Rect2(body.position, Vector2(10, 11)), Menu.accent)
	elif lit == "right":
		draw_rect(Rect2(body.position + Vector2(9, 0), Vector2(10, 11)), Menu.accent)
	Px.frame(self, body, Px.WHITE)
	draw_rect(Rect2(body.position + Vector2(0, 10), Vector2(19, 1)), Px.WHITE)       # under the buttons
	draw_rect(Rect2(body.position + Vector2(9, 0), Vector2(1, 10)), Px.WHITE)        # between them
	for corner in [Vector2(0, 0), Vector2(18, 0), Vector2(0, 27), Vector2(18, 27)]:  # rounded corners
		draw_rect(Rect2(body.position + corner, Vector2.ONE), Menu.panel_lo)
	var wheel := Rect2(body.position + Vector2(8, 2), Vector2(3, 6))
	draw_rect(wheel, Menu.accent if lit == "wheel" else Menu.panel_col)
	Px.frame(self, wheel, Px.WHITE)


## a key cap with its top-left at pos
func _key(pos: Vector2, label: String) -> void:
	var r := Rect2(pos, Vector2(Px.text_width(label) + 9, 13))
	draw_rect(r, Menu.panel_col)
	Px.frame(self, r, Px.WHITE)
	draw_rect(Rect2(r.position + Vector2(1, 13), Vector2(r.size.x - 2, 1)), Menu.panel_hi)   # its front edge
	Px.text(self, label, r.position + Vector2(5, 3), Menu.accent)


## a 2 px chevron pointing left (-1) or right (1), its tip at `tip`
func _chevron(tip: Vector2, dir: int, color = null) -> void:
	var col: Color = Menu.accent if color == null else color
	for i in 4:
		for t in 2:
			draw_rect(Rect2(tip + Vector2(-dir * (i + t), -i), Vector2.ONE), col)
			draw_rect(Rect2(tip + Vector2(-dir * (i + t), i), Vector2.ONE), col)
