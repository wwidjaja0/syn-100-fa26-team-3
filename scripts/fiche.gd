extends RefCounted
## The microfiche display's screen: a world map panned around under a fixed window
## (pipeline/scene/make_fiche.py). The sheet starts as a blank outline map (ui/fiche_blank.png); the
## printed map (ui/fiche_world.png) shows through only inside revealed areas (GameState.revealed): the
## Pacific Northwest from the start, plus a patch around every station reached over the radio. Each
## station is marked; hovering a mark shows its problems.
##
## Zoom: the world sheet comes at 1/4, 1/2 and full scale (meta.levels), and every revealed area has
## a 4x detail map (ui/fiche_detail_<id>.png). Wheel, the title bar's - / + and the - / = keys step
## through them; clicking a revealed area jumps straight to its detail map.
## Pan: drag, push the cursor against the window's edges (anywhere past an edge = full speed), or
## WASD / arrow keys.
## ui.gd owns this and draws it as the "fiche" panel.

const THUMB := preload("res://ui/fiche_thumb.png")
const PANEL := Rect2(24, 14, 432, 222)      # the display on the 480x270 canvas
const VIEW := Rect2(30, 30, 420, 200)       # the window onto the sheet
const CLOSE := Vector2(447, 21)             # close box centre
const ZOOM_MINUS := Rect2(414, 16, 11, 11) # title-bar zoom buttons
const ZOOM_PLUS := Rect2(428, 16, 11, 11)
const SCALE_NAMES := ["1/4", "1/2", "X1"]   # per world level; the detail maps are X4
const TITLE := "MICROFICHE - WORLD SHEET 01"
const EDGE := 22.0                          # px inside the window where the cursor pushes the sheet
const PAN_SPEED := 360.0                    # sheet px per second at full push
const MARK_HIT := 6.0                       # px from a mark that counts as hovering it
const CLICK_SLOP := 3.0                     # a press that moves less than this is a click, not a drag
const REVEAL_SIDES := 64                    # polygon sides of a revealed circle

var ui: Control
var meta: Dictionary
var offset := Vector2.ZERO                  # pixel of the current sheet at the window's top-left
var level := 2                              # world sheet zoom level (index into meta.levels)
var zoom_area := ""                         # "" = the world sheet, else the revealed area's 4x detail map
var hover_station := ""
var hover_area := ""                        # revealed area under the cursor (world view)
var mark_col: Color
var line_col: Color
var edge_col: Color
var paper_col: Color
var ink_col: Color
var _drag = null                            # [cursor, offset] while the button is down
var _textures := {}                         # ui/ file name -> Texture2D, loaded on first use


func _init(owner_ui: Control, palette: Array) -> void:
	ui = owner_ui
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://ui/fiche_meta.json"))
	mark_col = ui._pal(palette, Color(0.95, 0.40, 0.15))
	line_col = ui._pal(palette, Color8(121, 183, 196))
	edge_col = ui._pal(palette, Color8(99, 68, 50))
	paper_col = ui._pal(palette, Color8(249, 228, 177))
	ink_col = ui._pal(palette, Color8(63, 31, 14))
	level = meta.levels.size() - 1
	center_on(meta.home[0], meta.home[1])     # the shelter


func _tex(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load("res://ui/" + file)
	return _textures[file]


# ---------------------------------------------------------------- projections
## pixel of a latitude / longitude on world level i's sheet
func level_px(i: int, lat: float, lon: float) -> Vector2:
	var ppd: float = meta.levels[i].px_per_deg
	return Vector2(meta.origin_px[0] + (lon - meta.lon_left) * ppd, meta.origin_px[1] + (meta.lat_top - lat) * ppd)


## pixel on the main (full-scale) world sheet, which the overview and other areas' prints use
func world_px(lat: float, lon: float) -> Vector2:
	return level_px(meta.levels.size() - 1, lat, lon)


## pixel of a latitude / longitude on whatever sheet is showing (a world level, or a detail map)
func sheet_px(lat: float, lon: float) -> Vector2:
	if zoom_area == "":
		return level_px(level, lat, lon)
	var d: Dictionary = meta.details[zoom_area]
	return Vector2((lon - d.lon_left) * d.px_per_deg, (d.lat_top - lat) * d.px_per_deg)


## latitude / longitude under a pixel of the showing sheet
func sheet_latlon(p: Vector2) -> Vector2:
	if zoom_area == "":
		var ppd: float = meta.levels[level].px_per_deg
		return Vector2(meta.lat_top - (p.y - meta.origin_px[1]) / ppd, meta.lon_left + (p.x - meta.origin_px[0]) / ppd)
	var d: Dictionary = meta.details[zoom_area]
	return Vector2(d.lat_top - p.y / d.px_per_deg, d.lon_left + p.x / d.px_per_deg)


func _ppd() -> float:
	return meta.levels[level].px_per_deg if zoom_area == "" else meta.details[zoom_area].px_per_deg


func _sheet_size() -> Vector2:
	var s: Array = meta.levels[level].size if zoom_area == "" else meta.details[zoom_area].size
	return Vector2(s[0], s[1])


## screen pixel of a latitude / longitude (may be outside the window)
func screen_px(lat: float, lon: float) -> Vector2:
	return VIEW.position + sheet_px(lat, lon) - offset.floor()


func center_on(lat: float, lon: float) -> void:
	offset = sheet_px(lat, lon) - VIEW.size / 2.0
	_clamp()


func _clamp() -> void:
	var room := _sheet_size() - VIEW.size
	for a in 2:                             # a sheet smaller than the window sits in its middle
		offset[a] = clampf(offset[a], 0.0, room[a]) if room[a] >= 0.0 else room[a] / 2.0


# ---------------------------------------------------------------- zoom
func zoomed() -> bool:
	return zoom_area != ""


## zoom into a revealed area's detail map, keeping `at` (lat, lon) under screen pixel `screen`
func zoom_in(id: String, at: Vector2, screen: Vector2) -> void:
	if not meta.details.has(id):
		return
	zoom_area = id
	_keep(at, screen)


## leave a detail map for the full-scale world sheet, staying over the same place
func leave_detail() -> void:
	if zoom_area == "":
		return
	var c := sheet_latlon(offset + VIEW.size / 2.0)
	zoom_area = ""
	level = meta.levels.size() - 1
	center_on(c.x, c.y)


## one step in (+1) or out (-1) through 1/4, 1/2, full sheet, detail; `anchor` stays put on screen.
## Past the full sheet, zooming in needs a revealed area under the anchor.
func zoom_by(dir: int, anchor: Vector2) -> void:
	if not VIEW.has_point(anchor):
		anchor = VIEW.get_center()
	var at := sheet_latlon(anchor - VIEW.position + offset.floor())
	if dir > 0:
		if zoom_area != "":
			return
		if level < meta.levels.size() - 1:
			level += 1
		else:
			var id := _area_at_latlon(at)
			if id == "":
				return
			zoom_area = id
	else:
		if zoom_area != "":
			zoom_area = ""
		elif level > 0:
			level -= 1
		else:
			return
	_keep(at, anchor)


func zoom_out() -> void:
	zoom_by(-1, VIEW.get_center())


func _keep(at: Vector2, screen: Vector2) -> void:
	offset = sheet_px(at.x, at.y) - (screen - VIEW.position)
	_clamp()


## the name shown in the title while zoomed
func _area_name(id: String) -> String:
	if GameState.stations.has(id):
		return GameState.stations[id].name
	for a in GameState.revealed:
		if a.id == id:
			return a.get("name", id.to_upper())
	return id.to_upper()


## the revealed area (with a detail map) under a screen pixel, world view only
func area_at(p: Vector2) -> String:
	if zoom_area != "" or not VIEW.has_point(p):
		return ""
	return _area_at_latlon(sheet_latlon(p - VIEW.position + offset.floor()))


func _area_at_latlon(ll: Vector2) -> String:
	for i in range(GameState.revealed.size() - 1, -1, -1):
		var a: Dictionary = GameState.revealed[i]
		if meta.details.has(a.id) and _deg_dist(ll, Vector2(a.lat, a.lon)) <= a.radius_deg:
			return a.id
	return ""


## distance in "sheet degrees" (equirectangular, like the circles are drawn)
func _deg_dist(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


# ---------------------------------------------------------------- input
## per frame while open. `outside` is the direction the mouse has left the game window in (or zero):
## past any edge of the window onto the sheet, the sheet scrolls at full speed that way.
func update(cursor: Vector2, delta: float, keys: Vector2, outside := Vector2.ZERO) -> void:
	if _drag != null:
		if cursor.distance_to(_drag[0]) >= CLICK_SLOP:
			offset = _drag[1] - (cursor - _drag[0])
	else:
		var push := keys + outside
		if outside == Vector2.ZERO and not _over_controls(cursor):
			if VIEW.has_point(cursor):
				var d := cursor - VIEW.position
				var e := VIEW.end - cursor
				push.x += _ramp(d.x) * -1.0 + _ramp(e.x)
				push.y += _ramp(d.y) * -1.0 + _ramp(e.y)
			else:                           # left the window onto the sheet: full speed that way
				push.x += -1.0 if cursor.x < VIEW.position.x else (1.0 if cursor.x >= VIEW.end.x else 0.0)
				push.y += -1.0 if cursor.y < VIEW.position.y else (1.0 if cursor.y >= VIEW.end.y else 0.0)
		push = push.clamp(Vector2(-1, -1), Vector2(1, 1))
		offset += push * PAN_SPEED * delta
	_clamp()
	var dragging := _drag != null and cursor.distance_to(_drag[0]) >= CLICK_SLOP
	hover_station = station_at(cursor) if not dragging else ""
	hover_area = area_at(cursor) if not dragging and hover_station == "" else ""


func _ramp(dist: float) -> float:
	return pow(clampf((EDGE - dist) / EDGE, 0.0, 1.0), 1.5)


## the button went down inside the display. False = outside it (the caller closes the display).
func press(p: Vector2) -> bool:
	if ZOOM_MINUS.has_point(p):
		zoom_by(-1, VIEW.get_center())
		return true
	if ZOOM_PLUS.has_point(p):
		zoom_by(1, VIEW.get_center())
		return true
	if VIEW.has_point(p):
		_drag = [p, offset]
	return PANEL.has_point(p)


## the button came up: a press that hardly moved is a click (zoom into a revealed area)
func release(p: Vector2) -> void:
	if _drag != null and p.distance_to(_drag[0]) < CLICK_SLOP:
		var id := area_at(p)
		if id != "" and station_at(p) == "":
			zoom_in(id, sheet_latlon(p - VIEW.position + offset.floor()), p)
	_drag = null


## mouse wheel: one zoom step around the cursor
func wheel(up: bool, p: Vector2) -> void:
	zoom_by(1 if up else -1, p)


func over_close(p: Vector2) -> bool:
	return absf(p.x - CLOSE.x) < 6 and absf(p.y - CLOSE.y) < 6


## the title bar's buttons (no edge-scrolling while aiming at them)
func _over_controls(p: Vector2) -> bool:
	return over_close(p) or ZOOM_MINUS.grow(1).has_point(p) or ZOOM_PLUS.grow(1).has_point(p)


## the hover label ui.gd shows at the cursor ("" for none)
func hover_label(p: Vector2) -> String:
	if over_close(p):
		return "CLOSE"
	if ZOOM_MINUS.has_point(p):
		return "ZOOM OUT"
	if ZOOM_PLUS.has_point(p):
		return "ZOOM IN"
	if hover_area != "":
		return "ZOOM IN"
	return ""


## the contacted station marked under a screen pixel, or ""
func station_at(p: Vector2) -> String:
	if not VIEW.has_point(p):
		return ""
	for id in GameState.contacted:
		var s: Dictionary = GameState.stations[id]
		if screen_px(s.lat, s.lon).distance_to(p) <= MARK_HIT:
			return id
	return ""


# ---------------------------------------------------------------- drawing
## scale 0..1 is the open amount (the panel unrolls vertically)
func draw(scale: float) -> void:
	var rows := int(PANEL.size.y * scale)
	if rows <= 0:
		return
	var top := PANEL.position.y + int(PANEL.size.y - rows) / 2
	ui.draw_rect(Rect2(PANEL.position.x, top, PANEL.size.x, rows), ui.panel_col)
	ui._frame(Rect2(PANEL.position.x, top, PANEL.size.x, rows), ui.panel_hi)
	if scale < 1.0:
		return
	var cur: Vector2 = ui.game.cursor
	var title := TITLE if not zoomed() else "MICROFICHE - %s" % _area_name(zoom_area)
	ui.text(title, PANEL.position + Vector2(7, 4), line_col, ui.INK)
	var scale_name: String = "X4" if zoomed() else SCALE_NAMES[mini(level, SCALE_NAMES.size() - 1)]
	ui.text(scale_name, Vector2(ZOOM_MINUS.position.x - 4 - ui.text_width(scale_name), ZOOM_MINUS.position.y + 2), ui.WHITE)
	var can_out := zoomed() or level > 0
	var can_in: bool = not zoomed() and (level < meta.levels.size() - 1 or _area_at_latlon(sheet_latlon(offset + VIEW.size / 2.0)) != "")
	for b in [[ZOOM_MINUS, can_out, false], [ZOOM_PLUS, can_in, true]]:
		var r: Rect2 = b[0]
		ui.draw_rect(r, ui.panel_lo)
		ui._frame(r, ui.WHITE if r.has_point(cur) and b[1] else ui.panel_hi)
		var c := r.get_center().floor()
		var col: Color = ui.WHITE if b[1] else ui.panel_hi
		ui.draw_rect(Rect2(c.x - 2, c.y, 5, 1), col)
		if b[2]:
			ui.draw_rect(Rect2(c.x, c.y - 2, 1, 5), col)
	var cb := Rect2(CLOSE - Vector2(5, 5), Vector2(11, 11))
	ui.draw_rect(cb, ui.panel_lo)
	ui._frame(cb, ui.WHITE if over_close(cur) else ui.panel_hi)
	for i in range(-2, 3):
		ui.draw_rect(Rect2(CLOSE + Vector2(i, i), Vector2.ONE), ui.WHITE)
		ui.draw_rect(Rect2(CLOSE + Vector2(i, -i), Vector2.ONE), ui.WHITE)

	_draw_blank()
	_draw_revealed()
	ui._frame(VIEW.grow(1), ui.INK)
	for id in GameState.contacted:
		_draw_mark(id)
	_draw_overview()
	if hover_station != "":
		_draw_note(hover_station)


## the blank outline sheet under the window (the full-scale one magnified on a detail map)
func _draw_blank() -> void:
	if not zoomed():
		ui.draw_texture_rect_region(_tex(meta.levels[level].blank), VIEW, Rect2(offset.floor(), VIEW.size))
		return
	var base: Dictionary = meta.levels[-1]
	var k := _ppd() / float(base.px_per_deg)
	var tl := sheet_latlon(offset.floor())
	ui.draw_texture_rect_region(_tex(base.blank), VIEW, Rect2(world_px(tl.x, tl.y), VIEW.size / k))


## what a revealed area prints with, and where its pixels are: [texture, pixel of lat/lon]
func _print_source(id: String) -> Array:
	if id != "" and meta.details.has(id) and zoomed():
		var d: Dictionary = meta.details[id]
		return [_tex("fiche_detail_%s.png" % id), func(lat: float, lon: float) -> Vector2:
			return Vector2((lon - d.lon_left) * d.px_per_deg, (d.lat_top - lat) * d.px_per_deg)]
	if zoomed():                                # other areas on a detail map: the full sheet, magnified
		return [_tex(meta.levels[-1].printed), world_px]
	return [_tex(meta.levels[level].printed), func(lat: float, lon: float) -> Vector2:
		return level_px(level, lat, lon)]


## the printed map inside every revealed circle, clipped to the window, with a dotted pencil edge
func _draw_revealed() -> void:
	var o := offset.floor()
	var view_poly := PackedVector2Array([VIEW.position, Vector2(VIEW.end.x, VIEW.position.y), VIEW.end,
			Vector2(VIEW.position.x, VIEW.end.y)])
	var ppd := _ppd()
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
		var src: Array = _print_source(a.id if a.id == zoom_area else "")
		var tex: Texture2D = src[0]
		var tex_size := Vector2(tex.get_size())
		for poly in Geometry2D.intersect_polygons(pts, view_poly):
			var uvs := PackedVector2Array()
			for p in poly:
				var ll := sheet_latlon(p - VIEW.position + o)
				uvs.append(src[1].call(ll.x, ll.y) / tex_size)
			ui.draw_polygon(poly, PackedColorArray([Color.WHITE]), uvs, tex)
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
				ui.draw_rect(Rect2(p, Vector2.ONE), edge_col)


func _draw_mark(id: String) -> void:
	var s: Dictionary = GameState.stations[id]
	var p := screen_px(s.lat, s.lon).floor()
	if not VIEW.grow(-2).has_point(p):
		return
	var hot := id == hover_station
	ui._ring(p, 3.0, ui.INK)
	ui._ring(p, 2.0, ui.WHITE if hot else mark_col)
	ui.draw_rect(Rect2(p, Vector2.ONE), ui.WHITE if hot else mark_col)
	var label: String = s.callsign
	var lp := p + Vector2(6, -4)
	lp.x = minf(lp.x, VIEW.end.x - ui.text_width(label) - 2)
	lp.y = clampf(lp.y, VIEW.position.y + 2, VIEW.end.y - 9)
	ui.text(label, lp, ui.WHITE if hot else mark_col, ui.INK)


## the station's card: name, callsign and each problem it radioed in
func _draw_note(id: String) -> void:
	var s: Dictionary = GameState.stations[id]
	var lines: Array[String] = [s.name, "CALL " + s.callsign]
	for p in s.problems:
		lines.append("- " + p)
	var w := 0
	for l in lines:
		w = maxi(w, ui.text_width(l))
	var size := Vector2(w + 10, lines.size() * 9 + 7)
	var at := screen_px(s.lat, s.lon).floor() + Vector2(8, 6)
	at.x = clampf(at.x, VIEW.position.x + 2, VIEW.end.x - size.x - 2)
	at.y = clampf(at.y, VIEW.position.y + 2, VIEW.end.y - size.y - 2)
	var r := Rect2(at, size)
	ui.draw_rect(r, paper_col)
	ui._frame(r, edge_col)
	ui._frame(r.grow(1), ui.INK)
	for i in lines.size():
		ui.text(lines[i], at + Vector2(5, 4 + i * 9), mark_col if i == 0 else ink_col)


## the whole sheet in the window's corner, with where you are and every mark
func _draw_overview() -> void:
	var ts := Vector2(THUMB.get_size())
	var at := VIEW.end - ts - Vector2(4, 4)
	ui.draw_rect(Rect2(at, ts).grow(1), ui.INK)
	ui.draw_texture(THUMB, at)
	var k: float = meta.thumb_scale
	var o := Vector2(meta.origin_px[0], meta.origin_px[1])
	var tl := sheet_latlon(offset.floor())
	var br := sheet_latlon(offset.floor() + VIEW.size)
	var a := ((world_px(tl.x, tl.y) - o) / k).floor()
	var b := ((world_px(br.x, br.y) - o) / k).floor()
	var r := Rect2(at + a, (b - a).max(Vector2(2, 2))).intersection(Rect2(at, ts))
	if r.size.x > 0 and r.size.y > 0:
		ui._frame(r, ui.WHITE)
	for id in GameState.contacted:
		var s: Dictionary = GameState.stations[id]
		var p := at + ((world_px(s.lat, s.lon) - o) / k).floor()
		ui.draw_rect(Rect2(p, Vector2.ONE), mark_col)
