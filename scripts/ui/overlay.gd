extends Control
## The pixel UI, drawn straight onto the 480x270 canvas on top of the post-processed room
## (the UI/Overlay node in scenes/main.tscn).
##
## Draws, in this order (later on top):
##   edge chevrons while the view pans  - crafting, the tank and radio panels, BACK
##   inventory bar (inventory_bar.gd)  - hover label, items in flight, click ripples
##   then any popup sitting under the top one, a full-screen scrim, and the top popup
##   (the microfiche, the cabin log, the dialogue box, or the F9 menu). Clicks never pass
##   through the scrim.
##   a red ! above the radio when a transmission is waiting, or the radio is the next story step,
##   and above the sandbags while the storm runs in through the hole under the window
##   the day and the temperature outside, in the top-left corner (in the room, not the close-ups)
##   the black of a night passing, with the new day's card (room/pendant.gd)
##   the cursor (arrow, or hand over anything clickable) with the held item on it
##
## Panels: at most one is open at a time (`panel`): "fiche" (the microfiche) or "journal"
## (the cabin log: J, L, or the fixed radio when nothing is incoming).
## main.gd sends every click here first (handle_click); the room only gets the ones the UI ignores.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const InventoryBar := preload("res://scripts/ui/inventory_bar.gd")
const MicrofichePanel := preload("res://scripts/ui/microfiche/microfiche_panel.gd")
const JournalPanel := preload("res://scripts/ui/journal_panel.gd")
const DialogueBox := preload("res://scripts/ui/dialogue_box.gd")
const ARROW := preload("res://ui/cursor_arrow.png")
const HAND := preload("res://ui/cursor_hand.png")
const BACK := Rect2(6, 6, 33, 15)       # close-up views: back to the room
const RESULT := Rect2(402, 112, 46, 46) # crafting view: the result slot, right of the mat
const RESULT_SCALE := 3                 # the result's 12x12 icon, drawn 3x
const PANEL_OPEN_FRAMES := 6.0
const PANEL_CLOSE_FRAMES := 4.0
const RIPPLE_FRAMES := 7.0
const HUD_AT := Vector2(6, 6)           # the day / temperature box's top-left corner
const THERMO_MIN := 20.0                # degC at the thermometer icon's empty and full marks
const THERMO_MAX := 45.0
## explicit red, not the amber "new" chip: this one means "the story is waiting on the radio"
const ALERT := Color8(214, 36, 28)
## full-screen dim behind whichever popup is on top (dialogue, the map, the journal, the debug menu).
## Pause and the title screen draw the same shade themselves.
const SCRIM := Color(0.015, 0.008, 0.012, 0.62)

var panel := ""                         # the open panel: "", "fiche", or "journal"
var inventory: InventoryBar
var microfiche: MicrofichePanel
var journal: JournalPanel
var dialogue: DialogueBox
# palette-snapped panel colours, shared by everything drawn here
var panel_col: Color
var panel_hi: Color
var panel_lo: Color
var warn_col: Color                     # readings outside their safe band
var ok_col: Color                       # the safe band on a reading's bar

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
	warn_col = Px.palette_color(pal, Color(0.92, 0.39, 0.09))
	ok_col = Px.palette_color(pal, Color(0.39, 0.63, 0.68))
	inventory = InventoryBar.new(self)
	microfiche = MicrofichePanel.new(self, pal)
	journal = JournalPanel.new(self, pal)
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
		elif panel == "journal":
			journal.leave_detail()


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
## the popup that owns the screen, or "". Lower UI and the room ignore the cursor until it closes.
## Debug sits above dialogue, which sits above the open panel (the microfiche or the journal).
func top_modal() -> String:
	if main.debug_menu.open:
		return "debug"
	if dialogue.is_active():
		return "dialogue"
	return panel


func _scrim() -> void:
	draw_rect(Rect2(0, 0, Px.W, Px.H), SCRIM)


func _hover_label(text: String, cur: Vector2) -> void:
	var tw := Px.text_width(text)
	var lx := mini(int(cur.x) + 10, Px.W - tw - 3)
	var ly := maxi(int(cur.y) - 13, 3)
	Px.text(self, text, Vector2(lx, ly), Px.WHITE, Px.INK)


## is the cursor on a piece of UI (so the room shouldn't react to it)?
func over_ui(p: Vector2) -> bool:
	if top_modal() != "":
		return true
	return inventory.slot_at(p) >= 0 or _over_back(p) or _over_result(p) \
			or main.radio_repair.slot_at(p) != "" or main.tank_panel.over(p)


func _over_result(p: Vector2) -> bool:
	return main.crafting.settled() and RESULT.has_point(p)


func _over_back(p: Vector2) -> bool:
	var v = main.active_view()
	return v != null and v.settled() and BACK.has_point(p)


## the left button went down. True when the UI took the click and the room should ignore it.
## A popup eats every click: only its own controls run, and nothing under the scrim does.
func handle_click(p: Vector2) -> bool:
	match top_modal():
		"debug":
			main.debug_menu.click(p)
			return true
		"dialogue":
			dialogue.skip_or_advance()
			return true
		"fiche":
			if microfiche.over_close(p):
				close_panel()
			else:
				microfiche.press(p)
			return true
		"journal":
			if journal.over_close(p):
				close_panel()
			else:
				journal.press(p)
			return true
	if _over_back(p):
		main.back()
		return true
	if _over_result(p):
		main.workbench.craft(RESULT.get_center())
		return true
	if main.radio_repair.click(p, inventory.held) or main.tank_panel.click(p, inventory.held):
		return true
	return inventory.click(p)


## the left button came up (ends a drag on the microfiche, or zooms if it was a click)
func release_click(p: Vector2) -> void:
	if top_modal() == "fiche":
		microfiche.release(p)


## mouse wheel: zooms the microfiche while it is the top popup
func wheel(up: bool, p: Vector2) -> void:
	if top_modal() == "fiche" and panel_scale() >= 1.0:
		microfiche.wheel(up, p)
	elif top_modal() == "journal" and panel_scale() >= 1.0:
		journal.wheel(up)


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
	_draw_hud()

	# close-ups and the inventory stay on screen under a popup, but they don't highlight or take clicks
	var top := top_modal()
	var live := top == ""
	var craft = main.crafting
	if craft.settled():
		var craft_label := _draw_crafting(craft, cur, live)
		ui_hover = ui_hover or craft_label != ""
		label = craft_label
	if main.tank_panel.showing():
		var tank_label := _draw_tank_panel(cur, live)
		ui_hover = ui_hover or tank_label != ""
		label = tank_label
	if main.radio_repair.showing():
		var radio_label := _draw_radio_slots(cur, live)
		ui_hover = ui_hover or radio_label != ""
		label = radio_label
	var view = main.active_view()
	if view != null and view.settled():
		var hot := live and BACK.has_point(cur)
		draw_rect(BACK, panel_col)
		Px.frame(self, BACK, Px.WHITE if hot else panel_hi)
		Px.text(self, "BACK", BACK.position + Vector2(5, 4), Px.WHITE, Px.INK)
		ui_hover = ui_hover or hot

	var slot_label := inventory.draw_slots(cur, live)
	if slot_label != "":
		label = slot_label
	ui_hover = ui_hover or label != ""

	var hover: String = main.picker.hover
	if live and label == "" and hover != "":
		label = main.interactions.label_for(hover, inventory.held)
	if label != "":
		_hover_label(label, cur)

	inventory.draw_flights(now)

	for r in _ripples:
		var k: float = now - r[1]
		if k < RIPPLE_FRAMES:
			Px.ring(self, r[0], 3.0 + k * 1.6, Px.WHITE)
	_ripples = _ripples.filter(func(r): return now - r[1] < RIPPLE_FRAMES)

	# popups under the top one stay visible, then one scrim, then the top popup
	if panel == "fiche" and top != "fiche":
		microfiche.draw(panel_scale(), Vector2(-999, -999))
	elif panel == "journal" and top != "journal":
		journal.draw(panel_scale(), now, Vector2(-999, -999))
	if dialogue.is_active() and top != "dialogue":
		dialogue.draw(now, Vector2(-999, -999))
	if top != "":
		_scrim()
	if top == "" or top == "dialogue":
		_draw_radio_alert(now)
		_draw_leak_alert(now)
	if top == "fiche":
		var sc := panel_scale()
		microfiche.draw(sc, cur)
		if sc >= 1.0:
			var fiche_label := microfiche.hover_label(cur)
			ui_hover = fiche_label != "" or microfiche.hover_station != ""
			if fiche_label != "":
				_hover_label(fiche_label, cur)
	elif top == "journal":
		var sc := panel_scale()
		journal.draw(sc, now, cur)
		if sc >= 1.0:
			var journal_label := journal.hover_label(cur)
			ui_hover = journal_label != ""
			if journal_label != "":
				_hover_label(journal_label, cur)
	elif top == "debug":
		ui_hover = main.debug_menu.draw(self, cur)
	elif top == "dialogue":
		dialogue.draw(now, cur)
		ui_hover = true

	_draw_night()

	# the cursor: a hand over anything clickable, pressed in while a click is fresh
	var hand: bool = ui_hover or (live and (hover != "" or inventory.held != null or craft.hover_cell != craft.NO_CELL))
	var hs: Array = _hotspots["hand" if hand else "arrow"]
	var pressed: bool = main.clicking()
	var at := cur - Vector2(hs[0], hs[1]) + Vector2(0, 1 if pressed else 0)
	draw_texture(HAND if hand else ARROW, at, Color(0.78, 0.78, 0.80) if pressed else Px.WHITE)
	if inventory.held != null:
		inventory.draw_icon(inventory.held, cur + Vector2(5, 8))


## the tank close-up's panel (tank/tank_panel.gd): each reading's name and live value (orange when
## outside its safe band), a bar with the safe band marked and a tick at the value, then the item
## slots. Returns the hover label.
func _draw_tank_panel(cur: Vector2, live: bool) -> String:
	var tank = main.tank_panel
	var r: Rect2 = tank.PANEL
	draw_rect(r, panel_col)
	Px.frame(self, r.grow(1), Px.INK)
	Px.frame(self, r, panel_hi)
	Px.text(self, "REEF TANK", r.position + Vector2(8, 7), Px.WHITE, Px.INK)
	for i in tank.readings.size():
		var rd: Dictionary = tank.readings[i]
		var v: float = tank.live_value(i)
		var safe: bool = tank.in_safe_band(i)
		var at: Vector2 = tank.row_pos(i)
		Px.text(self, rd.name, at, Px.GREY, Px.INK)
		var val: String = rd.format % v
		Px.text(self, val, Vector2(r.end.x - 8 - Px.text_width(val), at.y), Px.WHITE if safe else warn_col, Px.INK)
		var bar: Rect2 = tank.bar_rect(i)
		var span: float = rd.max - rd.min
		draw_rect(bar, panel_lo)
		var s0: float = bar.position.x + bar.size.x * (rd.safe[0] - rd.min) / span
		var s1: float = bar.position.x + bar.size.x * (rd.safe[1] - rd.min) / span
		draw_rect(Rect2(s0, bar.position.y + 2, s1 - s0, bar.size.y - 4), ok_col)
		Px.frame(self, bar, panel_hi)
		var tx := floorf(bar.position.x + bar.size.x * clampf((v - rd.min) / span, 0.0, 1.0))
		draw_rect(Rect2(tx - 1, bar.position.y - 2, 3, bar.size.y + 4), Px.INK)
		draw_rect(Rect2(tx, bar.position.y - 1, 1, bar.size.y + 2), Px.WHITE if safe else warn_col)
		if not safe:
			Px.text(self, "OUT OF RANGE", at + Vector2(0, 21), warn_col, Px.INK)
	var label := ""
	Px.text(self, "SLOTS", tank.slot_rect(0).position + Vector2(0, -11), Px.GREY, Px.INK)
	for i in tank.SLOTS:
		var sr: Rect2 = tank.slot_rect(i)
		var hot := live and sr.has_point(cur)
		draw_rect(sr, panel_lo)
		Px.frame(self, sr.grow(1), Px.INK)
		Px.frame(self, sr, Px.WHITE if hot else panel_hi)
		var item: ItemData = tank.contents[i]
		if item != null:
			if item.icon != null:
				draw_texture_rect(item.icon, Rect2(sr.position + Vector2(2, 2), Vector2(24, 24)), false)
			else:
				Px.text(self, "?", sr.get_center() - Vector2(2, 3), Px.WHITE, Px.INK)
		if hot:
			label = tank.label(i, inventory.held)
	return label


## the radio close-up's repair slots (radio/radio_repair.gd): a square per missing part, white when
## hovered, with the part's icon at 2x once it's in. Returns the hover label.
func _draw_radio_slots(cur: Vector2, live: bool) -> String:
	var repair = main.radio_repair
	var label := ""
	for id: String in repair.SLOTS:
		var r: Rect2 = repair.slot_rect(id)
		var hot := live and r.has_point(cur)
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
func _draw_crafting(craft, cur: Vector2, live: bool) -> String:
	var bench = main.workbench
	var label := ""
	for cell: Vector2i in bench.placed:
		inventory.draw_icon(bench.placed[cell], Vector2(craft.cell_rect(cell).position) + Vector2(5, 5))
	if live and craft.hover_cell != craft.NO_CELL:
		var cr := Rect2(craft.cell_rect(craft.hover_cell))
		Px.frame(self, cr.grow(1), Px.INK)
		Px.frame(self, cr, Px.WHITE)
		Px.frame(self, cr.grow(-1), Px.WHITE)
		var on: ItemData = bench.item_at(craft.hover_cell)
		if on != null and inventory.held == null:
			label = "TAKE " + on.name
	var out: String = bench.result()
	var hot := live and out != "" and RESULT.has_point(cur)
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


## a red ! sign pointing straight down at the radio. Story guidance only: an incoming call, or the
## radio itself once the cabin has pointed the player at it and it is still broken. Hidden parts
## stay unmarked.
func _draw_radio_alert(now: float) -> void:
	if main.landing_active or not main.interactions.radio_alert():
		return
	var top: Vector2 = main.picker.screen_top("radio")
	var bob := int(fmod(now / 8.0, 2.0))
	var tip := Vector2i(int(clampf(top.x, 7.0, Px.W - 8.0)), int(clampf(top.y - 3.0 - bob, 16.0, Px.H - 4.0)))
	_alert_badge(tip)


## the same sign over the sandbag pile while water runs in through the hole behind it (room/leak.gd)
func _draw_leak_alert(now: float) -> void:
	if not main.interactions.leak_alert():
		return
	var top: Vector2 = main.picker.screen_top("sandbags")
	var bob := int(fmod(now / 8.0, 2.0))
	_alert_badge(Vector2i(int(clampf(top.x, 7.0, Px.W - 8.0)), int(clampf(top.y - 3.0 - bob, 16.0, Px.H - 4.0))))


## the top-left box: the day, and the temperature outside with a little thermometer. The
## temperature turns orange when it is hotter outside than the reef tank's water, the cue that an
## open window will warm the tank (tank/tank_water.gd). Hidden on the title screen and in close-ups,
## where BACK sits in that corner.
func _draw_hud() -> void:
	if main.landing_active or main.active_view() != null:
		return
	var day := "DAY %d" % GameState.day
	var outside: float = main.weather.temperature()
	var deg := "%d" % roundi(outside)
	var hot: bool = outside > main.tank_panel.readings[0].value
	var w := maxi(Px.text_width(day), 8 + Px.text_width(deg) + 4 + Px.text_width("C")) + 10
	var r := Rect2(HUD_AT, Vector2(w, 27))
	draw_rect(r, panel_col)
	Px.frame(self, r.grow(1), Px.INK)
	Px.frame(self, r, panel_hi)
	Px.text(self, day, r.position + Vector2(5, 4), Px.WHITE, Px.INK)
	# the thermometer: a glass stem over a red bulb, filled to the temperature
	var at := r.position + Vector2(5, 15)
	draw_rect(Rect2(at + Vector2(0, -1), Vector2(5, 10)), Px.INK)
	draw_rect(Rect2(at + Vector2(2, 0), Vector2(1, 6)), Px.GREY)
	var fill := int(round(5.0 * clampf((outside - THERMO_MIN) / (THERMO_MAX - THERMO_MIN), 0.0, 1.0)))
	draw_rect(Rect2(at + Vector2(2, 6 - fill), Vector2(1, fill)), ALERT)
	draw_rect(Rect2(at + Vector2(1, 5), Vector2(3, 3)), ALERT)
	var col := warn_col if hot else Px.WHITE
	var tx := at.x + 8
	Px.text(self, deg, Vector2(tx, at.y), col, Px.INK)
	tx += Px.text_width(deg) + 1
	draw_rect(Rect2(tx, at.y - 1, 5, 5), Px.INK)          # a degree sign: the font has none
	Px.frame(self, Rect2(tx + 1, at.y, 3, 3), col)
	Px.text(self, "C", Vector2(tx + 5, at.y), col, Px.INK)


## lights out (room/pendant.gd): the room fades to black in steps, the new day's number shows big
## in the middle, and the morning fades back in
func _draw_night() -> void:
	var dark: float = main.pendant.blackout()
	if dark <= 0.0:
		return
	draw_rect(Rect2(0, 0, Px.W, Px.H), Color(Px.INK, snappedf(dark, 0.25)))
	var c: float = main.pendant.card()
	if c <= 0.0:
		return
	var s := "DAY %d" % GameState.day
	var at := Vector2(floorf((Px.W - 2 * Px.text_width(s)) / 2.0), floorf(Px.H / 2.0 - 7.0))
	draw_set_transform(at, 0.0, Vector2(2, 2))
	Px.text(self, s, Vector2.ZERO, Color(1, 1, 1, snappedf(c, 0.25)), Px.INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## half-widths of the alert sign's rows, top to bottom: a 9 x 11 sign with clipped corners, then a
## point three rows long whose last pixel is the tip
const ALERT_ROWS := [3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 3, 2, 1, 0]


## the alert sign with its tip at `tip`: ink round the outside, red, a bold white !
func _alert_badge(tip: Vector2i) -> void:
	var top := tip.y - (ALERT_ROWS.size() - 1)
	for r in ALERT_ROWS.size():
		var h: int = ALERT_ROWS[r]
		draw_rect(Rect2(tip.x - h - 1, top + r - 1, 2 * h + 3, 3), Px.INK)
	for r in ALERT_ROWS.size():
		var h: int = ALERT_ROWS[r]
		draw_rect(Rect2(tip.x - h, top + r, 2 * h + 1, 1), ALERT)
	draw_rect(Rect2(tip.x - 1, top + 2, 3, 4), Px.WHITE)     # the bar, tapering
	draw_rect(Rect2(tip.x, top + 6, 1, 1), Px.WHITE)
	draw_rect(Rect2(tip.x - 1, top + 8, 3, 2), Px.WHITE)     # the dot


## a little pixel chevron at the left (side -1) or right (+1) edge, bobbing toward that side
func _chevron(side: int, hot: bool, now: float) -> void:
	var tip := (3 if side < 0 else Px.W - 5) + int(fmod(now / 6.0, 2.0)) * side
	var cy := Px.H / 2
	var col := Px.WHITE if hot else Px.GREY
	for i in range(-4, 5):
		draw_rect(Rect2(tip - side * absi(i) - 1, cy + i - 1, 4, 3), Px.INK)
	for i in range(-4, 5):
		draw_rect(Rect2(tip - side * absi(i), cy + i, 2, 1), col)
