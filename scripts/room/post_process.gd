extends Node
## Feeds the post-process shader (shaders/post.gdshader) on the full-screen `Screen` TextureRect.
##
## The room is rendered at 480x270 into WorldVP, and the object-id mask into MaskVP. The post
## shader turns that render into the final look: toon light bands, heat shimmer, Bayer dither,
## snapping to the 40-colour palette, and the white hover outline (from the mask). This script
## connects the two renders and the palette once, then updates the shader's inputs every frame.

const SHIMMER_FRAMES := 2.0             # the hover shimmer pattern jumps every this many frames

var _main: Node
var _mat: ShaderMaterial
var _window_point: Vector3              # the window's centre, for the heat shimmer's focus
var _shimmer_step := -1


func setup(main: Node, meta: Dictionary, screen: TextureRect, world_vp: SubViewport, mask_vp: SubViewport) -> void:
	_main = main
	_mat = screen.material
	screen.texture = world_vp.get_texture()
	_mat.set_shader_parameter("scene_tex", world_vp.get_texture())
	_mat.set_shader_parameter("mask_tex", mask_vp.get_texture())
	var pal := PackedVector3Array()
	for c in JSON.parse_string(FileAccess.get_file_as_string("res://assets/palette.json")):
		pal.append(Vector3(c[0], c[1], c[2]) / 255.0)
	_mat.set_shader_parameter("palette", pal)
	var w: Array = meta.points.window
	_window_point = Vector3(w[0], w[1], w[2])


func update() -> void:
	var clock: float = _main.clock
	var picker = _main.picker
	var shutters = _main.shutters
	_mat.set_shader_parameter("frame", clock)
	_mat.set_shader_parameter("cam_px", _main.room_camera.cam_px)
	_mat.set_shader_parameter("noise_seed", fmod(clock, 97.0))
	_mat.set_shader_parameter("cursor", _main.cursor.floor())
	_mat.set_shader_parameter("target_id", picker.id_of(picker.hover))               # hover outline
	_mat.set_shader_parameter("build", 1.0 - exp(-picker.hover_t / 10.0))            # outline grows in
	_mat.set_shader_parameter("outline_px", 3 if _main.clicking() else 2)
	_mat.set_shader_parameter("heat", shutters.heat)
	_mat.set_shader_parameter("heat_focus", 1.0)
	_mat.set_shader_parameter("shutter", shutters.value)
	_mat.set_shader_parameter("window_px", _main.camera.unproject_position(_window_point))
	_mat.set_shader_parameter("dim", _main.ui.panel_scale())                         # darken behind panels
	var s := int(clock / SHIMMER_FRAMES)
	if s != _shimmer_step:
		_shimmer_step = s
		_mat.set_shader_parameter("shimmer_off", Vector2(randi() % 4, randi() % 4))
