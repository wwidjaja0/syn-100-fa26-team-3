extends Resource
class_name InventoryData
## The list of items the player carries, in pick-up order. InventoryManager owns the only instance;
## change it through InventoryManager's functions so the inventory_updated signal fires.

@export var items: Array[ItemData] = []
