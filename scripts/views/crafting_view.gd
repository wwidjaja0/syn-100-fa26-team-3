extends "res://scripts/views/close_view.gd"
## The crafting view. Clicking the workbench swings the camera straight down onto the
## cutting mat (the camera move is close_view.gd's). The mat is only the backdrop: crafting is one
## plus one, in two slots drawn over it (crafting/crafting.gd, which gets this view's clicks).
##
## The mat texture is drawn so one texel is one screen pixel in this view
## (pipeline/scene/make_mat.py), and the camera is placed so the mat starts on a whole pixel.

## a click in the settled view; held is the item on the cursor, or null
signal clicked(p: Vector2, held: ItemData)

const CAM_HEIGHT := 2.0                 # m above the mat: above the pendant shade and under the ceiling

var mat_px: Rect2i                      # the whole mat on screen, in the settled view

var _px: float                          # metres per screen pixel over the mat
var _mat_corner: Vector3                # world position of the mat's back-left corner (top of screen)


## size the view from scene_meta.json's "craft" block (written by pipeline/godot/export_glb.py)
func setup(meta: Dictionary, w: int, h: int) -> void:
	var c: Dictionary = meta.craft
	_px = 1.0 / (float(c.px_per_cm) * 100.0)
	_size = w * _px
	var size := Vector2i(int(c.px[0]), int(c.px[1]))
	var center := Vector3(c.mat_center[0], c.mat_center[1], c.mat_center[2])
	_mat_corner = center - Vector3(size.x, 0, size.y) * _px / 2.0
	mat_px = Rect2i(Vector2i((w - size.x) / 2, (h - size.y) / 2), size)
	# screen pixel edges fall at camera centre + whole pixels, so put the mat corner on one
	_focus = _mat_corner + Vector3(w / 2 - mat_px.position.x, 0, h / 2 - mat_px.position.y) * _px
	_pose = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), _focus + Vector3(0, CAM_HEIGHT, 0))


## The original swing (close_view.gd), with the zoom and the pan onto the mat running a little
## ahead of the tilt so the frame is already tight on the bench as it tips down.
## Mid-swing the orthographic frame's top edge pokes up through the sloped ceiling, and the rays
## from there show the roof boards from above. Sliding an orthographic camera along its view ray
## doesn't change the picture, only what sits behind it, so the camera is pushed forward until
## that edge is under the rafters.
func camera_pose(room: Transform3D, room_size: float) -> Array:
	if t <= 0.0:
		return [room, room_size]
	if t >= 1.0:
		return [_pose, _size]
	var e := smoothstep(0.0, 1.0, t)
	var lead := smoothstep(0.0, 0.7, t)
	var f0 := -room.basis.z
	var d0 := (room.origin.z - _focus.z) / maxf(-f0.z, 1e-3)
	var pivot0 := room.origin + f0 * d0
	var d1 := (_pose.origin - _focus).length()
	var b := Basis(room.basis.get_rotation_quaternion().slerp(_pose.basis.get_rotation_quaternion(), e))
	var size := exp(lerpf(log(room_size), log(_size), lead))
	var pivot := pivot0.lerp(_focus, lead)
	var dist := _under_ceiling(pivot, b, size, exp(lerpf(log(d0), log(d1), e)))
	return [Transform3D(b, pivot + b.z * dist), size]


## the ceiling's underside (pipeline/scene/build_pixel_scene.py, in Godot axes): a plane rising
## CEIL_SLOPE toward the front, from the back wall (z = CEIL_BACK) to the front edge (z = CEIL_FRONT),
## lowered to the rafters' undersides plus a little clearance
const CEIL_SLOPE := deg_to_rad(16.0)
const CEIL_BACK := -2.0
const CEIL_FRONT := 1.1
const CEIL_AT_BACK := 3.2 - 0.14 - 0.06


## dist, shortened if the top edge of the frame would start above the ceiling: the camera moves
## up its own view ray to where that edge's ray comes out under the boards
func _under_ceiling(pivot: Vector3, b: Basis, size: float, dist: float) -> float:
	var k := tan(CEIL_SLOPE)
	var top := pivot + b.y * (size * 270.0 / 480.0 / 2.0)
	var climb := b.z.y - k * b.z.z                   # how fast the edge rises past the slope per m back
	if climb <= 1e-4:
		return dist
	var level := CEIL_AT_BACK - k * CEIL_BACK          # underside: y - k z stays below this
	var d := (level - (top.y - k * top.z)) / climb   # where the edge's ray crosses the underside
	var cross := top + b.z * d
	if d >= dist or cross.z < CEIL_BACK or cross.z > CEIL_FRONT:
		return dist
	return maxf(d, 0.3)


func click(cursor: Vector2, held: ItemData) -> void:
	if settled():
		clicked.emit(cursor, held)
