extends Node
## Fixing the ham radio in its close-up (views/radio_view.gd). main.gd creates it as
## `main.radio_repair`.
##
## While the radio is broken, the close-up shows one square slot per missing part (SLOTS), each over
## the part of the rig it belongs to. Drop the matching item in (drag it from the inventory, or hold
## it and click the slot) and it leaves the inventory. Click a filled slot with nothing held to take
## the part back. When every slot is filled the radio is fixed: flag "radio_fixed", which main.gd
## turns into the repaired meshes and the "radio_repaired" monologue. overlay.gd draws the slots.

## emitted when a slot is filled or emptied
signal changed

## slot id -> [the item that fits, the radio mesh the slot sits over, its label]
const SLOTS := {
	"speaker": ["speaker", "radio_speaker_hole", "SPEAKER"],
	"battery": ["battery", "psu_front_panel", "BATTERY"],
}
const SIZE := 28                        # slot side, px (the 12x12 icon is drawn 2x inside)

var filled := {}                        # slot id -> ItemData in it

var _main: Node
var _parts := {}                        # slot id -> MeshInstance3D the slot sits over


func setup(main: Node) -> void:
	_main = main
	var radio: Node3D = main.picker.groups["radio"]
	for id: String in SLOTS:
		var found := radio.find_children(SLOTS[id][1] + "*", "MeshInstance3D", true, false)
		_parts[id] = found[0] if not found.is_empty() else null
		if _parts[id] == null:
			push_error("radio slot '%s': no mesh '%s' in the radio" % [id, SLOTS[id][1]])


## the slots are showing: the close-up has settled on a radio that still needs parts
func showing() -> bool:
	return _main.radio_view.settled() and not GameState.flag("radio_fixed")


## a slot's square on screen (valid while showing()), centred on its part of the rig
func slot_rect(id: String) -> Rect2:
	var part: MeshInstance3D = _parts[id]
	var at: Vector2 = _main.radio_view.screen_point(part.global_transform * part.get_aabb().get_center())
	return Rect2((at - Vector2(SIZE, SIZE) / 2.0).floor(), Vector2(SIZE, SIZE))


## the slot under a screen pixel, or ""
func slot_at(p: Vector2) -> String:
	if not showing():
		return ""
	for id: String in SLOTS:
		if slot_rect(id).has_point(p):
			return id
	return ""


## a click (or a drag let go) on the slots. held is the item on the cursor, or null. True if a slot
## was under p, so the click goes no further.
func click(p: Vector2, held: ItemData) -> bool:
	var id := slot_at(p)
	if id == "":
		return false
	var bar = _main.ui.inventory
	if held != null:
		if filled.has(id) or held.id != SLOTS[id][0]:
			bar.held = null             # doesn't fit: back to its slot
			UiSounds.play("back")
			return true
		bar.held = null
		InventoryManager.remove_item(held)
		filled[id] = held
		UiSounds.play("pick")
		changed.emit()
		if filled.size() == SLOTS.size():
			GameState.set_flag("radio_fixed")
	elif filled.has(id):
		if bar.has_room():
			bar.fly(filled[id], slot_rect(id).get_center(), _main.clock)
			filled.erase(id)
			UiSounds.play("pick")
			changed.emit()
		else:
			UiSounds.play("back")
	return true


## the hover label for a slot
func label(id: String, held: ItemData) -> String:
	if held != null:
		return ("PUT IN " + held.name) if held.id == SLOTS[id][0] and not filled.has(id) else ("NEEDS " + SLOTS[id][2])
	if filled.has(id):
		return "TAKE OUT " + filled[id].name
	return SLOTS[id][2] + " SLOT"
