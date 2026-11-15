extends "res://scripts/views/close_view.gd"
## The reef tank close-up. Clicking the tank (or its gauge board) brings the camera level with the
## glass, with the tank on the left of the screen and room on the right for the tank's panel
## (readings and item slots: tank/tank_panel.gd, drawn by overlay.gd).
##
## The tank is built in code (room/fish_tank.gd), so the view frames it from that script's constants
## rather than a scene_meta.json point.

## a click while the view is settled; held is the item on the cursor, or null
signal clicked(cursor: Vector2, held: ItemData)

const FishTank := preload("res://scripts/room/fish_tank.gd")
const WIDTH := 2.2                      # m across the screen: the tank fills the left ~60%
const SHIFT := 0.35                     # m the view looks right of the tank's centre (room for the panel)
const TILT := deg_to_rad(6.0)           # looking slightly down into the water
const DIST := 2.0                       # m in front of the glass (only matters for clipping)


func setup() -> void:
	_focus = Vector3(FishTank.TX + SHIFT, FishTank.STAND_H + FishTank.TANK.y / 2.0 + 0.04,
			FishTank.TANK_Z + FishTank.TANK.z / 2.0)
	var b := Basis.from_euler(Vector3(-TILT, 0, 0))
	_pose = Transform3D(b, _focus + b.z * DIST)
	_size = WIDTH


func click(cursor: Vector2, held: ItemData) -> void:
	if settled():
		clicked.emit(cursor, held)
