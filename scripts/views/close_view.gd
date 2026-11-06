extends Node
## Base class for close-up camera views: the room camera eases into a fixed pose looking at
## something, and back out again.
##
## crafting_view.gd (straight down onto the workbench's cutting mat) and radio_view.gd (the ham
## radio's front panel) extend this. While a view is active, room_camera.gd blends it into the room
## camera, the room's hover is off, the ceiling hides, and overlay.gd shows a BACK button once it
## has settled. Esc, right-click and BACK all call exit().
##
## To add a view: extend this script, set _pose (camera transform), _size (orthographic width in
## metres) and _focus (the point it looks at) in a setup() function, then create it in main.gd and
## add it to `views`. See docs/HOW_TO.md.

## the camera has settled on the close-up
signal entered
## the camera is back in the room
signal exited

const MOVE_FRAMES := 28.0               # 24 fps frames for the full camera move

var open := false                       # where the camera is heading
var t := 0.0                            # 0 = room view .. 1 = close-up

var _pose: Transform3D                  # set by the subclass's setup()
var _size: float                        # ortho width of the close-up
var _focus: Vector3                     # what the close-up looks at: the pivot of the move
var _from_t := 0.0
var _at := -1e9


func enter(now: float) -> void:
	if not open:
		open = true
		_from_t = t
		_at = now


func exit(now: float) -> void:
	if open:
		open = false
		_from_t = t
		_at = now


## true once the camera has settled on the close-up (its input is live)
func settled() -> bool:
	return open and t >= 1.0


## true while the view owns the screen (moving or settled); the room ignores input
func active() -> bool:
	return open or t > 0.0


## per frame, from room_camera.gd; subclasses extend it for their own hover
func update(now: float, _cursor: Vector2, _cursor_free: bool) -> void:
	var goal := 1.0 if open else 0.0
	var span := absf(goal - _from_t) * MOVE_FRAMES
	var was := t
	t = goal if span <= 0.0 else lerpf(_from_t, goal, clampf((now - _at) / span, 0.0, 1.0))
	if t >= 1.0 and was < 1.0:
		entered.emit()
	elif t <= 0.0 and was > 0.0:
		exited.emit()


## a click while the view is active (after the UI had its turn); held is the item on the cursor
func click(_cursor: Vector2, _held: ItemData) -> void:
	pass


## blend the room camera into the close-up: both look at a pivot at the focus's depth, and the
## pivot, view direction, distance and zoom all ease across together
func camera_pose(room: Transform3D, room_size: float) -> Array:
	if t <= 0.0:
		return [room, room_size]
	var e := smoothstep(0.0, 1.0, t)
	if e >= 1.0:
		return [_pose, _size]
	var f0 := -room.basis.z
	var d0 := (room.origin.z - _focus.z) / maxf(-f0.z, 1e-3)
	var pivot0 := room.origin + f0 * d0
	var d1 := (_pose.origin - _focus).length()
	var q := room.basis.get_rotation_quaternion().slerp(_pose.basis.get_rotation_quaternion(), e)
	var b := Basis(q)
	var dist := exp(lerpf(log(d0), log(d1), e))
	var size := exp(lerpf(log(room_size), log(_size), e))
	return [Transform3D(b, pivot0.lerp(_focus, e) + b.z * dist), size]
