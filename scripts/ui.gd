extends Control
## Pixel UI drawn straight onto the 480x270 canvas, like pixui.py did in the video:
## hover label, turn arrows, inventory bar, the microfiche display's screen (scripts/fiche.gd),
## the F9 debug menu,
## the close-up views' BACK button and the crafting cell highlight, click ripple and the pixel
## cursor (carrying the held item).

const W := 480
const H := 270
const FONT := preload("res://ui/pixel_font.fnt")
const ARROW := preload("res://ui/cursor_arrow.png")
const HAND := preload("res://ui/cursor_hand.png")
const FICHE := preload("res://scripts/fiche.gd")
const WHITE := Color(1, 1, 1)
const INK := Color8(14, 5, 5)
const SLOT := 20
const SLOT_STEP := 22
const SLOTS: int = preload("res://InventoryManager.gd").MAX_ITEMS
const INV_POS := Vector2i((W - SLOT_STEP * SLOTS + SLOT_STEP - SLOT) / 2, 245)   # first slot, top-left; bar centred
const FLY := 16.0                        # frames an item takes to fly into its slot
const BACK := Rect2(6, 6, 33, 15)        # close-up views: back to the room

var panel := ""
var panel_at := -1e9
var closing_at := -1e9
var ripples: Array = []                  # [pos, clock]
var fiche                                # the microfiche display's screen (scripts/fiche.gd)
var debug_open := false                  # F9 menu (commands come from main.gd debug_commands())
var debug_msg := ""
var debug_msg_at := -1e9
var hotspots: Dictionary
var flights: Array = []                  # [ItemData, from (screen px), launched at]
var held: ItemData = null                # item riding on the cursor
var panel_col: Color                     # palette-snapped panel colours
var panel_hi: Color
var panel_lo: Color

@onready var game := owner


func _ready() -> void:
	hotspots = JSON.parse_string(FileAccess.get_file_as_string("res://ui/cursor_hotspots.json"))
	var pal: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/palette.json"))
	panel_col = _pal(pal, Color(0.09, 0.06, 0.08))
	panel_hi = _pal(pal, Color(0.36, 0.24, 0.17))
	panel_lo = _pal(pal, Color(0.03, 0.02, 0.03))
	fiche = FICHE.new(self, pal)


static func _pal(pal: Array, c: Color) -> Color:
	var best := Color.BLACK
	var bd := INF
	for p in pal:
		var q := Color8(int(p[0]), int(p[1]), int(p[2]))
		var e := 2.0 * pow(q.r - c.r, 2) + 4.0 * pow(q.g - c.g, 2) + 3.0 * pow(q.b - c.b, 2)
		if e < bd:
			bd = e
			best = q
	return best


# ---------------------------------------------------------------- inventory
func fly(item: ItemData, from: Vector2, now: float) -> void:
	flights.append([item, from, now])


func flying() -> bool:
	return not flights.is_empty()


## room for one more item, counting the ones still flying into the bar
func has_room() -> bool:
	return InventoryManager.inventory.items.size() + flights.size() < SLOTS


func _slot_rect(i: int) -> Rect2:
	return Rect2(INV_POS.x + SLOT_STEP * i, INV_POS.y, SLOT, SLOT)


func _slot_at(p: Vector2) -> int:
	for i in SLOTS:
		if _slot_rect(i).has_point(p):
			return i
	return -1


## what a slot shows: the inventory item, unless it is riding on the cursor
func _slot_item(i: int) -> ItemData:
	var inv: Array[ItemData] = InventoryManager.inventory.items
	if i >= inv.size() or inv[i] == held:
		return null
	return inv[i]


## an item's 12x12 icon at pos; items without art yet get a "?" box
func _draw_icon(item: ItemData, pos: Vector2) -> void:
	if item.icon != null:
		draw_texture(item.icon, pos)
	else:
		_frame(Rect2(pos, Vector2(12, 12)), panel_hi)
		text("?", pos + Vector2(3, 2), WHITE, INK)


# ---------------------------------------------------------------- panels
func open_panel(name: String, now: float) -> void:
	panel = name
	panel_at = now
	closing_at = -1e9


func close_panel() -> void:
	if panel != "" and closing_at < panel_at:
		closing_at = game.clock
		if panel == "fiche":
			fiche.release(Vector2(-99, -99))
			fiche.leave_detail()             # next time it opens on the world sheet


## 0..1 open amount: grows over 6 frames, shrinks over 4
func panel_scale() -> float:
	if panel == "":
		return 0.0
	var now: float = game.clock
	var s := minf((now - panel_at) / 6.0, 1.0)
	if closing_at >= panel_at:
		s = minf(s, maxf(1.0 - (now - closing_at) / 4.0, 0.0))
		if s <= 0.0:
			panel = ""
	return maxf(s, 0.0)


func close_box_center() -> Vector2:
	return FICHE.CLOSE


# ---------------------------------------------------------------- hit tests
func over_ui(p: Vector2) -> bool:
	return debug_open or _slot_at(p) >= 0 or _over_back(p)


func _over_back(p: Vector2) -> bool:
	var v = game.active_view()
	return v != null and v.settled() and BACK.has_point(p)


## true when the click was for the UI and the room should ignore it
func handle_click(p: Vector2) -> bool:
	if debug_open:
		var row := _debug_row_at(p)
		if row >= 0:
			game.run_debug(row)
		elif not _debug_rect().has_point(p):
			debug_open = false
		return true
	if panel == "fiche":
		if fiche.over_close(p) or not fiche.press(p):
			close_panel()
		return true
	if _over_back(p):
		game.back()
		return true
	var slot := _slot_at(p)
	if slot >= 0:
		var item := _slot_item(slot)
		if held != null and item != held:
			held = null                  # put back whatever was in hand
		elif item != null:
			held = item
		return true
	return false


## the left button came up (ends a drag on the microfiche, or zooms if it was a click)
func release_click(p: Vector2) -> void:
	if panel == "fiche":
		fiche.release(p)


## mouse wheel over the microfiche: up zooms into a revealed area, down zooms out
func wheel(up: bool, p: Vector2) -> void:
	if panel == "fiche" and panel_scale() >= 1.0:
		fiche.wheel(up, p)


# ---------------------------------------------------------------- debug menu (F9)
const DEBUG_ROW := 10

func _debug_rect() -> Rect2:
	var n: int = game.debug_commands().size()
	return Rect2(124, 34, 232, 40 + n * DEBUG_ROW)


func _debug_row_at(p: Vector2) -> int:
	var r := _debug_rect()
	var i := int((p.y - r.position.y - 26) / DEBUG_ROW)
	if r.has_point(p) and p.y >= r.position.y + 26 and i < game.debug_commands().size():
		return i
	return -1


func debug_say(msg: String) -> void:
	debug_msg = msg
	debug_msg_at = game.clock


func _draw_debug(cur: Vector2) -> bool:
	var cmds: Array = game.debug_commands()
	var r := _debug_rect()
	draw_rect(r, panel_lo)
	_frame(r, WHITE)
	text("DEBUG MENU  (F9 / ESC TO CLOSE)", r.position + Vector2(6, 5), WHITE)
	text(game.debug_status(), r.position + Vector2(6, 14), panel_hi)
	var hot := _debug_row_at(cur)
	for i in cmds.size():
		var y := r.position.y + 26 + i * DEBUG_ROW
		if i == hot:
			draw_rect(Rect2(r.position.x + 2, y - 1, r.size.x - 4, DEBUG_ROW), panel_col)
		text("%s  %s" % [cmds[i][0], cmds[i][1]], Vector2(r.position.x + 8, y), WHITE if i == hot else Color8(170, 170, 178))
	if debug_msg != "" and game.clock - debug_msg_at < 72.0:
		text("> " + debug_msg, Vector2(r.position.x + 6, r.end.y - 11), Color8(239, 180, 94))
	return hot >= 0


func ripple(p: Vector2, now: float) -> void:
	ripples.append([p.floor(), now])


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var now: float = game.clock
	var cur: Vector2 = game.cursor.floor()
	var label := ""
	var ui_hover := false

	# while the cursor pushes an edge, a chevron there shows the view is moving
	if game.push < 0.0:
		_chevron("left", game.push < -0.5, now)
	elif game.push > 0.0:
		_chevron("right", game.push > 0.5, now)

	# close-up views: the crafting grid's hovered cell, and the way back
	var craft = game.crafting
	if craft.settled() and craft.hover_cell != craft.NO_CELL:     # 2 px white on the cell's grid lines, inked outside
		var cr := Rect2(craft.cell_rect(craft.hover_cell))
		_frame(cr.grow(1), INK)
		_frame(cr, WHITE)
		_frame(cr.grow(-1), WHITE)
	var view = game.active_view()
	if view != null and view.settled():
		var hot := BACK.has_point(cur)
		draw_rect(BACK, panel_col)
		_frame(BACK, WHITE if hot else panel_hi)
		text("BACK", BACK.position + Vector2(5, 4), WHITE, INK)
		ui_hover = ui_hover or hot

	for i in SLOTS:
		var r := _slot_rect(i)
		var item := _slot_item(i)
		var hov := item != null and r.has_point(cur) and panel == ""
		draw_rect(r, panel_col)
		_frame(r, WHITE if hov else panel_hi)
		if item != null:
			_draw_icon(item, r.position + Vector2(4, 4))
		if hov:
			label = item.name
			ui_hover = true

	if panel == "fiche":
		var sc := panel_scale()
		fiche.draw(sc)
		if sc >= 1.0:
			label = fiche.hover_label(cur)
			ui_hover = label != "" or fiche.hover_station != ""

	if label == "" and game.hover != "":
		label = game.label_for(game.hover)
	if label != "" and not debug_open:
		var tw := text_width(label)
		var lx := mini(int(cur.x) + 10, W - tw - 3)
		var ly := maxi(int(cur.y) - 13, 3)
		text(label, Vector2(lx, ly), WHITE, INK)

	# items in flight: an arc from the room into the next free slot
	var landed := []
	for fl in flights:
		var k: float = (now - fl[2]) / FLY
		if k >= 1.0:
			landed.append(fl)
			continue
		var slot: int = InventoryManager.inventory.items.size() + flights.find(fl)
		var to := _slot_rect(slot).get_center()
		var t := smoothstep(0.0, 1.0, k)
		var at: Vector2 = fl[1].lerp(to, t) - Vector2(0, 30.0 * sin(PI * t))
		_draw_icon(fl[0], at.floor() - Vector2(6, 6))
	for fl in landed:
		flights.erase(fl)
		InventoryManager.add_item(fl[0])

	for r in ripples:
		var k: float = now - r[1]
		if k < 7.0:
			_ring(r[0], 3.0 + k * 1.6, WHITE)
	ripples = ripples.filter(func(r): return now - r[1] < 7.0)

	if debug_open:
		ui_hover = _draw_debug(cur)
	var hand: bool = game.hover != "" or ui_hover or held != null or craft.hover_cell != craft.NO_CELL
	var name := "hand" if hand else "arrow"
	var hs: Array = hotspots[name]
	var pressed: bool = game.clicking()
	var at := cur - Vector2(hs[0], hs[1]) + Vector2(0, 1 if pressed else 0)
	draw_texture(HAND if hand else ARROW, at, Color(0.78, 0.78, 0.80) if pressed else WHITE)
	if held != null:
		_draw_icon(held, cur + Vector2(5, 8))


# ---------------------------------------------------------------- pixel helpers
static func text_width(s: String) -> int:
	return int(FONT.get_string_size(s.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x) - 1


func text(s: String, pos: Vector2, color: Color, shadow = null) -> void:
	s = s.to_upper()
	var base := pos.floor() + Vector2(0, 7)
	if shadow != null:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx != 0 or dy != 0:
					draw_string(FONT, base + Vector2(dx, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, shadow)
	draw_string(FONT, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, color)


func _ring(c: Vector2, radius: float, color: Color) -> void:
	var n := int(8.0 * radius) + 8
	for i in n:
		var a := TAU * i / n
		var p := (c + Vector2(cos(a), sin(a)) * radius).round()
		if p.x >= 0 and p.y >= 0 and p.x < W and p.y < H:
			draw_rect(Rect2(p, Vector2.ONE), color)


func _frame(r: Rect2, color: Color) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), color)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), color)
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), color)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), color)


## a little pixel chevron at the screen edge, bobbing toward the side the view is moving
func _chevron(s: String, hot: bool, now: float) -> void:
	var dir := -1 if s == "left" else 1
	var tip := (3 if s == "left" else W - 5) + int(fmod(now / 6.0, 2.0)) * dir
	var cy := H / 2
	var col := WHITE if hot else Color8(170, 170, 178)
	for i in range(-4, 5):
		draw_rect(Rect2(tip - dir * absi(i) - 1, cy + i - 1, 4, 3), INK)
	for i in range(-4, 5):
		draw_rect(Rect2(tip - dir * absi(i), cy + i, 2, 1), col)
