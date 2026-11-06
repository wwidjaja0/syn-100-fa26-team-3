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

## ids are stored as (id + MASK_ID_OFFSET) * ID_STEP in the mask's red channel; keep in step with
## shaders/toon.gdshader and shaders/post.gdshader
const MASK_ID_OFFSET := 4
const ID_STEP := 12.0

var group_names: Array[String] = []     # index + 1 = the group's mask id
var group_ids := {}                     # group name -> mask id (1-based)
var groups := {}                        # group name -> its Node3D (grp_<name>) in the room
var hover := ""
var hover_t := 0.0

var _main: Node
var _room: Node3D
var _mask_vp: SubViewport
var _camera: Camera3D


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


## the hoverable group under a screen pixel, or "". Looks at the pixel and its 8 neighbours so thin
## objects are easy to hit.
func group_at(p: Vector2) -> String:
	var img := _mask_vp.get_texture().get_image()
	if img == null:                      # first frame, or a headless run with no renderer
		return ""
	var ip := Vector2i(p)
	var last := Vector2i(img.get_width() - 1, img.get_height() - 1)
	for o in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var q: Vector2i = (ip + o).clamp(Vector2i.ZERO, last)
		var id := roundi(img.get_pixelv(q).r * 255.0 / ID_STEP) - MASK_ID_OFFSET
		if id >= 1 and id <= group_names.size():
			var name := group_names[id - 1]
			if _main.interactions.hoverable(name):
				return name
	return ""


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
