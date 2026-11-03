extends Node
## The player's inventory (autoload). Items are ItemData resources in res://items/<id>.tres;
## scripts/ui.gd draws them in the pixel inventory bar.

signal inventory_updated

const MAX_ITEMS := 5
const ITEM_DIR := "res://items/"

var inventory: InventoryData = InventoryData.new()


## the ItemData for an id, e.g. get_item("jar") -> res://items/jar.tres
func get_item(id: String) -> ItemData:
	return load(ITEM_DIR + id + ".tres") as ItemData


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

func has_item(item: ItemData) -> bool:
	return item in inventory.items
