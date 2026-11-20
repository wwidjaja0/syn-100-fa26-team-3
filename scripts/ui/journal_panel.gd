extends RefCounted
## The cabin log, split by the kind of thing that was said: thoughts, things looked into,
## and radio calls. Open a category, then an entry.
##
## There is no HUD button. Open it from the fixed radio (when nothing is incoming),
## or with J or L. A story alert is drawn on the radio itself, not on this panel.
##
## Owned, updated, and drawn by overlay.gd when panel == "journal".

const Px := preload("res://scripts/ui/pixel_draw.gd")

const PANEL := Rect2(36, 18, 408, 214)
const VIEW := Rect2(44, 34, 392, 190)
const CLOSE := Vector2(436, 25)
const PAGE_PREV := Rect2(396, 20, 11, 11)
const PAGE_NEXT := Rect2(410, 20, 11, 11)
const BACK_BTN := Rect2(50, 40, 44, 13)

const CARDS_PER_PAGE := 3
const CARD_X := 50
const LIST_Y := 58
const CARD_W := 380
const CARD_H := 46
const CARD_STEP := 50
const CAT_Y := 48
const CAT_H := 50
const CAT_STEP := 56
const LINE_SPACING := 9
## id, title, the line under it
const CATEGORIES := [
	["thought", "THOUGHTS", "THINGS YOU TOLD YOURSELF"],
	["inspect", "LOOKED AT", "THINGS YOU LOOKED INTO"],
	["radio", "RADIO", "CALLS YOU HEARD"],
]

var category := ""                      # "", or one of the category ids above
var selected_id := ""
var page := 0

var _overlay: Control
var _title_col: Color
var _paper: Color
var _paper_lo: Color
var _ink: Color
var _pencil: Color
var _badge_col: Color
var _radio_col: Color


func _init(overlay: Control, palette: Array) -> void:
	_overlay = overlay
	_title_col = Px.palette_color(palette, Color8(121, 183, 196))
	_paper = Px.palette_color(palette, Color8(249, 228, 177))
	_paper_lo = Px.palette_color(palette, Color8(224, 198, 142))
	_ink = Px.palette_color(palette, Color8(63, 31, 14))
	_pencil = Px.palette_color(palette, Color8(99, 68, 50))
	_badge_col = Px.palette_color(palette, Color8(239, 180, 94))
	_radio_col = Px.palette_color(palette, Color8(121, 183, 196))


func in_detail() -> bool:
	return selected_id != ""


## one step toward the front of the log: an entry, then its category, then the category list
func can_step_back() -> bool:
	return selected_id != "" or category != ""


func step_back() -> void:
	if selected_id != "":
		selected_id = ""
	elif category != "":
		category = ""
		page = 0


## panel closed: next time it opens on the categories
func leave_detail() -> void:
	selected_id = ""
	category = ""
	page = 0


func over_close(p: Vector2) -> bool:
	return absf(p.x - CLOSE.x) < 6 and absf(p.y - CLOSE.y) < 6


func _category_of(entry: Dictionary) -> String:
	var stored := str(entry.get("category", ""))
	if stored != "":
		return stored
	if entry.get("kind", "") == "radio" or str(entry.get("id", "")).begins_with("radio_"):
		return "radio"
	if str(entry.get("id", "")).begins_with("inspect_"):
		return "inspect"
	return "thought"


func _logs_in(which: String) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for item in GameState.cabin_log:
		if _category_of(item) == which:
			logs.append(item)
	logs.reverse()
	return logs


func _unread_in(which: String) -> int:
	var n := 0
	for item in GameState.cabin_log:
		if _category_of(item) == which and item.get("unread", false):
			n += 1
	return n


func _total_pages() -> int:
	if category == "":
		return 1
	return maxi(1, ceili(float(_logs_in(category).size()) / float(CARDS_PER_PAGE)))


func _card_rect(slot: int) -> Rect2:
	return Rect2(CARD_X, LIST_Y + slot * CARD_STEP, CARD_W, CARD_H)


func _cat_rect(slot: int) -> Rect2:
	return Rect2(CARD_X, CAT_Y + slot * CAT_STEP, CARD_W, CAT_H)


func wheel(up: bool) -> void:
	if category == "" or selected_id != "":
		return
	var tp := _total_pages()
	if tp <= 1:
		return
	var next_page := clampi(page + (-1 if up else 1), 0, tp - 1)
	if next_page != page:
		page = next_page
		UiSounds.play("tick")


## False = the press was outside the panel (the caller closes it).
func press(p: Vector2) -> bool:
	if selected_id != "" or category != "":
		if BACK_BTN.has_point(p):
			step_back()
			UiSounds.play("tick")
			return true
	if selected_id != "":
		return PANEL.has_point(p)

	if category == "":
		for i in CATEGORIES.size():
			if _cat_rect(i).has_point(p):
				category = CATEGORIES[i][0]
				page = 0
				UiSounds.play("click")
				return true
		return PANEL.has_point(p)

	var tp := _total_pages()
	if tp > 1:
		if PAGE_PREV.has_point(p) and page > 0:
			page -= 1
			UiSounds.play("tick")
			return true
		if PAGE_NEXT.has_point(p) and page < tp - 1:
			page += 1
			UiSounds.play("tick")
			return true

	var logs := _logs_in(category)
	var start_idx := page * CARDS_PER_PAGE
	var end_idx := mini(start_idx + CARDS_PER_PAGE, logs.size())
	for i in range(start_idx, end_idx):
		var r := _card_rect(i - start_idx)
		if r.has_point(p):
			var entry: Dictionary = logs[i]
			selected_id = str(entry.get("id", ""))
			GameState.mark_log_read(selected_id)
			UiSounds.play("click")
			return true

	return PANEL.has_point(p)


func hover_label(p: Vector2) -> String:
	if over_close(p):
		return "CLOSE"
	if selected_id != "":
		if BACK_BTN.has_point(p):
			return "BACK"
		return ""
	if category == "":
		for i in CATEGORIES.size():
			if _cat_rect(i).has_point(p):
				return "OPEN " + CATEGORIES[i][1]
		return ""
	if BACK_BTN.has_point(p):
		return "ALL CATEGORIES"
	var tp := _total_pages()
	if tp > 1:
		if PAGE_PREV.has_point(p) and page > 0:
			return "PREVIOUS PAGE"
		if PAGE_NEXT.has_point(p) and page < tp - 1:
			return "NEXT PAGE"
	var logs := _logs_in(category)
	var start_idx := page * CARDS_PER_PAGE
	var end_idx := mini(start_idx + CARDS_PER_PAGE, logs.size())
	for i in range(start_idx, end_idx):
		if _card_rect(i - start_idx).has_point(p):
			return "READ ENTRY"
	return ""


# ---------------------------------------------------------------- drawing
func draw(open: float, _now: float, cur: Vector2) -> void:
	var rows := int(PANEL.size.y * open)
	if rows <= 0:
		return
	var top := PANEL.position.y + int(PANEL.size.y - rows) / 2
	var body := Rect2(PANEL.position.x, top, PANEL.size.x, rows)
	_overlay.draw_rect(body, _overlay.panel_col)
	Px.frame(_overlay, body, _overlay.panel_hi)
	if open < 1.0:
		return

	_draw_title_bar(cur)

	# Stardew-style parchment page interior
	_overlay.draw_rect(VIEW, _paper)
	Px.frame(_overlay, VIEW, _ink)
	Px.frame(_overlay, VIEW.grow(1), _overlay.panel_lo)

	if selected_id != "":
		_draw_detail(cur)
	elif category == "":
		_draw_categories(cur)
	else:
		_draw_list(cur)


func _draw_title_bar(cur: Vector2) -> void:
	var title := "CABIN LOG"
	if category != "":
		title = _category_label(category)
	Px.text(_overlay, title, PANEL.position + Vector2(7, 4), _title_col, Px.INK)

	var tp := _total_pages()
	if category != "" and selected_id == "" and tp > 1:
		var page_label := "%d/%d" % [page + 1, tp]
		Px.text(_overlay, page_label, Vector2(PAGE_PREV.position.x - 4 - Px.text_width(page_label), PAGE_PREV.position.y + 2), Px.WHITE)
		for b in [[PAGE_PREV, page > 0, -1], [PAGE_NEXT, page < tp - 1, 1]]:
			var r: Rect2 = b[0]
			var live: bool = b[1]
			var dir: int = b[2]
			_overlay.draw_rect(r, _overlay.panel_lo)
			Px.frame(_overlay, r, Px.WHITE if r.has_point(cur) and live else _overlay.panel_hi)
			var col: Color = Px.WHITE if live else _overlay.panel_hi
			var cx := int(r.position.x) + 5
			var cy := int(r.position.y) + 5
			for dx in 3:
				_overlay.draw_rect(Rect2(cx + dir * (dx - 1), cy - (2 - dx), 1, 1 + 2 * (2 - dx)), col)

	var cb := Rect2(CLOSE - Vector2(5, 5), Vector2(11, 11))
	_overlay.draw_rect(cb, _overlay.panel_lo)
	Px.frame(_overlay, cb, Px.WHITE if over_close(cur) else _overlay.panel_hi)
	Px.text(_overlay, "X", cb.position + Vector2(3, 2), Px.WHITE)


func _category_label(id: String) -> String:
	for row in CATEGORIES:
		if row[0] == id:
			return row[1]
	return "LOG"


func _draw_back(cur: Vector2) -> void:
	var hot := BACK_BTN.has_point(cur)
	_overlay.draw_rect(BACK_BTN, _paper_lo if hot else _paper)
	Px.frame(_overlay, BACK_BTN, _ink if hot else _pencil)
	var ax := int(BACK_BTN.position.x) + 5
	var ay := int(BACK_BTN.position.y) + 6
	for dx in 3:
		_overlay.draw_rect(Rect2(ax + dx, ay - dx, 1, 1 + 2 * dx), _ink)
	Px.text(_overlay, "BACK", BACK_BTN.position + Vector2(11, 3), _ink)


func _draw_categories(cur: Vector2) -> void:
	for i in CATEGORIES.size():
		var row: Array = CATEGORIES[i]
		var r := _cat_rect(i)
		var hot := r.has_point(cur)
		var count := _logs_in(row[0]).size()
		var unread := _unread_in(row[0])
		_overlay.draw_rect(r, _paper_lo if hot else _paper)
		Px.frame(_overlay, r, _ink if hot else _pencil)
		var name_col: Color = _radio_col if row[0] == "radio" else _ink
		Px.text(_overlay, row[1], Vector2(r.position.x + 10, r.position.y + 10), name_col)
		Px.text(_overlay, row[2], Vector2(r.position.x + 10, r.position.y + 24), _pencil)
		var count_str := "%d" % count
		Px.text(_overlay, count_str, Vector2(r.end.x - 10 - Px.text_width(count_str), r.position.y + 10), _ink)
		if unread > 0:
			var new_str := "NEW"
			var nw := Px.text_width(new_str) + 4
			var nr := Rect2(r.end.x - 10 - nw, r.position.y + 28, nw, 12)
			_overlay.draw_rect(nr, _badge_col)
			Px.frame(_overlay, nr, _ink)
			Px.text(_overlay, new_str, nr.position + Vector2(2, 2), _ink)


func _draw_list(cur: Vector2) -> void:
	_draw_back(cur)
	var logs := _logs_in(category)
	if logs.is_empty():
		var msg := "NOTHING IN THIS LOG YET."
		Px.text(_overlay, msg, Vector2(VIEW.get_center().x - Px.text_width(msg) / 2.0, VIEW.get_center().y).floor(), _ink)
		return

	var start_idx := page * CARDS_PER_PAGE
	var end_idx := mini(start_idx + CARDS_PER_PAGE, logs.size())
	for i in range(start_idx, end_idx):
		var entry := logs[i]
		var r := _card_rect(i - start_idx)
		var hot := r.has_point(cur)
		_overlay.draw_rect(r, _paper_lo if hot else _paper)
		Px.frame(_overlay, r, _ink if hot else _pencil)

		var title: String = str(entry.get("title", "NOTE"))
		Px.text(_overlay, title, Vector2(r.position.x + 10, r.position.y + 6), _ink)

		var day_str := "DAY %d" % entry.get("day", 1)
		var dx := r.end.x - Px.text_width(day_str) - 6
		Px.text(_overlay, day_str, Vector2(dx, r.position.y + 6), _pencil)

		if entry.get("unread", false):
			var new_w := Px.text_width("NEW") + 4
			var nr := Rect2(dx - new_w - 4, r.position.y + 4, new_w, 10)
			_overlay.draw_rect(nr, _badge_col)
			Px.frame(_overlay, nr, _ink)
			Px.text(_overlay, "NEW", nr.position + Vector2(2, 2), _ink)

		var speaker: String = str(entry.get("speaker", ""))
		Px.text(_overlay, speaker, Vector2(r.position.x + 10, r.position.y + 18), _pencil)

		var lines: Array = entry.get("lines", [])
		var preview: String = _line_text(lines[0]) if not lines.is_empty() else ""
		var max_preview_w := int(r.size.x) - 24
		while Px.text_width(preview) > max_preview_w and preview.length() > 4:
			preview = preview.substr(0, preview.length() - 4) + "..."
		Px.text(_overlay, preview, Vector2(r.position.x + 10, r.position.y + 30), _ink)


func _draw_detail(cur: Vector2) -> void:
	var entry: Dictionary = {}
	for item in GameState.cabin_log:
		if item.get("id", "") == selected_id:
			entry = item
			break
	if entry.is_empty():
		selected_id = ""
		return

	_draw_back(cur)

	var day_str := "LOGGED DAY %d" % entry.get("day", 1)
	Px.text(_overlay, day_str, Vector2(VIEW.end.x - Px.text_width(day_str) - 8, BACK_BTN.position.y + 3), _pencil)

	var title: String = str(entry.get("title", "NOTE"))
	var speaker: String = _category_label(_category_of(entry)) + " / " + str(entry.get("speaker", ""))
	Px.text(_overlay, title, Vector2(VIEW.position.x + 10, BACK_BTN.end.y + 7), _ink)
	Px.text(_overlay, speaker, Vector2(VIEW.position.x + 10, BACK_BTN.end.y + 17), _pencil)

	# Horizontal rule
	var rule_y := BACK_BTN.end.y + 28
	_overlay.draw_rect(Rect2(VIEW.position.x + 10, rule_y, VIEW.size.x - 20, 1), _pencil)

	# Full transcript wrapped onto the parchment page
	var y := rule_y + 7
	var max_w := int(VIEW.size.x) - 20
	var lines: Array = entry.get("lines", [])
	for line in lines:
		var wrapped := _wrap_text(_line_text(line), max_w)
		for row in wrapped:
			if y + LINE_SPACING > VIEW.end.y - 6:
				break
			Px.text(_overlay, row, Vector2(VIEW.position.x + 10, y), _ink)
			y += LINE_SPACING
		y += 4


func _line_text(line) -> String:
	return str(line.get("text", "")) if line is Dictionary else str(line)


func _wrap_text(text: String, max_width: int) -> Array[String]:
	var words := text.split(" ")
	var result: Array[String] = []
	var cur := ""
	for w in words:
		if w.is_empty():
			continue
		var test := cur + (" " if cur != "" else "") + w
		if Px.text_width(test) <= max_width:
			cur = test
		else:
			if cur != "":
				result.append(cur)
			cur = w
	if cur != "":
		result.append(cur)
	return result
