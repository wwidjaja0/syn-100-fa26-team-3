extends RefCounted
## The microfiche panel: opens over the room when the player clicks the microfiche display, and shows
## the world map (microfiche_map.gd) through a fixed window.
##
## What it shows:
##   * the blank outline sheet, with the printed map showing through inside every revealed circle
##     (GameState.revealed: the Pacific Northwest from the start, then a patch per station reached);
##   * a mark and callsign per contacted station (GameState.contacted); hovering one shows a card
##     with that station's problems (data/stations.json);
##   * an overview of the whole sheet in the corner.
## Controls: drag or WASD / arrows to pan; mouse wheel, the title bar's - / + or the - / = keys to
## zoom; a click on a revealed area jumps straight to its 4x detail map.
##
## overlay.gd owns this, forwards the mouse to it while the "fiche" panel is open, and calls draw().

const Px := preload("res://scripts/ui/pixel_draw.gd")
const MicroficheMap := preload("res://scripts/ui/microfiche/microfiche_map.gd")
const THUMB := preload("res://ui/fiche_thumb.png")

# layout on the 480x270 canvas
const PANEL := Rect2(24, 14, 432, 222)      # the whole panel
const VIEW := Rect2(30, 30, 420, 200)       # the window onto the sheet
const CLOSE := Vector2(447, 21)             # close box centre
const ZOOM_MINUS := Rect2(414, 16, 11, 11)  # title-bar zoom buttons
const ZOOM_PLUS := Rect2(428, 16, 11, 11)
const TITLE := "MICROFICHE - WORLD SHEET 01"
const SCALE_NAMES := ["1/4", "1/2", "X1"]   # per world level; detail maps show "X4"

const PAN_SPEED := 360.0                    # sheet px per second with WASD / arrows
const MARK_HIT := 6.0                       # px from a mark that counts as hovering it
const CLICK_SLOP := 3.0                     # a press that moves less than this is a click, not a drag
const REVEAL_SIDES := 64                    # polygon sides of a revealed circle

var map: MicroficheMap
var hover_station := ""                     # contacted station under the cursor
var hover_area := ""                        # revealed area under the cursor (world levels only)
var _overlay: Control
var _drag = null                            # [cursor, offset] while the button is down
# palette-snapped colours
var _mark: Color                            # station marks
var _title: Color
var _pencil: Color                          # revealed areas' dotted edge
var _paper: Color                           # station cards
var _ink: Color


func _init(overlay: Control, palette: Array) -> void:
	_overlay = overlay
	map = MicroficheMap.new(VIEW.size)
	_mark = Px.palette_color(palette, Color(0.95, 0.40, 0.15))
	_title = Px.palette_color(palette, Color8(121, 183, 196))
	_pencil = Px.palette_color(palette, Color8(99, 68, 50))
	_paper = Px.palette_color(palette, Color8(249, 228, 177))
	_ink = Px.palette_color(palette, Color8(63, 31, 14))


# ---------------------------------------------------------------- coordinates
## screen pixel of a latitude / longitude (may be outside the window)
func screen_px(lat: float, lon: float) -> Vector2:
	return VIEW.position + map.sheet_px(lat, lon) - map.offset.floor()


func center_on(lat: float, lon: float) -> void:
	map.center_on(lat, lon)


func zoomed() -> bool:
	return map.zoomed()


func leave_detail() -> void:
	map.leave_detail()


## one zoom step around a screen point (the window's centre if the point is outside it)
func zoom_by(dir: int, screen_anchor: Vector2) -> void:
	var before := [map.level, map.zoom_area]
	map.zoom_by(dir, screen_anchor - VIEW.position)
	if [map.level, map.zoom_area] != before:
		UiSounds.play("tick")


## the revealed area under a screen pixel ("" on a detail map, or outside the window)
func area_at(p: Vector2) -> String:
	if map.zoomed() or not VIEW.has_point(p):
		return ""
	return map.area_at_latlon(map.window_latlon(p - VIEW.position))


## the contacted station marked under a screen pixel, or ""
func station_at(p: Vector2) -> String:
	if not VIEW.has_point(p):
		return ""
	for id in GameState.contacted:
		var s: Dictionary = GameState.stations[id]
		if screen_px(s.lat, s.lon).distance_to(p) <= MARK_HIT:
			return id
	return ""


# ---------------------------------------------------------------- input
## per frame while open: follow a drag, or pan with WASD / arrows (keys = direction)
func update(cursor: Vector2, delta: float, keys: Vector2) -> void:
	if _drag != null:
		if cursor.distance_to(_drag[0]) >= CLICK_SLOP:
			map.offset = _drag[1] - (cursor - _drag[0])
			map.clamp_offset()
	else:
		map.pan(keys.limit_length(1.0) * PAN_SPEED * delta)
	var dragging := _drag != null and cursor.distance_to(_drag[0]) >= CLICK_SLOP
	hover_station = station_at(cursor) if not dragging else ""
	hover_area = area_at(cursor) if not dragging and hover_station == "" else ""


## the button went down. False = the press was outside the panel (the caller closes it).
func press(p: Vector2) -> bool:
	if ZOOM_MINUS.has_point(p):
		zoom_by(-1, VIEW.get_center())
		return true
	if ZOOM_PLUS.has_point(p):
		zoom_by(1, VIEW.get_center())
		return true
	if VIEW.has_point(p):
		_drag = [p, map.offset]
	return PANEL.has_point(p)


## the button came up: a press that hardly moved is a click, and a click on a revealed area zooms
## straight into its detail map
func release(p: Vector2) -> void:
	if _drag != null and p.distance_to(_drag[0]) < CLICK_SLOP:
		var id := area_at(p)
		if id != "" and station_at(p) == "":
			map.zoom_in(id, map.window_latlon(p - VIEW.position), p - VIEW.position)
			if map.zoomed():
				UiSounds.play("tick")
	_drag = null


## mouse wheel: one zoom step around the cursor
func wheel(up: bool, p: Vector2) -> void:
	zoom_by(1 if up else -1, p)


func over_close(p: Vector2) -> bool:
	return absf(p.x - CLOSE.x) < 6 and absf(p.y - CLOSE.y) < 6


## the label to show at the cursor ("" for none)
func hover_label(p: Vector2) -> String:
	if over_close(p):
		return "CLOSE"
	if ZOOM_MINUS.has_point(p):
		return "ZOOM OUT"
	if ZOOM_PLUS.has_point(p) or hover_area != "":
		return "ZOOM IN"
	return ""


# ---------------------------------------------------------------- drawing
## open is 0..1, how far the panel has unrolled (it grows from its middle row)
func draw(open: float, cur: Vector2) -> void:
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
	var blank: Array = map.blank_source()
	_overlay.draw_texture_rect_region(blank[0], VIEW, blank[1])
	_draw_revealed()
	Px.frame(_overlay, VIEW.grow(1), Px.INK)
	for id in GameState.contacted:
		_draw_mark(id)
	_draw_overview()
	if hover_station != "":
		_draw_card(hover_station)


func _draw_title_bar(cur: Vector2) -> void:
	var title := TITLE if not map.zoomed() else "MICROFICHE - %s" % map.area_name(map.zoom_area)
	Px.text(_overlay, title, PANEL.position + Vector2(7, 4), _title, Px.INK)
	var scale_name: String = "X4" if map.zoomed() else SCALE_NAMES[mini(map.level, SCALE_NAMES.size() - 1)]
	Px.text(_overlay, scale_name, Vector2(ZOOM_MINUS.position.x - 4 - Px.text_width(scale_name), ZOOM_MINUS.position.y + 2), Px.WHITE)
	for b in [[ZOOM_MINUS, map.can_zoom_out(), false], [ZOOM_PLUS, map.can_zoom_in(), true]]:
		var r: Rect2 = b[0]
		var live: bool = b[1]
		_overlay.draw_rect(r, _overlay.panel_lo)
		Px.frame(_overlay, r, Px.WHITE if r.has_point(cur) and live else _overlay.panel_hi)
		var c := r.get_center().floor()
		var col: Color = Px.WHITE if live else _overlay.panel_hi
		_overlay.draw_rect(Rect2(c.x - 2, c.y, 5, 1), col)          # minus
		if b[2]:
			_overlay.draw_rect(Rect2(c.x, c.y - 2, 1, 5), col)      # plus
	var cb := Rect2(CLOSE - Vector2(5, 5), Vector2(11, 11))
	_overlay.draw_rect(cb, _overlay.panel_lo)
	Px.frame(_overlay, cb, Px.WHITE if over_close(cur) else _overlay.panel_hi)
	for i in range(-2, 3):                                           # the X
		_overlay.draw_rect(Rect2(CLOSE + Vector2(i, i), Vector2.ONE), Px.WHITE)
		_overlay.draw_rect(Rect2(CLOSE + Vector2(i, -i), Vector2.ONE), Px.WHITE)


## the printed map inside every revealed circle, clipped to the window, with a dotted pencil edge
func _draw_revealed() -> void:
	var o := map.offset.floor()
	var view_poly := PackedVector2Array([VIEW.position, Vector2(VIEW.end.x, VIEW.position.y), VIEW.end,
			Vector2(VIEW.position.x, VIEW.end.y)])
	var ppd := map.ppd()
	var circles := []                           # [screen centre, radius px]
	for a: Dictionary in GameState.revealed:
		var c := screen_px(a.lat, a.lon).round()
		var r: float = a.radius_deg * ppd
		circles.append([c, r])
		if not Rect2(c - Vector2(r, r), Vector2(r, r) * 2).intersects(VIEW):
			continue
		var pts := PackedVector2Array()
		for i in REVEAL_SIDES:
			pts.append((c + Vector2.from_angle(TAU * i / REVEAL_SIDES) * r).round())
		var src: Array = map.print_source(a.id)
		var tex: Texture2D = src[0]
		var tex_size := Vector2(tex.get_size())
		for poly in Geometry2D.intersect_polygons(pts, view_poly):
			var uvs := PackedVector2Array()
			for p in poly:
				var ll := map.sheet_latlon(p - VIEW.position + o)
				uvs.append(src[1].call(ll.x, ll.y) / tex_size)
			_overlay.draw_polygon(poly, PackedColorArray([Color.WHITE]), uvs, tex)
	# the pencil edge, skipping stretches inside another revealed circle
	for i in circles.size():
		var c: Vector2 = circles[i][0]
		var r: float = circles[i][1]
		var n := mini(int(TAU * r / 2.0), 6000)
		for k in n:
			var p := (c + Vector2.from_angle(TAU * k / n) * r).floor()
			if not VIEW.grow(-1).has_point(p):
				continue
			var inside := false
			for j in circles.size():
				if j != i and p.distance_to(circles[j][0]) < circles[j][1] - 1.0:
					inside = true
					break
			if not inside:
				_overlay.draw_rect(Rect2(p, Vector2.ONE), _pencil)


func _draw_mark(id: String) -> void:
	var s: Dictionary = GameState.stations[id]
	var p := screen_px(s.lat, s.lon).floor()
	if not VIEW.grow(-2).has_point(p):
		return
	var hot := id == hover_station
	Px.ring(_overlay, p, 3.0, Px.INK)
	Px.ring(_overlay, p, 2.0, Px.WHITE if hot else _mark)
	_overlay.draw_rect(Rect2(p, Vector2.ONE), Px.WHITE if hot else _mark)
	var label: String = s.callsign
	var lp := p + Vector2(6, -4)
	lp.x = minf(lp.x, VIEW.end.x - Px.text_width(label) - 2)
	lp.y = clampf(lp.y, VIEW.position.y + 2, VIEW.end.y - 9)
	Px.text(_overlay, label, lp, Px.WHITE if hot else _mark, Px.INK)


## a station's card: its name, callsign and every problem it radioed in
func _draw_card(id: String) -> void:
	var s: Dictionary = GameState.stations[id]
	var lines: Array[String] = [s.name, "CALL " + s.callsign]
	for p in s.problems:
		lines.append("- " + p)
	var w := 0
	for l in lines:
		w = maxi(w, Px.text_width(l))
	var size := Vector2(w + 10, lines.size() * 9 + 7)
	var at := screen_px(s.lat, s.lon).floor() + Vector2(8, 6)
	at.x = clampf(at.x, VIEW.position.x + 2, VIEW.end.x - size.x - 2)
	at.y = clampf(at.y, VIEW.position.y + 2, VIEW.end.y - size.y - 2)
	var r := Rect2(at, size)
	_overlay.draw_rect(r, _paper)
	Px.frame(_overlay, r, _pencil)
	Px.frame(_overlay, r.grow(1), Px.INK)
	for i in lines.size():
		Px.text(_overlay, lines[i], at + Vector2(5, 4 + i * 9), _mark if i == 0 else _ink)


## the whole world in the window's corner, with where the window is and every station's mark
func _draw_overview() -> void:
	var ts := Vector2(THUMB.get_size())
	var at := VIEW.end - ts - Vector2(4, 4)
	_overlay.draw_rect(Rect2(at, ts).grow(1), Px.INK)
	_overlay.draw_texture(THUMB, at)
	var k: float = map.meta.thumb_scale
	var o := Vector2(map.meta.origin_px[0], map.meta.origin_px[1])
	var tl := map.sheet_latlon(map.offset.floor())
	var br := map.sheet_latlon(map.offset.floor() + VIEW.size)
	var a := ((map.world_px(tl.x, tl.y) - o) / k).floor()
	var b := ((map.world_px(br.x, br.y) - o) / k).floor()
	var r := Rect2(at + a, (b - a).max(Vector2(2, 2))).intersection(Rect2(at, ts))
	if r.size.x > 0 and r.size.y > 0:
		Px.frame(_overlay, r, Px.WHITE)
	for id in GameState.contacted:
		var s: Dictionary = GameState.stations[id]
		var p := at + ((map.world_px(s.lat, s.lon) - o) / k).floor()
		_overlay.draw_rect(Rect2(p, Vector2.ONE), _mark)
