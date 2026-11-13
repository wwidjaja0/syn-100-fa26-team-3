extends RefCounted
## Stand-in props built in code, for things the room needs before they're modelled in the pipeline.
## Each one is a plain box under its own grp_<name> node, registered as an extra object group so it
## hovers, outlines and picks up like the props from assets/shelter.glb.
##
## main.gd calls add_all() before the picker and the materials are set up. To replace a placeholder
## with a real prop, model it (docs/HOW_TO.md, "Add a prop to the room"), add its group to GROUPS in
## pipeline/godot/export_glb.py, and delete its entry here.
##
## The mask has room for 17 groups (see "Object groups and the mask" in docs/ARCHITECTURE.md); the
## room uses 16, so there is space for exactly one placeholder.

## group name -> [box size (m), colour (sRGB), where its bottom centre stands (world, Godot metres)]
const PROPS := {
	# on the workbench top (the cutting mat's height, scene_meta.json craft.mat_center), at its free left end
	"battery": [Vector3(0.20, 0.14, 0.13), Color(0.80, 0.66, 0.32), Vector3(1.85, 0.975, -1.20)],
}


static func add_all(room: Node3D, meta: Dictionary) -> void:
	for name: String in PROPS:
		if name in meta.groups:
			continue
		var p: Array = PROPS[name]
		var size: Vector3 = p[0]
		var grp := Node3D.new()
		grp.name = "grp_" + name
		room.add_child(grp)
		var box := BoxMesh.new()
		box.size = size
		var mat := StandardMaterial3D.new()
		mat.resource_name = "placeholder_" + name
		mat.albedo_color = p[1]
		box.material = mat
		var mi := MeshInstance3D.new()
		mi.name = name + "_placeholder"
		mi.mesh = box
		grp.add_child(mi)
		mi.global_position = p[2] + Vector3(0, size.y / 2.0, 0)
		meta.groups.append(name)

