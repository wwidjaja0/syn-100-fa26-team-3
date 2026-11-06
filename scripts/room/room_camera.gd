extends Node
## The room camera (WorldVP/Camera) and its twin for the object mask (MaskVP/MaskCam).
##
## The room is seen through a fixed orthographic camera that only pans left and right:
##   * pushing the cursor into the band near the left or right screen edge pans that way, harder
##     the closer to the edge; past the edge (off the window, in the black borders, or off the
##     browser page) it pans at full speed; A/D or the arrow keys pan at full speed too;
##   * the position is snapped to whole screen pixels, so the pixel art never shimmers;
##   * when a close-up view (scripts/views/) is opening or open, its camera pose is blended in
##     instead, and the sloped ceiling hides (both close-up cameras swing up through it).
## `push` (-1..1) tells overlay.gd to draw the edge chevrons.

const EDGE := 48.0                      # px from the screen edge where the cursor starts pushing
const PAN_SPEED := 2.6                  # m/s at full push
const PAN_EASE := 8.0                   # how quickly the camera speeds up / settles (1/s)
const CAM_MIN := -1.85                  # camera x limits: the left wall .. just past the speaker corner
const CAM_MAX := 3.0
const ORTHO_WIDTH := 6.6                # m across the screen (matches the Blender camera)

var push := 0.0                         # -1..1: how hard the cursor (or A/D) is pushing the view
var cam_px := 0.0                       # the pan in whole screen pixels (the post shader's dither follows it)
var x := 0.0                            # camera x, m
var velocity := 0.0                     # m/s

var _main: Node
var _cameras: Array[Camera3D] = []
var _pix: float                         # m per screen pixel
var _x_left: float                      # camera x at the left end of its range (pixel snapping origin)
var _basis: Basis                       # the room camera's fixed tilt, height, depth and zoom
var _y: float
var _z: float
var _size: float
var _edge_hold := false                 # after a panel or close-up the cursor may sit in an edge band
                                        # (BACK is top-left): no edge-push until it has left the band
var _ceiling: Array[Node3D] = []
var _web_out := Vector2.ZERO            # web: which way the pointer left the page
var _web_callbacks := []                # keeps the JavaScript callbacks alive


func setup(main: Node, meta: Dictionary, room: Node3D, camera: Camera3D, mask_cam: Camera3D) -> void:
	_main = main
	_cameras = [camera, mask_cam]
	_pix = ORTHO_WIDTH / main.W
	_x_left = meta.camera.x_left
	x = meta.camera.x_right             # start over the workbench
	_basis = camera.basis
	_y = camera.position.y
	_z = camera.position.z
	_size = camera.size
	for n in room.find_children("ceiling_*", "", true, false):
		if n.name.begins_with("ceiling_panel") or n.name.begins_with("ceiling_rafter"):
			_ceiling.append(n)
	if OS.has_feature("web"):
		_watch_web_mouse()


## per frame: pan, let the close-up views move, and place both cameras
func update(delta: float) -> void:
	_update_push()
	velocity = lerpf(velocity, push * PAN_SPEED, 1.0 - exp(-delta * PAN_EASE))
	x += velocity * delta
	if x < CAM_MIN or x > CAM_MAX:
		x = clampf(x, CAM_MIN, CAM_MAX)
		velocity = 0.0
	cam_px = roundf((x - _x_left) / _pix)
	var room := Transform3D(_basis, Vector3(_x_left + cam_px * _pix, _y, _z))
	var pose: Array = [room, _size]
	var cursor: Vector2 = _main.cursor
	for v in _main.views:
		v.update(_main.clock, cursor, not _main.ui.over_ui(cursor))
		if v.t > 0.0:
			pose = v.camera_pose(room, _size)
	for cam in _cameras:
		cam.transform = pose[0]
		cam.size = pose[1]
	var in_room: bool = _main.active_view() == null
	for c in _ceiling:
		c.visible = in_room


func panning() -> bool:
	return absf(velocity) > 0.05


func _update_push() -> void:
	push = 0.0
	var ui = _main.ui
	if _main.active_view() != null or ui.panel != "":
		_edge_hold = true
		return
	var cursor: Vector2 = _main.cursor
	var w: float = _main.W
	if _edge_hold and cursor.x >= EDGE and cursor.x <= w - 1 - EDGE:
		_edge_hold = false
	var live: bool = _main.cursor_override != null or (_main.mouse_seen and get_window().has_focus())
	var out := mouse_outside()
	if live and not _edge_hold and out.x != 0.0:
		push = out.x                     # the mouse is past that side: full speed
	elif live and not _edge_hold:
		if cursor.x < EDGE:
			push = -pow((EDGE - cursor.x) / EDGE, 1.5)
		elif cursor.x > w - 1 - EDGE:
			push = pow((cursor.x - (w - 1 - EDGE)) / EDGE, 1.5)
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		push = -1.0
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		push = 1.0
	if (push < 0.0 and x <= CAM_MIN) or (push > 0.0 and x >= CAM_MAX):
		push = 0.0                       # already against the wall


## which way the pointer is past the game area (-1 / 0 / +1 per axis). The game cursor is clamped
## to the screen, so this is how pans keep going at full speed past an edge:
##   * in the black borders around the scaled picture: Godot still reports where it is (main.beyond);
##   * outside the window on desktop: ask the OS where the mouse is;
##   * outside the page on the web: the edge it left by (browsers stop reporting it).
func mouse_outside() -> Vector2:
	if _main.cursor_override != null or not _main.mouse_seen:
		return Vector2.ZERO
	if _main.beyond != Vector2.ZERO:
		return _main.beyond
	if OS.has_feature("web"):
		return _web_out
	if not get_window().has_focus():
		return Vector2.ZERO
	var win := get_window()
	var p := Vector2(DisplayServer.mouse_get_position() - win.position)
	var out := Vector2.ZERO
	out.x = -1.0 if p.x < 0 else (1.0 if p.x >= win.size.x else 0.0)
	out.y = -1.0 if p.y < 0 else (1.0 if p.y >= win.size.y else 0.0)
	return out


## Listen for the page's own mouseleave / mouseenter, and remember the edge the pointer left by
## (the nearest one to where it went out).
func _watch_web_mouse() -> void:
	var root = JavaScriptBridge.get_interface("document").documentElement
	var leave := JavaScriptBridge.create_callback(_on_web_mouse_leave)
	var enter := JavaScriptBridge.create_callback(func(_args): _web_out = Vector2.ZERO)
	root.addEventListener("mouseleave", leave)
	root.addEventListener("mouseenter", enter)
	_web_callbacks = [leave, enter]


func _on_web_mouse_leave(args: Array) -> void:
	var e = args[0]
	var win = JavaScriptBridge.get_interface("window")
	var px: float = e.clientX
	var py: float = e.clientY
	var w: float = win.innerWidth
	var h: float = win.innerHeight
	var dist := [px, w - 1.0 - px, py, h - 1.0 - py]          # to the left, right, top and bottom edges
	var near: float = minf(minf(dist[0], dist[1]), minf(dist[2], dist[3])) + 16.0
	_web_out = Vector2((-1.0 if dist[0] <= near and dist[0] <= dist[1] else (1.0 if dist[1] <= near else 0.0)),
			(-1.0 if dist[2] <= near and dist[2] <= dist[3] else (1.0 if dist[3] <= near else 0.0)))
