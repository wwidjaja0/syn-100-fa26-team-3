extends Control
## The pixel UI, drawn straight onto the 480x270 canvas on top of the post-processed room
## (the UI/Overlay node in scenes/main.tscn).
##
## Draws, in this order (later on top):
##   edge chevrons while the view pans  - crafting: items on the mat, the cell highlight, the
##   result slot  - BACK button (close-ups)
##   inventory bar (inventory_bar.gd)   - the microfiche panel (microfiche/microfiche_panel.gd)
##   hover label - items flying into the bar - click ripples - F9 menu (dev/debug_menu.gd)
##   the cursor (arrow, or hand over anything clickable) with the held item on it
##
## Panels: at most one is open at a time (`panel`); today only "fiche", the microfiche.
## main.gd sends every click here first (handle_click); the room only gets the ones the UI ignores.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const InventoryBar := preload("res://scripts/ui/inventory_bar.gd")
const MicrofichePanel := preload("res://scripts/ui/microfiche/microfiche_panel.gd")
const DialogueBox := preload("res://scripts/ui/dialogue_box.gd")
const ARROW := preload("res://ui/cursor_arrow.png")
const HAND := preload("res://ui/cursor_hand.png")
const BACK := Rect2(6, 6, 33, 15)       # close-up views: back to the room
const RESULT := Rect2(402, 112, 46, 46) # crafting view: the result slot, right of the mat
const RESULT_SCALE := 3                 # the result's 12x12 icon, drawn 3x
const PANEL_OPEN_FRAMES := 6.0
const PANEL_CLOSE_FRAMES := 4.0
const RIPPLE_FRAMES := 7.0

var panel := ""                         # the open panel: "" or "fiche"
var inventory: InventoryBar
var microfiche: MicrofichePanel
var dialogue: DialogueBox
# palette-snapped panel colours, shared by everything drawn here
var panel_col: Color
var panel_hi: Color
var panel_lo: Color

var _panel_at := -1e9
var _closing_at := -1e9
var _ripples: Array = []                # [pos, clock]
var _hotspots: Dictionary               # cursor name -> its click point

@onready var main := owner


func _ready() -> void:
	_hotspots = JSON.parse_string(FileAccess.get_file_as_string("res://ui/cursor_hotspots.json"))
	var pal := Px.load_palette()
	panel_col = Px.palette_color(pal, Color(0.09, 0.06, 0.08))
	panel_hi = Px.palette_color(pal, Color(0.36, 0.24, 0.17))
	panel_lo = Px.palette_color(pal, Color(0.03, 0.02, 0.03))
	inventory = InventoryBar.new(self)
	microfiche = MicrofichePanel.new(self, pal)
	dialogue = DialogueBox.new(self, pal)


# ---------------------------------------------------------------- panels
func open_panel(name: String, now: float) -> void:
	panel = name
	_panel_at = now
	_closing_at = -1e9


func close_panel() -> void:
	if panel != "" and _closing_at < _panel_at:
		_closing_at = main.clock
		UiSounds.play("back")
		if panel == "fiche":
			microfiche.release(Vector2(-99, -99))   # drop any drag
			microfiche.leave_detail()               # next time it opens on the world sheet


## 0..1 how open the panel is: grows over PANEL_OPEN_FRAMES, shrinks over PANEL_CLOSE_FRAMES.
## Also the post shader's "dim" (the room darkens behind a panel).
func panel_scale() -> float:
	if panel == "":
		return 0.0
	var now: float = main.clock
	var s := minf((now - _panel_at) / PANEL_OPEN_FRAMES, 1.0)
	if _closing_at >= _panel_at:
		s = minf(s, maxf(1.0 - (now - _closing_at) / PANEL_CLOSE_FRAMES, 0.0))
		if s <= 0.0:
			panel = ""
	return maxf(s, 0.0)


# ---------------------------------------------------------------- input
## is the cursor on a piece of UI (so the room shouldn't react to it)?
func over_ui(p: Vector2) -> bool:
	return main.debug_menu.open or dialogue.is_active() or inventory.slot_at(p) >= 0 or _over_back(p) \
			or _over_result(p) or main.radio_repair.slot_at(p) != ""


func _over_result(p: Vector2) -> bool:
	return main.crafting.settled() and RESULT.has_point(p)


func _over_back(p: Vector2) -> bool:
	var v = main.active_view()
	return v != null and v.settled() and BACK.has_point(p)


## the left button went down. True when the UI took the click and the room should ignore it.
func handle_click(p: Vector2) -> bool:
	if main.debug_menu.open:
		main.debug_menu.click(p)
		return true
	if dialogue.is_active():
		dialogue.skip_or_advance()
		return true
	if panel == "fiche":
		if microfiche.over_close(p) or not microfiche.press(p):
			close_panel()
		return true
	if _over_back(p):
		main.back()
		return true
	if _over_result(p):
		main.workbench.craft(RESULT.get_center())
		return true
	if main.radio_repair.click(p, inventory.held):
		return true
	return inventory.click(p)


## the left button came up (ends a drag on the microfiche, or zooms if it was a click)
func release_click(p: Vector2) -> void:
	if panel == "fiche":
		microfiche.release(p)


## mouse wheel: zooms the microfiche while it is open
func wheel(up: bool, p: Vector2) -> void:
	if panel == "fiche" and panel_scale() >= 1.0:
		microfiche.wheel(up, p)


## a little expanding ring where the player clicked
func ripple(p: Vector2, now: float) -> void:
	_ripples.append([p.floor(), now])


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var now: float = main.clock
	var cur: Vector2 = main.cursor.floor()
	var label := ""
	var ui_hover := false

	# while the view pans, a chevron on that edge shows it
	var push: float = main.room_camera.push
	if push < 0.0:
		_chevron(-1, push < -0.5, now)
	elif push > 0.0:
		_chevron(1, push > 0.5, now)

	# close-ups: the crafting mat (items on it, the hovered cell, the result slot) and BACK
	var craft = main.crafting
	if craft.settled():
		var craft_label := _draw_crafting(craft, cur)
		ui_hover = ui_hover or craft_label != ""
		label = craft_label
	if main.radio_repair.showing():
		var radio_label := _draw_radio_slots(cur)
		ui_hover = ui_hover or radio_label != ""
		label = radio_label
	var view = main.active_view()
	if view != null and view.settled():
		var hot := BACK.has_point(cur)
		draw_rect(BACK, panel_col)
		Px.frame(self, BACK, Px.WHITE if hot else panel_hi)
		Px.text(self, "BACK", BACK.position + Vector2(5, 4), Px.WHITE, Px.INK)
		ui_hover = ui_hover or hot

	var slot_label := inventory.draw_slots(cur, panel == "")
	if slot_label != "":
		label = slot_label
	ui_hover = ui_hover or label != ""

	if panel == "fiche":
		var sc := panel_scale()
		microfiche.draw(sc, main.cursor)
		if sc >= 1.0:
			label = microfiche.hover_label(cur)
			ui_hover = label != "" or microfiche.hover_station != ""

	var hover: String = main.picker.hover
	if label == "" and hover != "":
		label = main.interactions.label_for(hover, inventory.held)
	if label != "" and not main.debug_menu.open and not dialogue.is_active():
		var tw := Px.text_width(label)
		var lx := mini(int(cur.x) + 10, Px.W - tw - 3)
		var ly := maxi(int(cur.y) - 13, 3)
		Px.text(self, label, Vector2(lx, ly), Px.WHITE, Px.INK)

	inventory.draw_flights(now)

	for r in _ripples:
		var k: float = now - r[1]
		if k < RIPPLE_FRAMES:
			Px.ring(self, r[0], 3.0 + k * 1.6, Px.WHITE)
	_ripples = _ripples.filter(func(r): return now - r[1] < RIPPLE_FRAMES)

	if main.debug_menu.open:
		ui_hover = main.debug_menu.draw(self, cur)

	if dialogue.is_active():
		dialogue.draw(now, cur)

	# the cursor: a hand over anything clickable, pressed in while a click is fresh
	var hand: bool = hover != "" or ui_hover or inventory.held != null or craft.hover_cell != craft.NO_CELL or dialogue.is_active()
	var hs: Array = _hotspots["hand" if hand else "arrow"]
	var pressed: bool = main.clicking()
	var at := cur - Vector2(hs[0], hs[1]) + Vector2(0, 1 if pressed else 0)
	draw_texture(HAND if hand else ARROW, at, Color(0.78, 0.78, 0.80) if pressed else Px.WHITE)
	if inventory.held != null:
		inventory.draw_icon(inventory.held, cur + Vector2(5, 8))


## the radio close-up's repair slots (radio/radio_repair.gd): a square per missing part, white when
## hovered, with the part's icon at 2x once it's in. Returns the hover label.
func _draw_radio_slots(cur: Vector2) -> String:
	var repair = main.radio_repair
	var label := ""
	for id: String in repair.SLOTS:
		var r: Rect2 = repair.slot_rect(id)
		var hot := r.has_point(cur)
		draw_rect(r, panel_col)
		Px.frame(self, r.grow(1), Px.INK)
		Px.frame(self, r, Px.WHITE if hot else panel_hi)
		var item: ItemData = repair.filled.get(id)
		if item != null and item.icon != null:
			draw_texture_rect(item.icon, Rect2(r.position + Vector2(2, 2), Vector2(24, 24)), false)
		else:
			var name: String = repair.SLOTS[id][2]
			Px.text(self, name, Vector2(r.get_center().x - Px.text_width(name) / 2.0, r.end.y + 3).floor(), Px.WHITE, Px.INK)
		if hot:
			label = repair.label(id, inventory.held)
	return label


## the crafting view's UI: the items lying on the mat, the hovered cell (2 px white on its grid
## lines, inked outside) and the result slot (empty until the mat holds a recipe; crafting/crafting.gd).
## Returns the hover label.
func _draw_crafting(craft, cur: Vector2) -> String:
	var bench = main.workbench
	var label := ""
	for cell: Vector2i in bench.placed:
		inventory.draw_icon(bench.placed[cell], Vector2(craft.cell_rect(cell).position) + Vector2(5, 5))
	if craft.hover_cell != craft.NO_CELL:
		var cr := Rect2(craft.cell_rect(craft.hover_cell))
		Px.frame(self, cr.grow(1), Px.INK)
		Px.frame(self, cr, Px.WHITE)
		Px.frame(self, cr.grow(-1), Px.WHITE)
		var on: ItemData = bench.item_at(craft.hover_cell)
		if on != null and inventory.held == null:
			label = "TAKE " + on.name
	var out: String = bench.result()
	var hot := out != "" and RESULT.has_point(cur)
	draw_rect(RESULT, panel_col)
	Px.frame(self, RESULT.grow(1), Px.INK)
	Px.frame(self, RESULT, Px.WHITE if hot else panel_hi)
	if out != "":
		var item := InventoryManager.get_item(out)
		var at := RESULT.position + (RESULT.size - Vector2(12, 12) * RESULT_SCALE) / 2.0
		if item.icon != null:
			draw_texture_rect(item.icon, Rect2(at, Vector2(12, 12) * RESULT_SCALE), false)
		else:
			Px.text(self, "?", RESULT.get_center() - Vector2(2, 3), Px.WHITE, Px.INK)
		if hot:
			label = "MAKE " + item.name
	return label


## a little pixel chevron at the left (side -1) or right (+1) edge, bobbing toward that side
func _chevron(side: int, hot: bool, now: float) -> void:
	var tip := (3 if side < 0 else Px.W - 5) + int(fmod(now / 6.0, 2.0)) * side
	var cy := Px.H / 2
	var col := Px.WHITE if hot else Px.GREY
	for i in range(-4, 5):
		draw_rect(Rect2(tip - side * absi(i) - 1, cy + i - 1, 4, 3), Px.INK)
	for i in range(-4, 5):
		draw_rect(Rect2(tip - side * absi(i), cy + i, 2, 1), col)
