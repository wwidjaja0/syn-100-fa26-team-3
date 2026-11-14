extends RefCounted
## Stardew Valley-inspired Radio Broadcast Journal / Log.
##
## Records radio transmissions only after the player clicks the radio and reads
## through every page of the dialogue. Accessible from the top-right HUD "LOG"
## button (with a bobbing "!" badge for unread logs) or by pressing J.
##
## Owned, updated, and drawn by overlay.gd when panel == "journal".

const Px := preload("res://scripts/ui/pixel_draw.gd")

const HUD_BTN := Rect2(392, 6, 33, 15)
const PANEL := Rect2(36, 18, 408, 214)
const VIEW := Rect2(44, 34, 392, 190)
const CLOSE := Vector2(436, 25)
const PAGE_PREV := Rect2(396, 20, 11, 11)
const PAGE_NEXT := Rect2(410, 20, 11, 11)
const BACK_BTN := Rect2(50, 40, 44, 13)

const CARDS_PER_PAGE := 4
const CARD_X := 50
const CARD_Y := 40
const CARD_W := 380
const CARD_H := 40
const CARD_STEP := 43
const LINE_SPACING := 9

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


func leave_detail() -> void:
	selected_id = ""


func over_hud_button(p: Vector2) -> bool:
	return GameState.flag("radio_fixed") and HUD_BTN.has_point(p)


func over_close(p: Vector2) -> bool:
	return absf(p.x - CLOSE.x) < 6 and absf(p.y - CLOSE.y) < 6


func _total_pages() -> int:
	return maxi(1, ceili(float(GameState.radio_log.size()) / float(CARDS_PER_PAGE)))


func _ordered_logs() -> Array[Dictionary]:
	var logs: Array[Dictionary] = GameState.radio_log.duplicate()
	logs.reverse()
	return logs


func _card_rect(slot: int) -> Rect2:
	return Rect2(CARD_X, CARD_Y + slot * CARD_STEP, CARD_W, CARD_H)


func wheel(up: bool) -> void:
	if selected_id != "":
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
	if selected_id != "":
		if BACK_BTN.has_point(p):
			leave_detail()
			UiSounds.play("tick")
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

	var logs := _ordered_logs()
	var start_idx := page * CARDS_PER_PAGE
	var end_idx := mini(start_idx + CARDS_PER_PAGE, logs.size())
	for i in range(start_idx, end_idx):
		var r := _card_rect(i - start_idx)
		if r.has_point(p):
			var entry := logs[i]
			selected_id = entry.get("id", "")
			GameState.mark_radio_log_read(selected_id)
			UiSounds.play("click")
			return true

	return PANEL.has_point(p)


func hover_label(p: Vector2) -> String:
	if over_close(p):
		return "CLOSE"
	if selected_id != "":
		if BACK_BTN.has_point(p):
			return "BACK TO LOG"
		return ""
	var tp := _total_pages()
	if tp > 1:
		if PAGE_PREV.has_point(p) and page > 0:
			return "PREVIOUS PAGE"
		if PAGE_NEXT.has_point(p) and page < tp - 1:
			return "NEXT PAGE"
	var logs := _ordered_logs()
	var start_idx := page * CARDS_PER_PAGE
	var end_idx := mini(start_idx + CARDS_PER_PAGE, logs.size())
	for i in range(start_idx, end_idx):
		if _card_rect(i - start_idx).has_point(p):
			return "READ BROADCAST"
	return ""


# ---------------------------------------------------------------- drawing
func draw_hud_button(now: float, cur: Vector2, interactive: bool) -> bool:
	if not GameState.flag("radio_fixed"):
		return false
	var hot := interactive and HUD_BTN.has_point(cur)
	var unread := GameState.unread_radio_logs > 0
	var pulse := unread and int(fmod(now / 12.0, 2.0)) == 0
	_overlay.draw_rect(HUD_BTN, _overlay.panel_col)
	var border: Color = Px.WHITE if hot else (_badge_col if pulse else _overlay.panel_hi)
	Px.frame(_overlay, HUD_BTN, border)

	# Small pixel notebook glyph on the left
	var ix := int(HUD_BTN.position.x) + 4
	var iy := int(HUD_BTN.position.y) + 4
	_overlay.draw_rect(Rect2(ix, iy, 5, 7), _paper)
	_overlay.draw_rect(Rect2(ix, iy + 1, 1, 5), _ink)
	_overlay.draw_rect(Rect2(ix + 2, iy + 2, 2, 1), _ink)
	_overlay.draw_rect(Rect2(ix + 2, iy + 4, 2, 1), _ink)

	Px.text(_overlay, "LOG", HUD_BTN.position + Vector2(12, 4), Px.WHITE, Px.INK)

	if unread:
		var bob := int(fmod(now / 6.0, 2.0))
		var badge := Rect2(HUD_BTN.position.x - 8, HUD_BTN.position.y + 2 + bob, 7, 11)
		_overlay.draw_rect(badge, _badge_col)
		Px.frame(_overlay, badge, Px.INK)
		Px.text(_overlay, "!", badge.position + Vector2(2, 2), _ink)

	return hot


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
	else:
		_draw_list(cur)


func _draw_title_bar(cur: Vector2) -> void:
	var count := GameState.radio_log.size()
	var title := "RADIO JOURNAL - %d LOGGED" % count
	Px.text(_overlay, title, PANEL.position + Vector2(7, 4), _title_col, Px.INK)

	var tp := _total_pages()
	if selected_id == "" and tp > 1:
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


func _draw_list(cur: Vector2) -> void:
	var logs := _ordered_logs()
	if logs.is_empty():
		var msg := "NO RADIO BROADCASTS LOGGED YET."
		var hint := "LISTEN TO A FULL RADIO TRANSMISSION TO RECORD IT HERE."
		Px.text(_overlay, msg, Vector2(VIEW.get_center().x - Px.text_width(msg) / 2.0, VIEW.get_center().y - 10).floor(), _ink)
		Px.text(_overlay, hint, Vector2(VIEW.get_center().x - Px.text_width(hint) / 2.0, VIEW.get_center().y + 4).floor(), _pencil)
		return

	var start_idx := page * CARDS_PER_PAGE
	var end_idx := mini(start_idx + CARDS_PER_PAGE, logs.size())
	for i in range(start_idx, end_idx):
		var entry := logs[i]
		var r := _card_rect(i - start_idx)
		var hot := r.has_point(cur)
		_overlay.draw_rect(r, _paper_lo if hot else _paper)
		Px.frame(_overlay, r, _ink if hot else _pencil)

		# Small radio icon badge on the left
		var bx := int(r.position.x) + 6
		var by := int(r.position.y) + 6
		_overlay.draw_rect(Rect2(bx, by, 7, 7), _overlay.panel_lo)
		_overlay.draw_rect(Rect2(bx + 2, by + 2, 3, 3), _radio_col)

		var title: String = entry.get("title", "RADIO BROADCAST")
		Px.text(_overlay, title, Vector2(r.position.x + 18, r.position.y + 6), _ink)

		var day_str := "DAY %d" % entry.get("day", 1)
		var dx := r.end.x - Px.text_width(day_str) - 6
		Px.text(_overlay, day_str, Vector2(dx, r.position.y + 6), _pencil)

		if entry.get("unread", false):
			var new_w := Px.text_width("NEW") + 4
			var nr := Rect2(dx - new_w - 4, r.position.y + 4, new_w, 10)
			_overlay.draw_rect(nr, _badge_col)
			Px.frame(_overlay, nr, _ink)
			Px.text(_overlay, "NEW", nr.position + Vector2(2, 2), _ink)

		var speaker: String = entry.get("speaker", "RADIO")
		Px.text(_overlay, speaker, Vector2(r.position.x + 18, r.position.y + 17), _pencil)

		var lines: Array = entry.get("lines", [])
		var preview: String = lines[0] if not lines.is_empty() else ""
		var max_preview_w := int(r.size.x) - 24
		while Px.text_width(preview) > max_preview_w and preview.length() > 4:
			preview = preview.substr(0, preview.length() - 4) + "..."
		Px.text(_overlay, preview, Vector2(r.position.x + 18, r.position.y + 27), _ink)


func _draw_detail(cur: Vector2) -> void:
	var entry: Dictionary = {}
	for item in GameState.radio_log:
		if item.get("id", "") == selected_id:
			entry = item
			break
	if entry.is_empty():
		leave_detail()
		return

	# BACK button with pixel left-arrow
	var hot := BACK_BTN.has_point(cur)
	_overlay.draw_rect(BACK_BTN, _paper_lo if hot else _paper)
	Px.frame(_overlay, BACK_BTN, _ink if hot else _pencil)
	var ax := int(BACK_BTN.position.x) + 5
	var ay := int(BACK_BTN.position.y) + 6
	for dx in 3:
		_overlay.draw_rect(Rect2(ax + dx, ay - dx, 1, 1 + 2 * dx), _ink)
	Px.text(_overlay, "BACK", BACK_BTN.position + Vector2(11, 3), _ink)

	var day_str := "LOGGED DAY %d" % entry.get("day", 1)
	Px.text(_overlay, day_str, Vector2(VIEW.end.x - Px.text_width(day_str) - 8, BACK_BTN.position.y + 3), _pencil)

	var title: String = entry.get("title", "RADIO BROADCAST")
	var speaker: String = entry.get("speaker", "RADIO")
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
		var wrapped := _wrap_text(str(line), max_w)
		for row in wrapped:
			if y + LINE_SPACING > VIEW.end.y - 6:
				break
			Px.text(_overlay, row, Vector2(VIEW.position.x + 10, y), _ink)
			y += LINE_SPACING
		y += 4


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
