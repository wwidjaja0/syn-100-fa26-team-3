extends Node

signal inventory_updated

var inventory: InventoryData = InventoryData.new()

func add_item(item: ItemData) -> bool:
	if inventory.items.size() < 5:
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
