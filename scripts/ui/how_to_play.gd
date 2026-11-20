extends RefCounted
## The how-to-play card, shared by the title screen, the first moment of a new game, and the
## pause menu. Draw it with draw() during a CanvasItem's _draw(). Esc, Enter or the X closes it;
## the caller decides what closing returns to.
##
## To add a control, add a line to CARDS and a case to _icon().

const Px := preload("res://scripts/ui/pixel_draw.gd")
const Menu := preload("res://scripts/ui/menu_draw.gd")

const PANEL := Rect2(48, 34, 384, 204)
const CARD := Vector2(120, 78)
const CARD_STEP := Vector2(126, 82)
## [icon, the input, what it does]
const CARDS := [
	["left_click", "LEFT CLICK", "USE OR PICK UP"],
	["look", "SCREEN EDGE OR A / D", "LOOK AROUND"],
	["item", "ITEM, THEN TARGET", "USE AN ITEM ON IT"],
	["right_click", "RIGHT CLICK", "STEP BACK"],
	["esc", "ESC", "LEAVE A VIEW / PAUSE"],
	["wheel", "WHEEL OR - / +", "ZOOM THE MAP"],
]


static func over_close(p: Vector2) -> bool:
	Menu.load_style()
	return Menu.close_rect(PANEL).has_point(p)


static func draw(ci: CanvasItem, cur: Vector2) -> void:
	Menu.load_style()
	Menu.panel(ci, PANEL, "HOW TO PLAY", over_close(cur))
	for i in CARDS.size():
		var card: Array = CARDS[i]
		var r := Rect2(PANEL.position + Vector2(6, 18) + Vector2(i % 3, i / 3) * CARD_STEP, CARD)
		ci.draw_rect(r, Menu.panel_lo)
		Px.frame(ci, r, Menu.panel_hi)
		var cx := r.get_center().x
		_icon(ci, card[0], Vector2(cx, r.position.y + 26))
		Menu.centred(ci, card[1], cx, r.position.y + 52, Menu.accent)
		Menu.centred(ci, card[2], cx, r.position.y + 63, Px.WHITE)
	Menu.centred(ci, "J OR L OPENS THE CABIN LOG", PANEL.get_center().x, PANEL.end.y - 14, Menu.accent)


## the diagram on a card, centred on c (about 60 x 36 px to work in)
static func _icon(ci: CanvasItem, icon: String, c: Vector2) -> void:
	c = c.floor()
	match icon:
		"left_click":
			_mouse(ci, c, "left")
		"right_click":
			_mouse(ci, c, "right")
		"wheel":
			_mouse(ci, c - Vector2(16, 0), "wheel")
			_key(ci, c + Vector2(2, -6), "-")
			_key(ci, c + Vector2(18, -6), "+")
		"esc":
			_key(ci, c - Vector2(13, 7), "ESC")
		"look":
			var screen := Rect2(c - Vector2(24, 18), Vector2(48, 22))
			ci.draw_rect(screen, Menu.panel_col)
			Px.frame(ci, screen, Px.WHITE)
			_chevron(ci, Vector2(screen.position.x + 5, screen.get_center().y), -1)
			_chevron(ci, Vector2(screen.end.x - 6, screen.get_center().y), 1)
			_key(ci, c + Vector2(-16, 6), "A")
			_key(ci, c + Vector2(3, 6), "D")
		"item":
			var slot := Rect2(c - Vector2(27, 8), Vector2(16, 16))
			ci.draw_rect(slot, Menu.panel_col)
			Px.frame(ci, slot, Px.WHITE)
			ci.draw_rect(Rect2(slot.position + Vector2(4, 4), Vector2(8, 8)), Menu.accent)
			ci.draw_rect(Rect2(c.x - 5, c.y, 9, 1), Px.WHITE)
			_chevron(ci, Vector2(c.x + 4, c.y), 1, Px.WHITE)
			var target := Rect2(c + Vector2(10, -10), Vector2(15, 20))
			ci.draw_rect(target.grow(-2), Menu.panel_hi)
			for i in range(0, 20, 2):
				ci.draw_rect(Rect2(target.position + Vector2(0, i), Vector2.ONE), Px.WHITE)
				ci.draw_rect(Rect2(target.position + Vector2(14, i + 1), Vector2.ONE), Px.WHITE)
			for i in range(0, 15, 2):
				ci.draw_rect(Rect2(target.position + Vector2(i, 0), Vector2.ONE), Px.WHITE)
				ci.draw_rect(Rect2(target.position + Vector2(i, 19), Vector2.ONE), Px.WHITE)


static func _mouse(ci: CanvasItem, c: Vector2, lit: String) -> void:
	var body := Rect2(c - Vector2(9, 14), Vector2(19, 28))
	ci.draw_rect(body, Menu.panel_col)
	if lit == "left":
		ci.draw_rect(Rect2(body.position, Vector2(10, 11)), Menu.accent)
	elif lit == "right":
		ci.draw_rect(Rect2(body.position + Vector2(9, 0), Vector2(10, 11)), Menu.accent)
	Px.frame(ci, body, Px.WHITE)
	ci.draw_rect(Rect2(body.position + Vector2(0, 10), Vector2(19, 1)), Px.WHITE)
	ci.draw_rect(Rect2(body.position + Vector2(9, 0), Vector2(1, 10)), Px.WHITE)
	for corner in [Vector2(0, 0), Vector2(18, 0), Vector2(0, 27), Vector2(18, 27)]:
		ci.draw_rect(Rect2(body.position + corner, Vector2.ONE), Menu.panel_lo)
	var wheel := Rect2(body.position + Vector2(8, 2), Vector2(3, 6))
	ci.draw_rect(wheel, Menu.accent if lit == "wheel" else Menu.panel_col)
	Px.frame(ci, wheel, Px.WHITE)


static func _key(ci: CanvasItem, pos: Vector2, label: String) -> void:
	var r := Rect2(pos, Vector2(Px.text_width(label) + 9, 13))
	ci.draw_rect(r, Menu.panel_col)
	Px.frame(ci, r, Px.WHITE)
	ci.draw_rect(Rect2(r.position + Vector2(1, 13), Vector2(r.size.x - 2, 1)), Menu.panel_hi)
	Px.text(ci, label, r.position + Vector2(5, 3), Menu.accent)


static func _chevron(ci: CanvasItem, tip: Vector2, dir: int, color = null) -> void:
	var col: Color = Menu.accent if color == null else color
	for i in 4:
		for t in 2:
			ci.draw_rect(Rect2(tip + Vector2(-dir * (i + t), -i), Vector2.ONE), col)
			ci.draw_rect(Rect2(tip + Vector2(-dir * (i + t), i), Vector2.ONE), col)
