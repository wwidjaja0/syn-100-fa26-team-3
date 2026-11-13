extends Node
## The crafting rules: what is lying on the workbench's cutting mat, the recipes, and making things.
## main.gd creates it as `main.workbench` (main.crafting is the camera view, views/crafting_view.gd).
##
## In the crafting view, hold an item and click an empty cell to put it down: it leaves the
## inventory and sits on the mat (`placed`). Click a placed item with nothing held to send it back to
## the inventory. Where things sit on the grid doesn't matter: when the mat holds exactly a
## recipe's ingredients, result() names what they make, overlay.gd shows it big in the result slot
## to the right of the mat, and clicking that slot calls craft().
##
## To add a recipe, add a line to RECIPES (the result and every ingredient are item ids, i.e.
## res://items/<id>.tres; see "Add a crafting recipe" in docs/HOW_TO.md).

## emitted whenever the mat changes (an item put down or taken back, or something crafted)
signal changed
## something was made; the result item is flying into the inventory
signal crafted(result: ItemData)

## result item id -> its ingredients' item ids (any order, any cells)
const RECIPES := {
	"radio": ["radio_broken", "battery", "speaker"],
}

var placed := {}                        # Vector2i cell -> ItemData lying there

var _main: Node


func setup(main: Node) -> void:
	_main = main
	main.crafting.cell_clicked.connect(_on_cell_clicked)


## the item lying in a cell, or null
func item_at(cell: Vector2i) -> ItemData:
	return placed.get(cell)


## the id of what the mat's items make, or "" when they don't make anything
func result() -> String:
	if placed.is_empty():
		return ""
	var have := _sorted_ids(placed.values().map(func(i: ItemData): return i.id))
	for out: String in RECIPES:
		if _sorted_ids(RECIPES[out]) == have:
			return out
	return ""


## make the result: the ingredients are used up and the result flies from `from` (a screen point)
## into the inventory. False when nothing matches or the inventory has no room.
func craft(from: Vector2) -> bool:
	var out := result()
	var bar = _main.ui.inventory
	if out == "" or not bar.has_room():
		UiSounds.play("back")
		return false
	var item := InventoryManager.get_item(out)
	placed.clear()
	bar.fly(item, from, _main.clock)
	UiSounds.play("start")
	GameState.set_flag("crafted_" + out)
	changed.emit()
	crafted.emit(item)
	return true


func _on_cell_clicked(cell: Vector2i, held: ItemData) -> void:
	var bar = _main.ui.inventory
	if held != null:
		if placed.has(cell):             # occupied: keep holding it
			UiSounds.play("back")
			return
		bar.held = null
		InventoryManager.remove_item(held)
		placed[cell] = held
		UiSounds.play("pick")
		changed.emit()
	elif placed.has(cell):
		if not bar.has_room():
			UiSounds.play("back")
			return
		bar.fly(placed[cell], Vector2(_main.crafting.cell_rect(cell).get_center()), _main.clock)
		placed.erase(cell)
		UiSounds.play("pick")
		changed.emit()


static func _sorted_ids(ids: Array) -> Array:
	var s := ids.duplicate()
	s.sort()
	return s
