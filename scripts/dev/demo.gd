extends Node
## A scripted walkthrough for checking the game without playing it: drives the cursor through the
## room and its interactions on a timeline, saves 480x270 screenshots, then quits.
##
##     godot --path . -- --demo screens            # walkthrough -> screens/*.png
##     godot --path . -- --demo screens --raw      # one unprocessed frame + the object mask
##     godot --path . -- --demo screens --menus    # the title screen, how to play, settings, pause
##
## Add --rendering-driver opengl3 (before --) to check the Compatibility renderer the web build uses.
## Compare the screenshots before and after a change to catch regressions.

var _main: Node


## start if the command line asks for it (called at the end of main.gd's _ready)
func start_if_asked(main: Node) -> void:
	_main = main
	var args := OS.get_cmdline_user_args()
	var i := args.find("--demo")
	if i < 0:
		return
	if args.has("--menus"):
		_menus(args[i + 1] if i + 1 < args.size() else "user://shots")
		return
	main.start_menu.active = false       # the walkthrough starts in the room, past the title screen
	main.start_menu.visible = false
	main.pause_menu.pause_button_enabled = true
	main.start_game()
	var out := args[i + 1] if i + 1 < args.size() else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join(".gdignore"), FileAccess.WRITE)   # keep the shots out of the import/export
	main.cursor_override = Vector2(main.W / 2.0, main.H / 2.0)      # the real mouse may sit on an edge and pan
	if args.has("--raw"):
		_raw(out)
	else:
		_run(out)


## the menus, one screenshot each. They read the real mouse, so keep it away from the window.
func _menus(out: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # the pause menu pauses the tree
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join(".gdignore"), FileAccess.WRITE)
	var start = _main.start_menu
	var pause = _main.pause_menu
	await _menu_shot(out, "menu_1_title")
	start._activate("how")
	await _menu_shot(out, "menu_2_how_to_play")
	start._show_main()
	start._activate("settings")
	await _menu_shot(out, "menu_3_settings")
	pause.resume()
	start._activate("start")
	await _menu_shot(out, "menu_4_in_game")
	pause.open_pause()
	await _menu_shot(out, "menu_5_paused")
	get_tree().quit()


func _menu_shot(out: String, shot_name: String) -> void:
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(shot_name + ".png"))


## a plain lit frame (no post shader, no UI) and the object-id mask, for matching Blender's renders
func _raw(out: String) -> void:
	_main.screen.material = null
	_main.get_node("UI").visible = false
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("raw.png"))
	_main.mask_vp.get_texture().get_image().save_png(out.path_join("mask.png"))
	get_tree().quit()


## the timeline: [frame (24 fps), action, arguments...]. Actions are listed in _do().
const STEPS := [
	[20, "shot", "01_bench_view"],
	[21, "hover", "lantern"], [45, "shot", "02_hover_lantern"],
	[46, "hover", "speaker"], [70, "shot", "03_hover_speaker"],
	[71, "pan", "left"], [90, "shot", "03b_pushing_left"], [150, "shot", "04_window_view"],
	[151, "hover", "shutters"], [175, "shot", "05_hover_shutters"],
	[176, "click"], [200, "shot", "06_shutters_opening"], [320, "shot", "07_heat"],
	[321, "hover", "sky", Vector2(40, -14)], [330, "shot", "07b_hover_open_window"], [331, "click"], [460, "shot", "08_closed_again"],
	[461, "pan", "right"], [485, "shot", "08b_pushing_right"], [540, "hover", "microfiche"], [560, "shot", "09_hover_fiche"],
	[561, "click"], [575, "shot", "10_fiche_blank"],
	[576, "contact", ["kl7_anchorage", "du1_manila", "5n_lagos", "cx_montevideo"]],
	[577, "fiche_center", Vector2(57.0, -142.0)], [580, "shot", "10b_fiche_marks"],
	[581, "fiche_mark", "kl7_anchorage"], [590, "shot", "10c_fiche_note"],
	[591, "fiche_click", "kl7_anchorage"], [594, "shot", "10d_fiche_zoomed"],
	[595, "point", Vector2(447, 130)], [603, "shot", "10e_fiche_zoomed_panning"],
	[604, "close_box"], [608, "shot", "11_fiche_close_hover"], [609, "click"], [620, "shot", "12_back"],
	[621, "hover", "cabinet", Vector2(0, -20)], [640, "shot", "13_hover_cabinet"], [641, "click"],
	[700, "shot", "14_cabinet_open"],
	[701, "hover", "jar"], [720, "shot", "15_hover_jar"], [721, "click"], [728, "shot", "16_jar_flying"],
	[745, "hover", "papers"], [765, "shot", "17_hover_papers"], [766, "click"],
	[800, "point", Vector2(196, 255)], [815, "shot", "18_hover_slot"], [816, "click"],
	[817, "hover", "bench", Vector2(0, 20)], [840, "shot", "19_holding_over_bench"], [841, "click"],
	[860, "point", Vector2(218, 255)], [870, "shot", "20_back_in_inventory"],
	[871, "hover", "bench", Vector2(0, 20)], [880, "shot", "21_hover_bench"], [881, "click"],
	[895, "shot", "22_craft_swing"], [920, "shot", "23_craft_view"],
	[921, "cell", Vector2i(4, 2)], [935, "shot", "24_craft_hover_cell"],
	[936, "point", Vector2(20, 12)], [945, "shot", "25_craft_hover_back"], [946, "click"],
	[960, "shot", "26_craft_leaving"], [985, "shot", "27_back_in_room"],
	# crafting: take the broken radio, the battery and the PA speaker, fix the radio, put it back
	[986, "radio"], [995, "shot", "28_hover_radio"], [996, "click"], [1010, "shot", "29_radio_taken"],
	[1011, "hover", "battery"], [1025, "shot", "30_hover_battery"], [1026, "click"],
	[1040, "hover", "speaker"], [1055, "shot", "31_hover_speaker"], [1056, "click"], [1078, "shot", "32_parts_taken"],
	[1080, "hover", "bench", Vector2(0, 20)], [1081, "click"], [1120, "shot", "33_craft_view"],
	[1121, "hold", "radio_broken"], [1122, "cell", Vector2i(3, 2)], [1124, "click"],
	[1126, "hold", "battery"], [1127, "cell", Vector2i(5, 2)], [1129, "click"], [1135, "shot", "34_craft_no_match"],
	[1136, "hold", "speaker"], [1137, "cell", Vector2i(7, 4)], [1139, "click"],
	[1141, "point", Vector2(425, 135)], [1150, "shot", "35_craft_result"], [1151, "click"],
	[1156, "shot", "36_crafted_flying"], [1175, "shot", "37_crafted"],
	[1176, "point", Vector2(20, 12)], [1177, "click"], [1215, "shot", "38_back_in_room"],
	[1216, "hold", "radio"], [1217, "point", Vector2(240, 120)], [1225, "shot", "39_radio_spot_outline"],
	[1226, "radio"], [1235, "shot", "40_hover_radio_spot"], [1236, "click"], [1245, "shot", "41_radio_fixed"],
	[1246, "click"], [1285, "shot", "42_radio_view"],
	[1286, "point", Vector2(20, 12)], [1287, "click"], [1325, "shot", "43_back_from_radio"],
	[1326, "debug"], [1335, "shot", "44_debug_menu"],
	[1336, "quit"],
]


func _run(out: String) -> void:
	for s in STEPS:
		while _main.clock < s[0]:
			await get_tree().process_frame
		await _do(s, out)


func _do(s: Array, out: String) -> void:
	var main := _main
	match s[1]:
		"shot":                          # save the screen as <name>.png
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join(s[2] + ".png"))
		"hover":                         # put the cursor on an object group (+ an optional offset)
			main.cursor_override = main.picker.screen_point(s[2]) + (s[3] if s.size() > 3 else Vector2.ZERO)
		"point":                         # put the cursor on a screen pixel
			main.cursor_override = s[2]
		"pan":                           # park the cursor on that screen edge so the view pans
			main.cursor_override = Vector2(1.0 if s[2] == "left" else main.W - 2.0, main.H / 2.0)
		"click":
			main.click()
		"close_box":                     # the microfiche's close box
			main.cursor_override = main.ui.microfiche.CLOSE
		"radio":                         # the radio's front panel (its group's centre is up the coax)
			var f: Array = main.meta.points.radio_front
			main.cursor_override = main.camera.unproject_position(Vector3(f[0], f[1], f[2]))
		"contact":                       # mark stations as reached
			for id in s[2]:
				GameState.contact_station(id)
		"fiche_center":                  # centre the microfiche on Vector2(lat, lon)
			main.ui.microfiche.center_on(s[2].x, s[2].y)
		"fiche_mark":                    # hover a station's mark
			var st: Dictionary = GameState.stations[s[2]]
			main.cursor_override = main.ui.microfiche.screen_px(st.lat, st.lon)
		"fiche_click":                   # click (press + release) inside a station's revealed patch
			var sc: Dictionary = GameState.stations[s[2]]
			main.cursor_override = main.ui.microfiche.screen_px(sc.lat - 1.5, sc.lon + 1.5)
			main.cursor = main.cursor_override
			main.click()
			main.ui.release_click(main.cursor_override)
		"cell":                          # the middle of a crafting grid cell
			main.cursor_override = Vector2(main.crafting.cell_rect(s[2]).get_center())
		"hold":                          # put an inventory item on the cursor, as clicking its slot does
			main.ui.inventory.held = InventoryManager.get_item(s[2])
		"debug":                         # open the F9 menu
			main.debug_menu.open = true
			main.cursor_override = Vector2(240, 80)
		"quit":
			get_tree().quit()
