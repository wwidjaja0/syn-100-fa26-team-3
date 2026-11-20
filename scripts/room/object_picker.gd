extends Node
## Works out which object is under the cursor.
##
## The room is grouped into named objects ("bench", "radio", "shutters", ... see
## assets/scene_meta.json's "groups", made by pipeline/godot/export_glb.py). A second camera
## (MaskVP/MaskCam) renders the room again with every surface painted a flat colour that encodes
## its group's id (toon.gdshader's mask pass). Reading that image under the cursor says what is
## there; the post shader uses the same image to draw the hover outline.
##
## Only objects interactions.gd knows about are hoverable. The result is `hover` (a group name, or
## "") and `hover_t` (how long it has been hovered, in 24 fps frames).
##
## The click target is the object's own meshes, not a box around them. The window's sill, lintel,
## jambs, mullion and transom start outside the shutter group; prepare_targets() parents them onto
## the shutters so those frame pieces click with the panels.

## ids are stored as (id + MASK_ID_OFFSET) * ID_STEP in the mask's red channel; keep in step with
## shaders/toon.gdshader and shaders/post.gdshader
const MASK_ID_OFFSET := 4
const ID_STEP := 10.0              # (id + 4) * 10 <= 255: room for 21 groups
const LEADS := ["coax", "cord", "cable", "wire"]   # thin parts screen_top() leaves out
const WINDOW_FRAME := ["window_sill", "window_lintel", "window_jamb_l", "window_jamb_r", "window_mullion", "window_transom"]

var group_names: Array[String] = []     # index + 1 = the group's mask id
var group_ids := {}                     # group name -> mask id (1-based)
var groups := {}                        # group name -> its Node3D (grp_<name>) in the room
var hover := ""
var hover_t := 0.0
var refresh_mask := true               # false on web frames that reuse the last mask image

var _main: Node
var _room: Node3D
var _mask_vp: SubViewport
var _camera: Camera3D
var _cached_mask: Image


func setup(main: Node, meta: Dictionary, room: Node3D, mask_vp: SubViewport, camera: Camera3D) -> void:
	_main = main
	_room = room
	_mask_vp = mask_vp
	_camera = camera
	for i in meta.groups.size():
		group_names.append(meta.groups[i])
		group_ids[meta.groups[i]] = i + 1
	for name in group_names:
		groups[name] = room.find_child("grp_" + name, true, false)


## the window frame pieces join the shutters, before room_materials numbers groups, so a click on
## the sill, lintel, jamb, mullion or transom is a click on the shutters.
func prepare_targets(room: Node3D) -> void:
	var shutters: Node3D = groups.get("shutters")
	if shutters == null:
		return
	for n in WINDOW_FRAME:
		var node := room.find_child(n, true, false)
		if node and node.get_parent() != shutters:
			node.reparent(shutters, true)


## the mask id of the group a node belongs to (0 = none); room_materials.gd uses this
func group_of(n: Node) -> int:
	while n and n != _room:
		if n.name.begins_with("grp_"):
			return group_ids.get(n.name.substr(4), 0)
		n = n.get_parent()
	return 0


## per frame; enabled is false while a panel, a close-up or a UI element has the cursor
func update(cursor: Vector2, step: float, enabled: bool) -> void:
	var target := group_at(cursor) if enabled else ""
	hover_t = hover_t + step if (target != "" and target == hover) else (1.0 if target != "" else 0.0)
	hover = target


## the hoverable group under a screen pixel, or "". Looks at the pixel and its 8 neighbours so a
## thin piece of the object is easy to hit, without reaching into the empty space around it.
func group_at(p: Vector2) -> String:
	var img := _mask_image()
	if img == null:                      # first frame, or a headless run with no renderer
		return ""
	var ip := Vector2i(p)
	for o in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var name := _hoverable_at(img, ip + o)
		if name != "":
			return name
	return ""


func _mask_image() -> Image:
	if refresh_mask or _cached_mask == null:
		var img := _mask_vp.get_texture().get_image()
		if img != null:
			_cached_mask = img
		refresh_mask = false
	return _cached_mask


func _hoverable_at(img: Image, p: Vector2i) -> String:
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		return ""
	var id := roundi(img.get_pixelv(p).r * 255.0 / ID_STEP) - MASK_ID_OFFSET
	if id < 1 or id > group_names.size():
		return ""
	var name := group_names[id - 1]
	return name if _main.interactions.hoverable(name) else ""


## the mask id of a group, 0 for none (the post shader outlines this id)
func id_of(name: String) -> int:
	return group_ids.get(name, 0)


## where a group's visible meshes are centred on screen (where picked-up items fly from)
func screen_point(name: String) -> Vector2:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in groups[name].find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return _camera.unproject_position(box.get_center())


## the screen point just above a group's top: the middle of the back edge of its highest face, the
## highest part of it the room camera sees. Leads hanging off an object (the radio's coax up the
## wall, the hand mic's cord) are left out, so a marker sits on the object itself.
func screen_top(name: String) -> Vector2:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in groups[name].find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or LEADS.any(func(w): return w in String(mi.name)):
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var c := box.get_center()
	return _camera.unproject_position(Vector3(c.x, box.end.y, box.position.z))

