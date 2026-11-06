extends Node
## The F9 developer menu: a numbered list of shortcuts for testing (contact stations, reveal the map,
## give items, ...). F9 opens and closes it; a number key or a click runs a line; Esc closes it.
## Set ENABLED to false for a release build.
##
## To add a command, add a line to commands(): [key shown, label, Callable].

const Px := preload("res://scripts/ui/pixel_draw.gd")
const ENABLED := true
const ROW := 10                         # px per line
const MESSAGE_FRAMES := 72.0            # how long the feedback line stays (3 s)

var open := false

var _main: Node
var _message := ""
var _message_at := -1e9


func setup(main: Node) -> void:
	_main = main


## the menu's lines: [key shown, label, action]. Keys 1..9 then 0 run them in this order.
func commands() -> Array:
	return [
		["1", "CONTACT NEXT STATION", _contact_next],
		["2", "CONTACT ALL STATIONS", _contact_all],
		["3", "REVEAL THE WHOLE MAP", func(): GameState.reveal(0, 0, 400); say("WHOLE MAP REVEALED")],
		["4", "RESET THE MAP", func(): GameState.reset_map(); say("MAP RESET")],
		["5", "GIVE ALL ITEMS", _give_all_items],
		["6", "CLEAR INVENTORY", _clear_inventory],
		["7", "OPEN / CLOSE SHUTTERS", func(): _main.shutters.toggle(); say("SHUTTERS")],
		["8", "OPEN / CLOSE CABINET", func(): _main.cabinet.toggle(); say("CABINET")],
		["9", "NEXT DAY", func(): GameState.day += 1; say("DAY %d" % GameState.day)],
		["0", "CLOSE THIS MENU", func(): open = false],
	]


func toggle() -> void:
	open = ENABLED and not open


func run(i: int) -> void:
	var cmds := commands()
	if i >= 0 and i < cmds.size():
		cmds[i][2].call()


## a feedback line under the list
func say(msg: String) -> void:
	_message = msg
	_message_at = _main.clock


## a key while the menu is open; it takes every key
func key(code: int) -> void:
	var n := _digit(code)
	if n >= 0:
		run((n + 9) % 10)                # 1 -> first line ... 0 -> tenth
	elif code in [KEY_ESCAPE, KEY_F9]:
		open = false


## a click while the menu is open: run the line under it, or close when clicking outside
func click(p: Vector2) -> void:
	var row := _row_at(p)
	if row >= 0:
		run(row)
	elif not _rect().has_point(p):
		open = false


# ---------------------------------------------------------------- drawing
## draws the menu on the overlay; returns true when the cursor is over a line (hand cursor)
func draw(overlay: Control, cur: Vector2) -> bool:
	var cmds := commands()
	var r := _rect()
	overlay.draw_rect(r, overlay.panel_lo)
	Px.frame(overlay, r, Px.WHITE)
	Px.text(overlay, "DEBUG MENU  (F9 / ESC TO CLOSE)", r.position + Vector2(6, 5), Px.WHITE)
	Px.text(overlay, _status(), r.position + Vector2(6, 14), overlay.panel_hi)
	var hot := _row_at(cur)
	for i in cmds.size():
		var y := r.position.y + 26 + i * ROW
		if i == hot:
			overlay.draw_rect(Rect2(r.position.x + 2, y - 1, r.size.x - 4, ROW), overlay.panel_col)
		Px.text(overlay, "%s  %s" % [cmds[i][0], cmds[i][1]], Vector2(r.position.x + 8, y), Px.WHITE if i == hot else Px.GREY)
	if _message != "" and _main.clock - _message_at < MESSAGE_FRAMES:
		Px.text(overlay, "> " + _message, Vector2(r.position.x + 6, r.end.y - 11), Color8(239, 180, 94))
	return hot >= 0


func _status() -> String:
	return "DAY %d   STATIONS %d/%d   ITEMS %d/%d" % [GameState.day, GameState.contacted.size(),
			GameState.stations.size(), InventoryManager.inventory.items.size(), InventoryManager.MAX_ITEMS]


func _rect() -> Rect2:
	return Rect2(124, 34, 232, 40 + commands().size() * ROW)


func _row_at(p: Vector2) -> int:
	var r := _rect()
	var i := int((p.y - r.position.y - 26) / ROW)
	if r.has_point(p) and p.y >= r.position.y + 26 and i < commands().size():
		return i
	return -1


static func _digit(code: int) -> int:
	if code >= KEY_0 and code <= KEY_9:
		return code - KEY_0
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return code - KEY_KP_0
	return -1


# ---------------------------------------------------------------- commands
func _contact_next() -> void:
	for id in GameState.stations:
		if not GameState.is_contacted(id):
			GameState.contact_station(id)
			say("CONTACTED " + GameState.stations[id].callsign)
			return
	say("EVERY STATION IS CONTACTED")


func _contact_all() -> void:
	for id in GameState.stations:
		GameState.contact_station(id)
	say("ALL %d STATIONS CONTACTED" % GameState.stations.size())


func _give_all_items() -> void:
	for f in DirAccess.get_files_at(InventoryManager.ITEM_DIR):
		if f.ends_with(".tres") or f.ends_with(".tres.remap"):       # exported builds list .remap files
			var item: ItemData = InventoryManager.get_item(f.get_basename().trim_suffix(".tres"))
			if item and not InventoryManager.has_item(item):
				InventoryManager.add_item(item)
	say("INVENTORY FULL")


func _clear_inventory() -> void:
	_main.ui.inventory.held = null
	for item in InventoryManager.inventory.items.duplicate():
		InventoryManager.remove_item(item)
	say("INVENTORY EMPTY")
