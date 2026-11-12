extends Node
## The game's rules for the room: what each object is called and what clicking it does.
## This is the file to edit when adding or changing an interaction.
##
## To make an object interactable (full walkthrough in docs/HOW_TO.md):
##   1. it needs an object group: GROUPS in pipeline/godot/export_glb.py, then re-export the room;
##   2. give it a hover label in LABELS below;
##   3. say what a click does in click(), and what using an item on it does in use_item().
## Story progress goes in GameState (flags, contacted stations); carried items in InventoryManager.
##
## The ham radio: clicking it while broken picks it up (item radio_broken) for crafting
## (crafting/crafting.gd). Its place in the room stays as a "ghost": not drawn, but still in the
## mask while the crafted radio is held, so the white outline shows where it goes back. Using the
## radio item on that outline puts it back fixed (flag "radio_fixed"); after that a click opens the
## radio close-up.

## mask-only render layer (20): MaskCam sees it, the world camera doesn't (see toon.gdshader)
const MASK_LAYER := 1 << 19

## hover text per object group. Capitals, and only the pixel font's characters
## (A-Z 0-9 . , ' - : ? ! ( ) / + = %). Groups not listed here can't be hovered or clicked.
const LABELS := {
	"shutters": "STORM SHUTTERS", "cabinet": "SUPPLY CABINET", "microfiche": "MICROFICHE MAP", "speaker": "PA SPEAKER",
	"radio": "HAM RADIO (BROKEN)", "jar": "DRIED MUSHROOMS", "papers": "ROLLING PAPERS", "bench": "WORKBENCH",
	"lantern": "LANTERN", "instruments": "WEATHER GAUGES", "power": "POWER STATION", "filter": "WATER FILTER",
	"crates": "SUPPLY CRATES", "sandbags": "SANDBAGS", "flashlight": "FLASHLIGHT", "battery": "BATTERY",
}

var _main: Node
var _radio_layers := -1                 # the ghost radio's current render layers (-1 = untouched)


func setup(main: Node) -> void:
	_main = main


## per frame, from main.gd: the taken radio's ghost is in the mask only while the fixed radio is held
func update() -> void:
	var layers := 1
	if radio_taken():
		layers = MASK_LAYER if holding_fixed_radio() else 0
	if layers != _radio_layers:
		_radio_layers = layers
		for vi: VisualInstance3D in _main.picker.groups["radio"].find_children("*", "VisualInstance3D", true, false):
			vi.layers = layers


## the radio was taken off the bench and hasn't been put back yet
func radio_taken() -> bool:
	return GameState.flag("took_radio_broken") and not GameState.flag("radio_fixed")


func holding_fixed_radio() -> bool:
	var held: ItemData = _main.ui.inventory.held
	return held != null and held.id == "radio"


## a group to outline even when the cursor isn't on it (post_process.gd): the empty radio spot
## while the fixed radio is held
func hint() -> String:
	var in_room: bool = _main.active_view() == null and _main.ui.panel == ""
	return "radio" if in_room and radio_taken() and holding_fixed_radio() else ""


## can the cursor pick this group? (the open window's sky only while the shutters are open; the
## radio's empty spot only while holding the fixed radio)
func hoverable(group: String) -> bool:
	if group == "radio" and radio_taken():
		return holding_fixed_radio()
	return LABELS.has(group) or (group == "sky" and _main.shutters.is_open)


## the label to show while hovering a group, given the item held on the cursor (or null)
func label_for(group: String, held: ItemData) -> String:
	if group == "radio" and held != null and held.id == "radio" and not GameState.flag("radio_fixed"):
		return "PUT BACK " + held.name
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
		"microfiche":
			_main.ui.open_panel("fiche", clock)
			GameState.set_flag("fiche_seen")
		"radio":
			if GameState.flag("radio_fixed"):
				_main.radio_view.enter(clock)
			else:
				pick_up("radio", "radio_broken", false)
		"cabinet":
			_main.cabinet.toggle()
		"jar":
			pick_up("jar", "jar")
		"papers":
			pick_up("papers", "papers")
		"speaker":
			pick_up("speaker", "speaker")
		"battery":
			pick_up("battery", "battery")
		"bench":
			_main.crafting.enter(clock)


## an item held on the cursor was clicked on a room object. Return true if something happened.
## The item goes back to its slot either way; if the use consumes it, remove it here with
## InventoryManager.remove_item(item).
func use_item(item: ItemData, group: String) -> bool:
	if item.id == "radio" and group == "radio" and not GameState.flag("radio_fixed"):
		put_back_radio(item)
		return true
	return false


## the crafted radio goes back on the bench, fixed: drawn again, with the speaker grill it was
## missing (scene_meta.json's start_hidden parts belong to it)
func put_back_radio(item: ItemData) -> void:
	InventoryManager.remove_item(item)
	GameState.set_flag("radio_fixed")
	update()
	var radio: Node3D = _main.picker.groups["radio"]
	for n in _main.meta.start_hidden:
		var node := radio.find_child(n, true, false)
		if node:
			node.visible = true
	UiSounds.play("start")


## take a prop: hide its group in the room and fly its icon into the inventory bar.
## item_id names res://items/<item_id>.tres. Does nothing while the bar is full. With hide = false
## the group stays in the scene for the caller to deal with (the radio leaves a ghost, see update()).
func pick_up(group: String, item_id: String, hide := true) -> void:
	var bar = _main.ui.inventory
	if not bar.has_room():
		return
	var from: Vector2 = _main.picker.screen_point(group)
	if hide:
		_main.picker.groups[group].visible = false
	bar.fly(InventoryManager.get_item(item_id), from, _main.clock)
	GameState.set_flag("took_" + item_id)
