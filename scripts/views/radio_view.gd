extends "res://scripts/views/close_view.gd"
## The radio view. Clicking the ham radio brings the camera to the front of the rig. The
## communication itself is left open: listen to clicked / entered / exited, use
## screen_point() to put UI over a part of the radio, and call GameState.contact_station(id)
## when a conversation reaches someone (that marks them on the microfiche).

## a click while the view is settled; held is the item on the cursor, or null
signal clicked(cursor: Vector2, held: ItemData)

const WIDTH := 0.85                     # m across the screen: the rig, its mic and a little bench
const TILT := deg_to_rad(6.0)           # looking slightly down onto the front panel
const DIST := 1.2                       # m in front of the panel (only matters for clipping)
const LIFT := Vector3(0.02, 0.035, 0)   # centre on the whole stack; the bench edge stays above the inventory bar

var camera: Camera3D


## frame the rig from scene_meta.json's points.radio_front (pipeline/godot/export_glb.py)
func setup(meta: Dictionary, cam: Camera3D) -> void:
	camera = cam
	var f: Array = meta.points.radio_front
	_focus = Vector3(f[0], f[1], f[2]) + LIFT
	var b := Basis.from_euler(Vector3(-TILT, 0, 0))
	_pose = Transform3D(b, _focus + b.z * DIST)
	_size = WIDTH


func click(cursor: Vector2, held: ItemData) -> void:
	if settled():
		clicked.emit(cursor, held)


## where a world point is on screen in this view (valid once settled)
func screen_point(world: Vector3) -> Vector2:
	return camera.unproject_position(world)
