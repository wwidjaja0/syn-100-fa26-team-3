extends RefCounted
## The microfiche's map sheets and where the reader is looking. No drawing and no screen layout:
## microfiche_panel.gd shows this through a fixed window and handles the mouse.
##
## The sheets come from pipeline/scene/make_fiche.py (copied into ui/ by make_ui_assets.py), and
## ui/fiche_meta.json says where every latitude/longitude lands on them:
##   * world levels (meta.levels): the whole world at 1/4, 1/2 and full scale, each as a blank
##     outline sheet and a fully printed one (fiche_blank*.png / fiche_world*.png);
##   * detail maps (meta.details): a 4x map of every area in data/stations.json
##     (fiche_detail_<id>.png), shown when the reader zooms into that area.
##
## Zoom ladder: level 0 (1/4) -> 1 (1/2) -> 2 (full) -> the detail map of a revealed area.
## All projections are equirectangular (x = longitude, y = latitude, linear).

var meta: Dictionary
var level := 0                          # which world level is showing (index into meta.levels)
var zoom_area := ""                     # "" = a world level; else the revealed area whose detail map is showing
var offset := Vector2.ZERO              # pixel of the showing sheet at the window's top-left
var view_size: Vector2                  # the window onto the sheet, in px
var _textures := {}                     # ui/ file name -> Texture2D, loaded on first use


func _init(window_size: Vector2) -> void:
	view_size = window_size
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://ui/fiche_meta.json"))
	level = top_level()
	center_on(meta.home[0], meta.home[1])     # opens over the shelter


func top_level() -> int:
	return meta.levels.size() - 1


func texture(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load("res://ui/" + file)
	return _textures[file]


# ---------------------------------------------------------------- projections
## pixel of a latitude / longitude on world level i's sheet
func level_px(i: int, lat: float, lon: float) -> Vector2:
	var ppd: float = meta.levels[i].px_per_deg
	return Vector2(meta.origin_px[0] + (lon - meta.lon_left) * ppd, meta.origin_px[1] + (meta.lat_top - lat) * ppd)


## pixel on the full-scale world sheet (the overview and other areas' prints use that one)
func world_px(lat: float, lon: float) -> Vector2:
	return level_px(top_level(), lat, lon)


## pixel of an area's detail map
func detail_px(id: String, lat: float, lon: float) -> Vector2:
	var d: Dictionary = meta.details[id]
	return Vector2((lon - d.lon_left) * d.px_per_deg, (d.lat_top - lat) * d.px_per_deg)


## pixel of a latitude / longitude on whatever sheet is showing
func sheet_px(lat: float, lon: float) -> Vector2:
	return level_px(level, lat, lon) if zoom_area == "" else detail_px(zoom_area, lat, lon)


## latitude / longitude (as Vector2(lat, lon)) under a pixel of the showing sheet
func sheet_latlon(p: Vector2) -> Vector2:
	if zoom_area == "":
		var ppd: float = meta.levels[level].px_per_deg
		return Vector2(meta.lat_top - (p.y - meta.origin_px[1]) / ppd, meta.lon_left + (p.x - meta.origin_px[0]) / ppd)
	var d: Dictionary = meta.details[zoom_area]
	return Vector2(d.lat_top - p.y / d.px_per_deg, d.lon_left + p.x / d.px_per_deg)


## latitude / longitude under a point of the window (0,0 = its top-left)
func window_latlon(p: Vector2) -> Vector2:
	return sheet_latlon(p + offset.floor())


## pixels per degree of the showing sheet
func ppd() -> float:
	return meta.levels[level].px_per_deg if zoom_area == "" else meta.details[zoom_area].px_per_deg


func sheet_size() -> Vector2:
	var s: Array = meta.levels[level].size if zoom_area == "" else meta.details[zoom_area].size
	return Vector2(s[0], s[1])


# ---------------------------------------------------------------- panning
func pan(by: Vector2) -> void:
	offset += by
	clamp_offset()


func center_on(lat: float, lon: float) -> void:
	offset = sheet_px(lat, lon) - view_size / 2.0
	clamp_offset()


## keep the window on the sheet; a sheet smaller than the window sits in its middle
func clamp_offset() -> void:
	var room := sheet_size() - view_size
	for a in 2:
		offset[a] = clampf(offset[a], 0.0, room[a]) if room[a] >= 0.0 else room[a] / 2.0


# ---------------------------------------------------------------- zoom
func zoomed() -> bool:
	return zoom_area != ""


## zoom into a revealed area's detail map, keeping `at` (lat, lon) under window point `anchor`
func zoom_in(id: String, at: Vector2, anchor: Vector2) -> void:
	if not meta.details.has(id):
		return
	zoom_area = id
	_keep(at, anchor)


## leave a detail map for the full-scale world sheet, staying over the same place
func leave_detail() -> void:
	if zoom_area == "":
		return
	var c := sheet_latlon(offset + view_size / 2.0)
	zoom_area = ""
	level = top_level()
	center_on(c.x, c.y)


## one step in (+1) or out (-1) along the zoom ladder, keeping window point `anchor` over the same
## place. Past the full-scale sheet, zooming in needs a revealed area under the anchor.
func zoom_by(dir: int, anchor: Vector2) -> void:
	if not Rect2(Vector2.ZERO, view_size).has_point(anchor):
		anchor = view_size / 2.0
	var at := window_latlon(anchor)
	if dir > 0:
		if zoom_area != "":
			return
		if level < top_level():
			level += 1
		else:
			var id := area_at_latlon(at)
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


func can_zoom_out() -> bool:
	return zoomed() or level > 0


func can_zoom_in() -> bool:
	return not zoomed() and (level < top_level() or area_at_latlon(window_latlon(view_size / 2.0)) != "")


func _keep(at: Vector2, anchor: Vector2) -> void:
	offset = sheet_px(at.x, at.y) - anchor
	clamp_offset()


# ---------------------------------------------------------------- revealed areas
## the revealed area (with a detail map) at a latitude / longitude, or "". The newest wins.
func area_at_latlon(ll: Vector2) -> String:
	for i in range(GameState.revealed.size() - 1, -1, -1):
		var a: Dictionary = GameState.revealed[i]
		# distance in "sheet degrees", the same equirectangular circles the panel draws
		if meta.details.has(a.id) and ll.distance_to(Vector2(a.lat, a.lon)) <= a.radius_deg:
			return a.id
	return ""


## the name shown in the panel's title while zoomed into an area
func area_name(id: String) -> String:
	if GameState.stations.has(id):
		return GameState.stations[id].name
	for a in GameState.revealed:
		if a.id == id:
			return a.get("name", id.to_upper())
	return id.to_upper()


## what a revealed area is printed from, and how to find a lat/lon's pixel on it:
## [texture, Callable(lat, lon) -> Vector2]. The zoomed-into area uses its detail map; on a detail
## map other areas use the full-scale world sheet (magnified); on a world level, that level's sheet.
func print_source(id: String) -> Array:
	if id != "" and id == zoom_area and meta.details.has(id):
		return [texture("fiche_detail_%s.png" % id), func(lat: float, lon: float) -> Vector2: return detail_px(id, lat, lon)]
	if zoomed():
		return [texture(meta.levels[-1].printed), world_px]
	var lv := level
	return [texture(meta.levels[lv].printed), func(lat: float, lon: float) -> Vector2: return level_px(lv, lat, lon)]


## the blank sheet under the window, and the region of it to show: [texture, Rect2]
func blank_source() -> Array:
	if not zoomed():
		return [texture(meta.levels[level].blank), Rect2(offset.floor(), view_size)]
	var base: Dictionary = meta.levels[-1]
	var tl := sheet_latlon(offset.floor())
	return [texture(base.blank), Rect2(world_px(tl.x, tl.y), view_size / (ppd() / float(base.px_per_deg)))]
