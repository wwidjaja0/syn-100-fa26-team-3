extends RefCounted
## The shared look of the menus (start_menu.gd, pause_menu.gd): one panel, one close box, one
## button, so every menu reads the same. It matches the microfiche panel in overlay.gd: a dark
## panel with a 1 px frame, the title top-left, and an X close box top-right.
##
##     const Menu := preload("res://scripts/ui/menu_draw.gd")
##     Menu.panel(self, RECT, "SETTINGS", Menu.close_rect(RECT).has_point(cur))
##
## Every function draws on the CanvasItem you pass in, during its _draw(). Colours are snapped to
## assets/palette.json the first time they are needed.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const ARROW := preload("res://ui/cursor_arrow.png")
const HAND := preload("res://ui/cursor_hand.png")
const TITLE_BAR := 16                   # px: the strip the title and the close box sit in
const CLOSE_SIZE := 11                  # the close box, as on the microfiche

static var panel_col: Color             # panel and button fill
static var panel_hi: Color              # frames, hovered fill
static var panel_lo: Color              # insets: close box, slider track, cards
static var accent: Color                # titles, slider fill, switched-on buttons
static var _hotspots: Dictionary
static var _loaded := false


## load the colours (each menu calls this in its _ready, before it reads them)
static func load_style() -> void:
	if _loaded:
		return
	_loaded = true
	var pal := Px.load_palette()
	panel_col = Px.palette_color(pal, Color(0.09, 0.06, 0.08))     # the same three as overlay.gd
	panel_hi = Px.palette_color(pal, Color(0.36, 0.24, 0.17))
	panel_lo = Px.palette_color(pal, Color(0.03, 0.02, 0.03))
	accent = Px.palette_color(pal, Color8(239, 180, 94))
	_hotspots = JSON.parse_string(FileAccess.get_file_as_string("res://ui/cursor_hotspots.json"))


## the close box of a panel: top-right, in its title bar
static func close_rect(r: Rect2) -> Rect2:
	return Rect2(r.end.x - 14, r.position.y + 2, CLOSE_SIZE, CLOSE_SIZE)


## a menu panel: fill, frame, title, and the X close box (close_hot = the cursor is on it)
static func panel(ci: CanvasItem, r: Rect2, title: String, close_hot: bool) -> void:
	load_style()
	ci.draw_rect(r, panel_col)
	Px.frame(ci, r, panel_hi)
	Px.text(ci, title, r.position + Vector2(7, 4), accent, Px.INK)
	ci.draw_rect(Rect2(r.position.x + 1, r.position.y + TITLE_BAR - 1, r.size.x - 2, 1), panel_hi)
	var cb := close_rect(r)
	ci.draw_rect(cb, panel_lo)
	Px.frame(ci, cb, Px.WHITE if close_hot else panel_hi)
	var c := cb.position + Vector2(5, 5)
	for i in range(-2, 3):                                           # the X
		ci.draw_rect(Rect2(c + Vector2(i, i), Vector2.ONE), Px.WHITE)
		ci.draw_rect(Rect2(c + Vector2(i, -i), Vector2.ONE), Px.WHITE)


## a button with its label centred. hot = hovered or selected; on = a switched-on toggle;
## enabled = false greys it out.
static func button(ci: CanvasItem, r: Rect2, label: String, hot: bool, on := false, enabled := true) -> void:
	load_style()
	hot = hot and enabled
	ci.draw_rect(r, panel_hi if hot else panel_col)
	Px.frame(ci, r, Px.WHITE if hot else (accent if on else panel_hi))
	var col: Color = panel_hi if not enabled else (accent if on and not hot else Px.WHITE)
	var pos := Vector2(r.get_center().x - Px.text_width(label) / 2.0, r.position.y + (r.size.y - 8.0) / 2.0)
	Px.text(ci, label, pos, col, Px.INK)


## text centred on x
static func centred(ci: CanvasItem, s: String, x: float, y: float, color: Color, shadow = null) -> void:
	Px.text(ci, s, Vector2(x - Px.text_width(s) / 2.0, y), color, shadow)


## the pixel cursor: a hand over anything clickable, else the arrow
static func cursor(ci: CanvasItem, p: Vector2, hand: bool) -> void:
	load_style()
	var spot: Array = _hotspots["hand" if hand else "arrow"]
	ci.draw_texture(HAND if hand else ARROW, p - Vector2(spot[0], spot[1]))
