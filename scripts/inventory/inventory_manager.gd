extends Node
## What the player is carrying. Autoload singleton, reachable anywhere as `InventoryManager`.
##
## Items are ItemData resources, one file per item in res://items/ (for example items/jar.tres).
## The pixel inventory bar (scripts/ui/inventory_bar.gd) draws this list; it never stores items itself.
##
## Typical use:
##     var jar: ItemData = InventoryManager.get_item("jar")
##     if InventoryManager.add_item(jar): ...      # false when all MAX_ITEMS slots are full
##     if InventoryManager.has_item(jar): ...
##     InventoryManager.remove_item(jar)           # e.g. when an item is used up
##     InventoryManager.clear()                    # a new game

## emitted after every add or remove
signal inventory_updated

const MAX_ITEMS := 5                    # the bar shows exactly this many slots
const ITEM_DIR := "res://items/"

var inventory: InventoryData = InventoryData.new()


## the ItemData for an id: get_item("jar") loads res://items/jar.tres
func get_item(id: String) -> ItemData:
	return load(ITEM_DIR + id + ".tres") as ItemData


## add an item; false (and nothing changes) when the bar is already full
func add_item(item: ItemData) -> bool:
	if inventory.items.size() < MAX_ITEMS:
		inventory.items.append(item)
		inventory_updated.emit()
		return true
	return false


func remove_item(item: ItemData) -> void:
	if item in inventory.items:
		inventory.items.erase(item)
		inventory_updated.emit()


## drop everything (a new game)
func clear() -> void:
	inventory.items.clear()
	inventory_updated.emit()


func has_item(item: ItemData) -> bool:
	return item in inventory.items
