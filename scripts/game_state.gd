extends Node
## Story progress that outlives any one scene: which day it is and what you've done.
## What you carry lives in the InventoryManager autoload.

signal changed

var day := 1
var flags := {}                            # e.g. "map_seen", "window_opened", "took_jar"


func flag(name: String) -> bool:
	return flags.get(name, false)


func set_flag(name: String, value := true) -> void:
	flags[name] = value
	changed.emit()
