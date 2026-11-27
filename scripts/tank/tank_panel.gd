extends Node
## The reef tank's panel in its close-up (views/tank_view.gd): live water readings and a row of
## item slots. main.gd creates it as `main.tank_panel`; overlay.gd draws it and hands it clicks.
##
## Readings: each has a value (drifting a little, as a live sensor would), the range its bar shows
## and the safe band within it. They're plain data in `readings`, so whatever later fixes the tank
## can change `value` and the panel follows.
##
## Slots: SLOTS squares that take any item (drag it in, or hold it and click a slot); clicking a
## filled slot with nothing held sends the item back to the inventory. What the items do to the
## tank isn't decided yet: listen to `changed` and read `contents`.

## emitted when a slot is filled or emptied
signal changed

const SLOTS := 3
const SLOT := 28                        # slot side, px (the 12x12 icon is drawn 2x inside)
const SLOT_GAP := 8
const PANEL := Rect2(304, 10, 168, 250) # the panel, right of the tank on the 480x270 screen
const ROW := 36                         # px per reading row

## name, value, unit (printf format), bar range, safe band, how far the live value wanders
var readings := [
	{"name": "WATER TEMP", "value": 31.4, "format": "%.1f C", "min": 20.0, "max": 34.0, "safe": [24.0, 29.0], "drift": 0.12},
	{"name": "PH", "value": 7.74, "format": "%.2f", "min": 7.4, "max": 8.4, "safe": [8.0, 8.3], "drift": 0.01},
	{"name": "OXYGEN", "value": 3.6, "format": "%.1f MG/L", "min": 0.0, "max": 9.0, "safe": [5.0, 9.0], "drift": 0.08},
	# a saltwater reef: natural seawater is about 35 parts per thousand. Evaporation leaves the salt
	# behind, so it climbs as the level drops (tank/tank_water.gd)
	{"name": "SALINITY", "value": 35.1, "format": "%.1f PPT", "min": 30.0, "max": 42.0, "safe": [33.0, 36.0], "drift": 0.02},
	{"name": "WATER LEVEL", "value": 97.0, "format": "%d%%", "min": 70.0, "max": 100.0, "safe": [92.0, 100.0], "drift": 0.0},
]
var contents: Array = []                # one ItemData (or null) per slot

var _main: Node


func setup(main: Node) -> void:
	_main = main
	contents.resize(SLOTS)


## the panel is up: the tank close-up has settled
func showing() -> bool:
	return _main.tank_view.settled()


## a reading's live value: its value plus a slow sensor wobble
func live_value(i: int) -> float:
	var r: Dictionary = readings[i]
	var t: float = _main.clock
	return r.value + r.drift * (0.7 * sin(t * 0.05 + i * 2.1) + 0.3 * sin(t * 0.23 + i))


func in_safe_band(i: int) -> bool:
	var v := live_value(i)
	return v >= readings[i].safe[0] and v <= readings[i].safe[1]


## where a reading's row starts (its name), and its bar under it
func row_pos(i: int) -> Vector2:
	return PANEL.position + Vector2(8, 22 + i * ROW)


func bar_rect(i: int) -> Rect2:
	return Rect2(row_pos(i) + Vector2(0, 12), Vector2(PANEL.size.x - 16, 6))


## a slot's square on screen
func slot_rect(i: int) -> Rect2:
	var w := SLOTS * SLOT + (SLOTS - 1) * SLOT_GAP
	var x := PANEL.position.x + (PANEL.size.x - w) / 2.0 + i * (SLOT + SLOT_GAP)
	return Rect2(x, PANEL.end.y - SLOT - 10, SLOT, SLOT)


## the slot under a screen pixel, or -1
func slot_at(p: Vector2) -> int:
	if not showing():
		return -1
	for i in SLOTS:
		if slot_rect(i).has_point(p):
			return i
	return -1


## is the cursor on the panel (so the view behind it shouldn't react)?
func over(p: Vector2) -> bool:
	return showing() and PANEL.has_point(p)


## a click (or a drag let go) on the panel. held is the item on the cursor, or null. True if p was
## on the panel, so the click goes no further.
func click(p: Vector2, held: ItemData) -> bool:
	if not over(p):
		return false
	var i := slot_at(p)
	if i < 0:
		return true
	var bar = _main.ui.inventory
	if held != null:
		if contents[i] != null:          # taken: keep holding it
			UiSounds.play("back")
			return true
		bar.held = null
		InventoryManager.remove_item(held)
		contents[i] = held
		UiSounds.play("pick")
		changed.emit()
	elif contents[i] != null:
		if bar.has_room():
			bar.fly(contents[i], slot_rect(i).get_center(), _main.clock)
			contents[i] = null
			UiSounds.play("pick")
			changed.emit()
		else:
			UiSounds.play("back")
	return true


## the hover label for a slot
func label(i: int, held: ItemData) -> String:
	if held != null:
		return "PUT IN " + held.name if contents[i] == null else "SLOT TAKEN"
	if contents[i] != null:
		return "TAKE OUT " + contents[i].name
	return "EMPTY SLOT"
