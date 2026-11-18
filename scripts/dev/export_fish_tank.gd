extends SceneTree
## Rebuild scenes/fish_tank.tscn from the builders in room/fish_tank.gd.
##
##     godot --path . --script res://scripts/dev/export_fish_tank.gd
##
## The game instances that scene; it does not build the meshes itself. Run this again after
## changing the tank's parts.


func _init() -> void:
	var tank = preload("res://scripts/room/fish_tank.gd").new()
	var model: Node3D = tank.build_model()
	root.add_child(model)
	_own(model, model)
	var packed := PackedScene.new()
	var err := packed.pack(model)
	if err != OK:
		push_error("FishTank: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, "res://scenes/fish_tank.tscn")
	if err != OK:
		push_error("FishTank: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("wrote scenes/fish_tank.tscn")
	quit()


func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)
