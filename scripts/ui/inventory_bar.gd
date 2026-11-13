extends RefCounted
## The inventory bar along the bottom of the screen: one 20x20 slot per InventoryManager.MAX_ITEMS,
## items flying into it when picked up, and the item "held" on the cursor.
##
## The items themselves live in the InventoryManager autoload; this only draws them and handles
## clicks on the slots. Clicking a slot picks its item up (it rides on the cursor, see `held`);
## clicking a slot while holding something puts it back. Items can also be dragged: press on a slot,
## move, and let go over the target; main.gd treats the release as a click there (drag_released()).
## Owned and drawn by overlay.gd.

const Px := preload("res://scripts/ui/pixel_draw.gd")
const SLOT := 20                        # slot size, px
const SLOT_STEP := 22                   # slot pitch, px
const SLOTS: int = preload("res://scripts/inventory/inventory_manager.gd").MAX_ITEMS
const POS := Vector2i((Px.W - SLOT_STEP * SLOTS + SLOT_STEP - SLOT) / 2, 245)   # first slot's top-left; bar centred
const FLY_FRAMES := 16.0                # how long an item takes to fly into its slot
const DRAG_PX := 4.0                    # a press that moves further than this before release is a drag
const NO_DRAG := Vector2(-1, -1)

var held: ItemData = null               # the item riding on the cursor, or null
var _flights: Array = []                # [ItemData, from (screen px), launched at (clock)]
var _drag_from := NO_DRAG               # where the press that picked up `held` was, until release
var _overlay: Control


func _init(overlay: Control) -> void:
	_overlay = overlay


## send an item flying from a point on screen into the next free slot; it is added to the
## inventory when it lands
func fly(item: ItemData, from: Vector2, now: float) -> void:
	_flights.append([item, from, now])


func flying() -> bool:
	return not _flights.is_empty()


## room for one more item, counting the ones still flying in
func has_room() -> bool:
	return InventoryManager.inventory.items.size() + _flights.size() < SLOTS


func slot_rect(i: int) -> Rect2:
	return Rect2(POS.x + SLOT_STEP * i, POS.y, SLOT, SLOT)


## the slot under a screen pixel, or -1
func slot_at(p: Vector2) -> int:
	for i in SLOTS:
		if slot_rect(i).has_point(p):
			return i
	return -1


## what a slot shows: its inventory item, unless that item is riding on the cursor
func slot_item(i: int) -> ItemData:
	var inv: Array[ItemData] = InventoryManager.inventory.items
	if i >= inv.size() or inv[i] == held:
		return null
	return inv[i]


## a click on a slot: pick its item up, or put back whatever is held. False if p is not on a slot.
func click(p: Vector2) -> bool:
	var slot := slot_at(p)
	if slot < 0:
		return false
	var item := slot_item(slot)
	if held != null and item != held:
		held = null
		UiSounds.play("back")
	elif item != null:
		held = item
		_drag_from = p
		UiSounds.play("pick")
	return true


## the left button came up. True when this ends a drag (the press picked an item up and the cursor
## has moved since): main.gd then clicks at p with the item, which drops it there.
func drag_released(p: Vector2) -> bool:
	var dragged := _drag_from != NO_DRAG and held != null and p.distance_to(_drag_from) > DRAG_PX
	_drag_from = NO_DRAG
	return dragged


## draw the slots; returns the name of the item under the cursor ("" if none) for the hover label
func draw_slots(cur: Vector2, interactive: bool) -> String:
	var label := ""
	for i in SLOTS:
		var r := slot_rect(i)
		var item := slot_item(i)
		var hov := interactive and item != null and r.has_point(cur)
		_overlay.draw_rect(r, _overlay.panel_col)
		Px.frame(_overlay, r, Px.WHITE if hov else _overlay.panel_hi)
		if item != null:
			draw_icon(item, r.position + Vector2(4, 4))
		if hov:
			label = item.name
	return label


## items in flight: an arc from where they were picked up into the next free slot. Lands them in
## the InventoryManager when they arrive.
func draw_flights(now: float) -> void:
	var landed := []
	for fl in _flights:
		var k: float = (now - fl[2]) / FLY_FRAMES
		if k >= 1.0:
			landed.append(fl)
			continue
		var slot: int = InventoryManager.inventory.items.size() + _flights.find(fl)
		var to := slot_rect(slot).get_center()
		var t := smoothstep(0.0, 1.0, k)
		var at: Vector2 = fl[1].lerp(to, t) - Vector2(0, 30.0 * sin(PI * t))
		draw_icon(fl[0], at.floor() - Vector2(6, 6))
	for fl in landed:
		_flights.erase(fl)
		InventoryManager.add_item(fl[0])


## an item's 12x12 icon at pos; items without art yet get a "?" box
func draw_icon(item: ItemData, pos: Vector2) -> void:
	if item.icon != null:
		_overlay.draw_texture(item.icon, pos)
	else:
		Px.frame(_overlay, Rect2(pos, Vector2(12, 12)), _overlay.panel_hi)
		Px.text(_overlay, "?", pos + Vector2(3, 2), Px.WHITE, Px.INK)
