extends Node
## The crafting view. Clicking the workbench swings the camera straight down onto the
## cutting mat, whose printed grid is the build grid. This script owns that camera move
## and the grid maths; what crafting actually does is left open (see the signals).
##
## The mat texture is drawn so one texel is one screen pixel in this view
## (pipeline/scene/make_mat.py), and the camera is placed so the mat starts on a whole
## pixel. Every cell is therefore an exact cell_px square on the 480x270 screen.

## the camera has settled over the mat
signal entered
## the camera is back in the room
signal exited
## the cursor moved onto another cell (NO_CELL when it leaves the grid)
signal cell_hovered(cell: Vector2i)
## a grid cell was clicked; held is the item on the cursor, or null
signal cell_clicked(cell: Vector2i, held: ItemData)

const NO_CELL := Vector2i(-1, -1)
const MOVE_FRAMES := 28.0               # 24 fps frames for the full camera swing
const CAM_HEIGHT := 1.25                # m above the mat: under the pendant lamp, over the radio aerial

var cols: int
var rows: int
var cell_px: int
var mat_px: Rect2i                      # the whole mat on screen, in the settled view
var grid_px: Rect2i                     # the grid, including its closing line
var open := false                       # where the camera is heading
var t := 0.0                            # 0 = room view .. 1 = over the mat
var hover_cell := NO_CELL

var _top_xform: Transform3D
var _top_size: float
var _px: float                          # metres per screen pixel over the mat
var _mat_corner: Vector3                # world position of the mat's back-left corner (top of screen)
var _from_t := 0.0
var _at := -1e9


## size the view from scene_meta.json's "craft" block (written by pipeline/godot/export_glb.py)
func setup(meta: Dictionary, w: int, h: int) -> void:
	var c: Dictionary = meta.craft
	cols = int(c.cols)
	rows = int(c.rows)
	cell_px = int(c.cell_px)
	_px = 1.0 / (float(c.px_per_cm) * 100.0)
	_top_size = w * _px
	var size := Vector2i(int(c.px[0]), int(c.px[1]))
	var center := Vector3(c.mat_center[0], c.mat_center[1], c.mat_center[2])
	_mat_corner = center - Vector3(size.x, 0, size.y) * _px / 2.0
	mat_px = Rect2i(Vector2i((w - size.x) / 2, (h - size.y) / 2), size)
	grid_px = Rect2i(mat_px.position + Vector2i(int(c.grid_origin_px[0]), int(c.grid_origin_px[1])),
			Vector2i(cols * cell_px + 1, rows * cell_px + 1))
	# screen pixel edges fall at camera centre + whole pixels, so put the mat corner on one
	var cam := _mat_corner + Vector3(w / 2 - mat_px.position.x, 0, h / 2 - mat_px.position.y) * _px
	_top_xform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), cam + Vector3(0, CAM_HEIGHT, 0))


# ---------------------------------------------------------------- state
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
		_set_hover(NO_CELL)


## true once the camera has settled over the mat (grid input is live)
func settled() -> bool:
	return open and t >= 1.0


## true while the crafting view owns the screen (moving or settled); the room ignores input
func active() -> bool:
	return open or t > 0.0


func update(now: float, cursor: Vector2, cursor_free: bool) -> void:
	var goal := 1.0 if open else 0.0
	var span := absf(goal - _from_t) * MOVE_FRAMES
	var was := t
	t = goal if span <= 0.0 else lerpf(_from_t, goal, clampf((now - _at) / span, 0.0, 1.0))
	if t >= 1.0 and was < 1.0:
		entered.emit()
	elif t <= 0.0 and was > 0.0:
		exited.emit()
	_set_hover(cell_at(cursor) if settled() and cursor_free else NO_CELL)


func click(cursor: Vector2, held: ItemData) -> void:
	if not settled():
		return
	var cell := cell_at(cursor)
	if cell != NO_CELL:
		cell_clicked.emit(cell, held)


func _set_hover(cell: Vector2i) -> void:
	if cell != hover_cell:
		hover_cell = cell
		cell_hovered.emit(cell)


# ---------------------------------------------------------------- grid maths
## the cell under a screen pixel, or NO_CELL. A grid line belongs to the cell right of / below it.
func cell_at(p: Vector2) -> Vector2i:
	var q := Vector2i(p.floor()) - grid_px.position
	if q.x < 0 or q.y < 0:
		return NO_CELL
	var cell := Vector2i(q.x / cell_px, q.y / cell_px)
	return cell if cell.x < cols and cell.y < rows else NO_CELL


## a cell's square on screen, including the grid lines around it (cell_px + 1 wide)
func cell_rect(cell: Vector2i) -> Rect2i:
	return Rect2i(grid_px.position + cell * cell_px, Vector2i(cell_px + 1, cell_px + 1))


## the world point at the centre of a cell, on the mat's surface (to stand 3D pieces on)
func cell_world(cell: Vector2i) -> Vector3:
	var p := Vector2(grid_px.position - mat_px.position) + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_px + Vector2(0.5, 0.5)
	return _mat_corner + Vector3(p.x, 0, p.y) * _px


# ---------------------------------------------------------------- camera
## blend the room camera into the top-down one: both look at a pivot on the mat's depth and
## the pivot, view direction, distance and zoom all ease across together
func camera_pose(room: Transform3D, room_size: float) -> Array:
	if t <= 0.0:
		return [room, room_size]
	var e := smoothstep(0.0, 1.0, t)
	if e >= 1.0:
		return [_top_xform, _top_size]
	var f0 := -room.basis.z
	var d0 := (room.origin.z - _mat_corner.z) / maxf(-f0.z, 1e-3)
	var pivot0 := room.origin + f0 * d0
	var pivot1 := _top_xform.origin + Vector3.DOWN * CAM_HEIGHT
	var q := room.basis.get_rotation_quaternion().slerp(_top_xform.basis.get_rotation_quaternion(), e)
	var basis := Basis(q)
	var dist := exp(lerpf(log(d0), log(CAM_HEIGHT), e))
	var size := exp(lerpf(log(room_size), log(_top_size), e))
	return [Transform3D(basis, pivot0.lerp(pivot1, e) - (-basis.z) * dist), size]
