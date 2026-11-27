extends Node
## The crafting rules, one plus one: put two things down on the workbench and, if they go together,
## they make one new thing (x + y = xy), which can go together with a third (xy + z = xyz).
## main.gd creates it as `main.workbench` (main.crafting is the camera view, views/crafting_view.gd).
##
## In the crafting view the cutting mat is only the backdrop. Over it sit two slots with a + between
## them (SLOTS), and the result slot to the right (overlay.gd's RESULT). Hold an item and click a slot
## (or drag it there) to put it down: it leaves the inventory. Click a filled slot with nothing held to
## take it back. When the two slots hold a recipe, result() names what they make, overlay.gd shows it
## big in the result slot, and clicking that slot calls craft(): the two are used up and the result
## flies into the inventory.
##
## Some results take time before they can be used: craft() asks ready_frames() how long, and marks the
## item (ItemData meta "ready_at", a clock frame) so the inventory bar shows a progress bar on it and
## won't let it be picked up until then. Reef salt that has caked in the damp (room/salt_bag.gd) takes
## longer to dissolve into SALTWATER; loose salt is ready at once.
##
## To add a recipe, add a line to RECIPES (the result and both ingredients are item ids, i.e.
## res://items/<id>.tres; see "Add a crafting recipe" in docs/HOW_TO.md).

## emitted whenever the slots change (an item put down or taken back, or something crafted)
signal changed
## something was made; the result item is flying into the inventory
signal crafted(result: ItemData)

## result item id -> its two ingredients' item ids (either order)
const RECIPES := {
	"saltwater": ["pure_water", "salt"],    # reef salt mix dissolved in purified water: new seawater
}
const SLOTS := [Rect2(146, 112, 46, 46), Rect2(232, 112, 46, 46)]   # the two ingredient slots, on the mat
const DISSOLVE_SECONDS := 90.0          # fully caked salt takes this long to dissolve into saltwater
const CAKED_AT := 0.25                  # salt caked less than this dissolves at once

var slots: Array = [null, null]         # the ItemData in each slot, or null

var _main: Node


func setup(main: Node) -> void:
	_main = main
	main.crafting.clicked.connect(_on_clicked)


## the slot under a screen pixel, or -1
func slot_at(p: Vector2) -> int:
	if not _main.crafting.settled():
		return -1
	for i in SLOTS.size():
		if SLOTS[i].has_point(p):
			return i
	return -1


## the id of what the two slots make, or ""
func result() -> String:
	if slots[0] == null or slots[1] == null:
		return ""
	for out: String in RECIPES:
		var need: Array = RECIPES[out]
		if (need[0] == slots[0].id and need[1] == slots[1].id) or (need[1] == slots[0].id and need[0] == slots[1].id):
			return out
	return ""


## the hover label over a slot
func slot_label(i: int, held: ItemData) -> String:
	if held != null:
		return "PUT DOWN " + held.name if slots[i] == null else "SLOT TAKEN"
	return "TAKE BACK " + slots[i].name if slots[i] != null else "EMPTY SLOT"


## how many clock frames the result needs before it can be used (0: ready now)
func ready_frames(out: String) -> float:
	if out != "saltwater":
		return 0.0
	for it in slots:
		if it != null and it.id == "salt":
			var cake: float = it.get_meta("cake", 0.0)
			return 0.0 if cake < CAKED_AT else cake * DISSOLVE_SECONDS * _main.TICK
	return 0.0


## make the result: both ingredients are used up and the result flies from `from` (a screen point)
## into the inventory. False when nothing matches or the inventory has no room.
func craft(from: Vector2) -> bool:
	var out := result()
	var bar = _main.ui.inventory
	if out == "" or not bar.has_room():
		UiSounds.play("back")
		return false
	var item: ItemData = InventoryManager.get_item(out).duplicate()   # its own copy: it may carry a timer
	var wait := ready_frames(out)
	if wait > 0.0:
		item.set_meta("ready_at", _main.clock + wait)
		item.set_meta("wait", wait)
	slots = [null, null]
	bar.fly(item, from, _main.clock)
	UiSounds.play("start")
	GameState.set_flag("crafted_" + out)
	changed.emit()
	crafted.emit(item)
	return true


func _on_clicked(p: Vector2, held: ItemData) -> void:
	var i := slot_at(p)
	if i < 0:
		return
	var bar = _main.ui.inventory
	if held != null:
		if slots[i] != null:             # taken: keep holding it
			UiSounds.play("back")
			return
		bar.held = null
		InventoryManager.remove_item(held)
		slots[i] = held
		UiSounds.play("pick")
		changed.emit()
	elif slots[i] != null:
		if not bar.has_room():
			UiSounds.play("back")
			return
		bar.fly(slots[i], SLOTS[i].get_center(), _main.clock)
		slots[i] = null
		UiSounds.play("pick")
		changed.emit()
