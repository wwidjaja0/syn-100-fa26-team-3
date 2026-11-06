extends "res://scripts/views/close_view.gd"
## The crafting view. Clicking the workbench swings the camera straight down onto the
## cutting mat, whose printed grid is the build grid. This script owns the grid maths
## (the camera move is close_view.gd's); what crafting actually does is left open (see the signals).
##
## The mat texture is drawn so one texel is one screen pixel in this view
## (pipeline/scene/make_mat.py), and the camera is placed so the mat starts on a whole
## pixel. Every cell is therefore an exact cell_px square on the 480x270 screen.

## the cursor moved onto another cell (NO_CELL when it leaves the grid)
signal cell_hovered(cell: Vector2i)
## a grid cell was clicked; held is the item on the cursor, or null
signal cell_clicked(cell: Vector2i, held: ItemData)

const NO_CELL := Vector2i(-1, -1)
const CAM_HEIGHT := 2.0                 # m above the mat: above the pendant shade, so the swing never runs through
                                        # it, and under the ceiling (hidden during the swing anyway)

var cols: int
var rows: int
var cell_px: int
var mat_px: Rect2i                      # the whole mat on screen, in the settled view
var grid_px: Rect2i                     # the grid, including its closing line
var hover_cell := NO_CELL

var _px: float                          # metres per screen pixel over the mat
var _mat_corner: Vector3                # world position of the mat's back-left corner (top of screen)


## size the view from scene_meta.json's "craft" block (written by pipeline/godot/export_glb.py)
func setup(meta: Dictionary, w: int, h: int) -> void:
	var c: Dictionary = meta.craft
	cols = int(c.cols)
	rows = int(c.rows)
	cell_px = int(c.cell_px)
	_px = 1.0 / (float(c.px_per_cm) * 100.0)
	_size = w * _px
	var size := Vector2i(int(c.px[0]), int(c.px[1]))
	var center := Vector3(c.mat_center[0], c.mat_center[1], c.mat_center[2])
	_mat_corner = center - Vector3(size.x, 0, size.y) * _px / 2.0
	mat_px = Rect2i(Vector2i((w - size.x) / 2, (h - size.y) / 2), size)
	grid_px = Rect2i(mat_px.position + Vector2i(int(c.grid_origin_px[0]), int(c.grid_origin_px[1])),
			Vector2i(cols * cell_px + 1, rows * cell_px + 1))
	# screen pixel edges fall at camera centre + whole pixels, so put the mat corner on one
	_focus = _mat_corner + Vector3(w / 2 - mat_px.position.x, 0, h / 2 - mat_px.position.y) * _px
	_pose = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), _focus + Vector3(0, CAM_HEIGHT, 0))


func exit(now: float) -> void:
	super.exit(now)
	_set_hover(NO_CELL)


func update(now: float, cursor: Vector2, cursor_free: bool) -> void:
	super.update(now, cursor, cursor_free)
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
