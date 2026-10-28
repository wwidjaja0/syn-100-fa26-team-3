extends Node
## Story progress that outlives any one scene: which day it is, what you carry, what you've done.

signal changed

var day := 1
var inventory: Array[String] = []          # item ids: jar, papers, cig, speaker
var flags := {}                            # e.g. "map_seen", "window_opened"


func flag(name: String) -> bool:
	return flags.get(name, false)


func set_flag(name: String, value := true) -> void:
	flags[name] = value
	changed.emit()


func add_item(item: String) -> void:
	inventory.append(item)
	changed.emit()


func remove_item(item: String) -> void:
	inventory.erase(item)
	changed.emit()


func has_item(item: String) -> bool:
	return item in inventory
