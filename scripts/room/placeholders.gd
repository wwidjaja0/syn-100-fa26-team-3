extends RefCounted
## Stand-in props built in code, for things the room needs before they're modelled in the pipeline.
## Each one is its own grp_<name> node, registered as an extra object group so it hovers, outlines
## and picks up like the props from assets/shelter.glb.
##
## main.gd calls add_all() before the picker and the materials are set up. To replace a placeholder
## with a real prop, model it (docs/HOW_TO.md, "Add a prop to the room"), add its group to GROUPS in
## pipeline/godot/export_glb.py, and delete its builder here.
##
## The mask has room for 21 groups (see "Object groups and the mask" in docs/ARCHITECTURE.md); the
## room uses 16, the battery and the reef tank (room/fish_tank.gd) 3 more.
##
## The battery is a yellow pack with a black lightning bolt, clicked into the front of the power
## station (grp_power) so it reads as a spare you can take. The cable is part of the same group
## and leaves with it.

const BODY := Vector3(0.22, 0.16, 0.09)
const YELLOW := Color(0.95, 0.78, 0.16)
const BOLT := Color(0.10, 0.09, 0.08)
const METAL := Color(0.74, 0.72, 0.64)
const CABLE := Color(0.08, 0.08, 0.09)


static func add_all(room: Node3D, meta: Dictionary) -> void:
	if "battery" in meta.groups:
		return
	var grp := Node3D.new()
	grp.name = "grp_battery"
	room.add_child(grp)
	grp.global_position = _anchor(room)
	_build(grp)
	meta.groups.append("battery")


## the back of the pack, on the camera-facing side of the power station, left of its screen
static func _anchor(room: Node3D) -> Vector3:
	var power := room.find_child("grp_power", true, false) as Node3D
	var box := AABB()
	var first := true
	if power:
		for mi in power.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	if first:
		return Vector3(1.85, 1.05, -1.05)
	# left of the station's screen, about halfway up its face, stuck on the front
	return Vector3(box.get_center().x - 0.20, box.position.y + box.size.y * 0.48, box.position.z + box.size.z)


static func _build(grp: Node3D) -> void:
	var depth := BODY.z
	_part(grp, "battery_body", BODY, YELLOW, Vector3(0, 0, depth * 0.5))
	# a dark cap along the top, the way a pack's lid reads
	_part(grp, "battery_cap", Vector3(BODY.x, 0.028, depth + 0.004), BOLT, Vector3(0, BODY.y * 0.5 - 0.01, depth * 0.5))
	for side in [-1, 1]:
		_part(grp, "battery_terminal", Vector3(0.03, 0.022, 0.022), METAL,
				Vector3(side * 0.045, BODY.y * 0.5 + 0.008, depth * 0.45))
	# black bolt on the yellow face: three offset bars, then the point
	var face := depth + 0.006
	_part(grp, "battery_bolt_top", Vector3(0.055, 0.034, 0.012), BOLT, Vector3(0.028, 0.032, face))
	_part(grp, "battery_bolt_mid", Vector3(0.078, 0.03, 0.012), BOLT, Vector3(-0.006, 0.0, face))
	_part(grp, "battery_bolt_low", Vector3(0.05, 0.034, 0.012), BOLT, Vector3(0.02, -0.034, face))
	_part(grp, "battery_bolt_tip", Vector3(0.02, 0.022, 0.012), BOLT, Vector3(0.028, -0.058, face))
	# a lead back into the station, so the pack looks plugged in rather than set down nearby
	_part(grp, "battery_lead", Vector3(0.026, 0.026, 0.07), CABLE, Vector3(0.06, -0.04, -0.02))
	_part(grp, "battery_plug", Vector3(0.042, 0.04, 0.022), METAL, Vector3(0.06, -0.04, -0.055))


static func _part(grp: Node3D, part_name: String, size: Vector3, color: Color, local_pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.resource_name = "placeholder_" + part_name
	mat.albedo_color = color
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	grp.add_child(mi)
	mi.position = local_pos
