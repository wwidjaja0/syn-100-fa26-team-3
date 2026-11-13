extends Node
## The game's rules for the room: what each object is called and what clicking it does.
## This is the file to edit when adding or changing an interaction.
##
## To make an object interactable (full walkthrough in docs/HOW_TO.md):
##   1. it needs an object group: GROUPS in pipeline/godot/export_glb.py, then re-export the room;
##   2. give it a hover label in LABELS below;
##   3. say what a click does in click(), and what using an item on it does in use_item().
## Story progress goes in GameState (flags, contacted stations); carried items in InventoryManager.

## hover text per object group. Capitals, and only the pixel font's characters
## (A-Z 0-9 . , ' - : ? ! ( ) / + = %). Groups not listed here can't be hovered or clicked.
const LABELS := {
	"shutters": "STORM SHUTTERS", "cabinet": "SUPPLY CABINET", "microfiche": "MICROFICHE MAP", "speaker": "PA SPEAKER",
	"radio": "HAM RADIO (BROKEN)", "jar": "DRIED MUSHROOMS", "papers": "ROLLING PAPERS", "bench": "WORKBENCH",
	"lantern": "LANTERN", "instruments": "WEATHER GAUGES", "power": "POWER STATION", "filter": "WATER FILTER",
	"crates": "SUPPLY CRATES", "sandbags": "SANDBAGS", "flashlight": "FLASHLIGHT",
}

var _main: Node


func setup(main: Node) -> void:
	_main = main


## can the cursor pick this group? (the open window's sky only while the shutters are open)
func hoverable(group: String) -> bool:
	return LABELS.has(group) or (group == "sky" and _main.shutters.is_open)


## the label to show while hovering a group, given the item held on the cursor (or null)
func label_for(group: String, held: ItemData) -> String:
	var name: String = "CLOSE SHUTTERS" if group == "sky" else LABELS.get(group, "")
	if group == "radio" and GameState.flag("radio_fixed"):
		name = "HAM RADIO"
	if held != null and name != "":
		return "USE %s ON %s" % [held.name, name]
	return name


## a click on a room object with nothing in hand
func click(group: String) -> void:
	var clock: float = _main.clock
	match group:
		"shutters", "sky":
			_main.shutters.toggle()
			if _main.shutters.is_open and not _main.suppress_auto_dialogue:
				_main.ui.dialogue.start("inspect_shutters_open")
		"microfiche":
			_main.ui.open_panel("fiche", clock)
			GameState.set_flag("fiche_seen")
		"radio":
			_main.radio_view.enter(clock)
		"cabinet":
			_main.cabinet.toggle()
		"jar":
			pick_up("jar", "jar")
		"papers":
			pick_up("papers", "papers")
		"bench":
			_main.crafting.enter(clock)
		"speaker", "lantern", "instruments", "power", "filter", "crates", "sandbags", "flashlight":
			_main.ui.dialogue.start("inspect_" + group)


## an item held on the cursor was clicked on a room object. Return true if something happened.
## The item goes back to its slot either way; if the use consumes it, remove it here with
## InventoryManager.remove_item(item). Nothing is wired up yet.
func use_item(item: ItemData, group: String) -> bool:
	return false


## take a prop: hide its group in the room and fly its icon into the inventory bar.
## item_id names res://items/<item_id>.tres. Does nothing while the bar is full.
func pick_up(group: String, item_id: String) -> void:
	var bar = _main.ui.inventory
	if not bar.has_room():
		return
	var from: Vector2 = _main.picker.screen_point(group)
	_main.picker.groups[group].visible = false
	bar.fly(InventoryManager.get_item(item_id), from, _main.clock)
	GameState.set_flag("took_" + item_id)
