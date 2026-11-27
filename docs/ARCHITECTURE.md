# How the game works

This is a map of the game code: what runs where, in what order, and how the pieces talk to each other. For the
assets and how they're built, see [`PIPELINE.md`](PIPELINE.md). For step-by-step recipes, see
[`HOW_TO.md`](HOW_TO.md).

## The big picture

The whole game is one scene, `scenes/main.tscn`. A pre-built 3D room (`assets/shelter.glb`, exported from Blender)
is rendered twice each frame at 480x270:

1. **WorldVP** renders what you see, with the toon shader on every surface.
2. **MaskVP** renders the same room from the same camera, but each object is painted with a flat id colour for its
   *object group*. That's how the game knows what's under the cursor.

A full-screen `TextureRect` (**Screen**) runs the post shader over WorldVP's image. It adds banding, heat shimmer,
dither, the palette snap and the white hover outline (read from MaskVP). On top of that, a `Control` (**UI/Overlay**)
draws the pixel UI: labels, the inventory bar, the microfiche panel, the cursor. The project's window stretch
settings upscale the 480x270 canvas by a whole number with nearest-neighbour, so pixels stay square.

```
Main (Node, scripts/main.gd)
├── WorldVP (SubViewport 480x270)        the room as seen
│   ├── Room                             assets/shelter.glb (every interactable under a grp_<name> node)
│   ├── Camera                           orthographic, pans left/right (room_camera.gd moves it)
│   ├── WorldEnvironment
│   └── Lights/                          pendant_key (the only shadowed light), lantern_glow, cabinet_interior, ...
├── MaskVP (SubViewport 480x270)         the same room, as flat object-id colours
│   └── MaskCam                          follows Camera exactly; sees render layer 20 (the mask pass)
├── Screen (TextureRect)                 WorldVP's image through shaders/post.gdshader
├── UI (CanvasLayer)
│   └── Overlay (Control, scripts/ui/overlay.gd)   the pixel UI, drawn last
└── (added at run time by main.gd) Interactions, ObjectPicker, RoomMaterials, Shutters, Cabinet,
    Ambience, CraftingView, RadioView, RoomCamera, PostProcess, DebugMenu, Demo
```

WorldVP and MaskVP share the scene's `World3D`, because neither sets a `world_3d` of its own. So one room instance
serves both.

## The scripts

`scripts/main.gd` is the coordinator. It holds almost no logic: it creates each part, calls the parts in a fixed
order every frame, and routes input. Each part is one file with one job.

| Script | Job | Main entry points |
|---|---|---|
| `main.gd` | Builds the parts, runs the frame, routes input | `click()`, `back(full)`, `active_view()`, `clock`, `cursor` |
| `game_state.gd` | **Autoload `GameState`.** Day, story flags, stations reached, revealed map areas | `set_flag`, `flag`, `advance_day()`, `contact_station(id)`, `reveal(lat, lon, deg)`, signals `changed`, `station_contacted` |
| `inventory/inventory_manager.gd` | **Autoload `InventoryManager`.** What the player carries (max 5) | `get_item(id)`, `add_item`, `remove_item`, `has_item`, signal `inventory_updated` |
| `inventory/item_data.gd` | `ItemData` resource: `id`, `name`, `icon` | one `.tres` per item in `items/` |
| `inventory/inventory_data.gd` | `InventoryData` resource: the list of carried items | |
| `room/interactions.gd` | **The game rules:** hover labels and what clicking each object does | `LABELS`, `click(group)`, `use_item(item, group)`, `pick_up(group, item_id, hide)`, `say(id)`, `then_after_dialogue(action)` |
| `room/fish_tank.gd` | Wires up `scenes/fish_tank.tscn` (the reef tank and gauge board) and animates the fish, bubbles, kelp and needles. The cabin's widened left end is `scenes/room_left.tscn` | `build(main, room, meta, lights)`, `update()`, `EXTRA` |
| `room/object_picker.gd` | Reads the mask render: which group is under the cursor | `hover`, `group_at(p)`, `group_of(node)`, `screen_point(group)` |
| `room/room_materials.gd` | Replaces the room's imported materials with the toon shader | `set_param(material, param, value)` |
| `room/shutters.gd` | Storm shutters swing open/shut; how much heat gets in rises and falls | `toggle()`, `is_open`, `heat` |
| `room/cabinet.gd` | Supply cabinet doors and the light inside | `toggle()` |
| `room/weather.gd` | The weather outside the window: presets (storm, rain, overcast, marine fog, clear, wildfire smoke) picked at random and cross-faded, a new one each day, day 1 (the tutorial) rainy only; lightning, and the window lights' colour to match; the outside temperature and the rain | `set_weather(name)`, `pick(name)`, `choices()`, `after(name)`, `temperature()`, `rain()`, `heat(open)`, `update(delta, clock)` |
| `room/leak.gd` | The hole under the window: the sandbag that belongs in it (starts thrown up on the pile), the stream and the puddle while it's open | `state()` ("open", "bag", "filter"), `leaking()`, `plug()`, `make_way()`, `level` |
| `room/water_filter.gd` | The bucket filter beside the hole: its intake run out through the hole (flag `filter_installed`), when it runs (shutters open + rain), and the jug it fills, taken as CLEAN WATER | `installed()`, `blocked()`, `running()`, `fill`, `click()`, `click_jug()`, `return_jug()` |
| `room/pendant.gd` | The hanging lamp's pull chain: lights out, a fade, `GameState.advance_day()`, the morning; not while the hole leaks | `pull()`, `busy()`, `blackout()`, `card()` |
| `room/ambience.gd` | Things that move on their own: storm sky, PA status light, lantern, the battery dock's green light (blinks while charging, solid when full, flag `battery_charged`) and the radio's red one | |
| `room/room_camera.gd` | Edge panning, pixel snapping, blending into close-up views | `x`, `push`, `cam_px` |
| `room/post_process.gd` | Hooks the renders and palette into `post.gdshader`; updates its uniforms | |
| `room/ease.gd` | Easing curves (`smooth`, `out_back`) | static functions |
| `views/close_view.gd` | Base class for close-ups: camera eases from the room to a fixed pose and back | `enter(now)`, `exit(now)`, `settled()`, `active()`, signals `entered`, `exited` |
| `views/crafting_view.gd` | Close-up straight down onto the cutting mat; the build grid | `cell_at(p)`, `cell_rect`, `cell_world`, signals `cell_hovered`, `cell_clicked` |
| `views/radio_view.gd` | Close-up of the ham radio's front panel | signal `clicked`, `screen_point(world)` |
| `crafting/crafting.gd` | **The crafting rules** (`main.workbench`): items lying on the mat, `RECIPES`, making the result | `placed`, `item_at(cell)`, `result()`, `craft(from)`, signals `changed`, `crafted` |
| `views/tank_view.gd` | Close-up of the reef tank, framed left of centre to leave room for its panel; first visit plays `interactions.inspect_tank()` | signal `clicked` |
| `tank/tank_panel.gd` | The tank close-up's panel (`main.tank_panel`): live readings with safe bands, and item slots that take anything | `readings`, `live_value(i)`, `contents`, `click(p, held)`, `slot_rect(i)`, signal `changed` |
| `tank/tank_water.gd` | What the cabin does to the tank's readings: an open window in hot weather warms it; a jug of CLEAN WATER in a tank slot is a water change (pH and oxygen part way to safe) and sends the jug back | `update(delta)` |
| `radio/radio_repair.gd` | The radio close-up's slots for its missing parts (`main.radio_repair`); filling them all sets `radio_fixed` | `SLOTS`, `filled`, `showing()`, `slot_rect(id)`, `click(p, held)`, signal `changed` |
| `ui/overlay.gd` | Draws all UI; gets every click first; owns the open panel | `panel`, `open_panel`, `close_panel`, `handle_click`, `over_ui` |
| `ui/inventory_bar.gd` | The slots along the bottom, the held item, items flying in, dragging | `held`, `fly`, `has_room`, `click`, `drag_released(p)` |
| `ui/dialogue_box.gd` | The bottom dialogue box: speaker portraits (you left, the other speaker right), typewriter text, voice blips, random radio chatter. Text, characters and voices are in `data/dialogue.json` | `start(id)`, `speaking()`, `skip_or_advance`, `close`, `is_active` |
| `ui/portraits.gd` | Placeholder pixel-map portraits (idle / talking / blinking / dimmed), or a character's PNG strip | `build(id, image_path, palette)` |
| `ui/pixel_draw.gd` | Drawing helpers: pixel text, frames, rings, palette colours | static functions, `W`, `H`, `INK`, `WHITE` |
| `ui/microfiche/microfiche_panel.gd` | The map panel: layout, mouse, marks, station cards | `update`, `press`, `release`, `wheel`, `draw` |
| `ui/microfiche/microfiche_map.gd` | The map sheets, zoom levels and lat/lon maths (no drawing) | `zoom_by`, `center_on`, `sheet_latlon`, `area_at_latlon` |
| `dev/debug_menu.gd` | The F9 menu | `commands()`, `ENABLED` |
| `dev/demo.gd` | Scripted walkthrough that saves screenshots (`--demo`) | `STEPS` |

Parts reach each other through `main`: each one gets `main` in its `setup()` and reads, for example,
`_main.shutters.is_open` or `_main.ui.inventory.held`. Only `main.gd` creates parts.

## One frame

`main.gd`'s `_process` runs the same order every frame:

1. **Clock.** `clock += delta * 24`. Time is counted in frames of a 24 fps clock (the frame rate of the
   story video the game came from), so durations like `SWING_FRAMES := 48` mean "2 seconds".
2. **Cursor.** Read the mouse in 480x270 canvas pixels (`cursor`) and note if it has gone past an edge (`beyond`).
3. **Camera** (`room_camera.update`). Pan from the cursor or keys, update each close-up view's ease, then
   place Camera and MaskCam: the room pose, a close-up pose, or a blend between them.
4. **Microfiche** (`ui.microfiche.update`), only while the map is open: drag and key panning.
5. **Shutters, cabinet.** Advance the door swings and the heat.
6. **Picker** (`picker.update`). Read the mask pixel under the cursor, unless a panel, a close-up or the UI has
   the cursor. The result is `picker.hover`, a group name or `""`.
7. **Ambience.** Storm sky, lights breathing.
8. **Post** (`post.update`). Push the clock, pan, hover id, heat and fades into the post shader.
9. **UI.** `ui.queue_redraw()`, so `overlay.gd` redraws everything on top.

## Input

All input lands in `main.gd`'s `_unhandled_input`:

- **Left click** → `main.click()`, which offers it to each layer in turn and stops at the first that takes it:
  1. `ui.handle_click(cursor)`: the F9 menu, the microfiche panel, the BACK button, the inventory slots;
  2. the active close-up view's `click(cursor, held)`, which emits its signals;
  3. holding an item: `interactions.use_item(item, picker.hover)`;
  4. otherwise: `interactions.click(picker.hover)`.
- **Right click** → close the F9 menu, else drop the held item, else `back(false)` (one step back).
- **Esc** → drop the held item, then `back(true)` (all the way back to the room). From the room, open the pause menu.
- **J / L** → open or close the cabin log.
- **Wheel, -/=** → zoom the microfiche when it's open.
- **F9** → toggle the debug menu. While it's open it takes every key.

## Object groups and the mask

An **object group** is a set of meshes that hover, outline and click as one thing ("cabinet", "jar", "radio"...).
Groups are defined in `GROUPS` in `pipeline/godot/export_glb.py`. The exporter puts each group's meshes under a
node called `grp_<name>` and writes the group list, in order, to `assets/scene_meta.json`.

At start-up:
- `object_picker.gd` numbers the groups from 1 in that order (0 means "no group");
- `room_materials.gd` gives every mesh a material with `group_id` set to its group's number.

`toon.gdshader` checks whether the camera drawing it is the mask camera (render layer 20). If so, it writes
`(group_id + 4) * 10 / 255` into red instead of lighting the surface. `object_picker.gd` reads that pixel back and
reverses the formula, and `post.gdshader` does the same to draw the outline. This encoding appears in three places,
which must agree:

| File | Constant |
|---|---|
| `shaders/toon.gdshader` | `ID_OFFSET = 4`, `ID_STEP = 10.0` |
| `shaders/post.gdshader` | `ID_OFFSET = 4`, `ID_STEP = 10.0` |
| `scripts/room/object_picker.gd` | `MASK_ID_OFFSET = 4`, `ID_STEP = 10` |

One 8-bit channel fits `(id + 4) * 10 ≤ 255`, so there's room for **21 groups**. 19 are used: 17 from the room
(the battery is the last), plus two added in code at start-up (appending to `meta.groups` before the picker
numbers them): the reef tank and its gauges (`room/fish_tank.gd`). (The step was 12, room for
17, until the tank needed more.)

A group is only hoverable if `interactions.hoverable(group)` says so: it needs a label in `LABELS`. The window's
`sky` group is the exception; it can be hovered only while the shutters are open.

## Materials and the look

Blender exports plain glTF materials. `scene_meta.json` records what each one really is, keyed by its Blender
material name: `toon` (lit flat colour, sometimes textured), `emit` (glowing), `outline` (the black inverted-hull
shell round each prop) or `sky` (the animated storm). `room_materials.gd` builds one `ShaderMaterial` per
(material, group, outlined?) combination, so per-object values are plain uniforms. The Compatibility renderer
can't do instance uniforms, which is why there are copies. Scripts that animate a material, such as the PA light
blinking, use `materials.set_param(name, param, value)`.

**Outlines in close-ups.** The hull is baked in Blender at a fixed thickness (3 mm to 1.6 cm), right for the room
view but a thick black slab once a close-up magnifies it. At load, `room_materials.gd` (`_scalable_hull`) moves
every hull vertex back onto its part and stores the push (direction in `NORMAL`, length in `UV2.x`);
`toon.gdshader` redoes the push times `outline_scale`, which `room_camera.gd` sets each frame to the close-up's
zoom (1 in the room, so the room is unchanged), never thinner than a pixel.

**Status lights.** The battery dock's `charge_led` and the radio's `radio_led` glow in the palette's two LED
colours (green, red). Those two palette entries are reserved: the mask pass writes a flag in its green channel
for these materials only (`status_light`), and the post shader only snaps flagged pixels to them, so nothing
else in the room drifts onto pure green or red.

`toon.gdshader` kinds: 0 toon, 1 emissive, 2 outline hull, 3 the window, 4 the microfiche's idle globe.

**The window.** Kind 3 shows `ui/window_view.png`, a real panorama from the cabin's summit
(`pipeline/scene/make_window_view.py`), looked into from the camera's position with the angles scaled up
(`VIEW_ZOOM` in `room_materials.gd`), so panning the room swings the view like a real window. Its sky is
transparent; the sky drawn there, the haze, the marine layer (from `window_view_depth.png`'s heights), the rain
on the glass and lightning all come from the `w_*` uniforms, which `room/weather.gd` blends between presets.

The post shader then does, in order: heat-haze warp round the screen's edges (`heat`, from `weather.heat()`: the
weather's `heat_in` with the shutters shut, up to its `heat` once they've been open a while; the middle stays clear), toon banding, colour punch and warm grade, world-locked Bayer
dither (it moves with `cam_px`, so it doesn't swim when the camera pans), hover shimmer, palette snap to the 42
colours in `assets/palette.json` (40, plus the two LED colours only for status lights), and the hover outline. The UI is drawn *after* this, so UI colours aren't snapped.
`pixel_draw.gd`'s `palette_color()` snaps them by hand.

### Two renderers

The desktop game uses Forward+; the web build (and old machines) use Compatibility. Compatibility treats colour
differently. `main.compat` is `true` on Compatibility, and it switches:
- `toon.gdshader`'s `srgb_io`: colours handed over sRGB-encoded;
- `ambience.gd`: the shadowed pendant light is scaled down (`COMPAT_SHADOW_LIGHT_SCALE`), because Compatibility adds
  shadowed lights in an extra, brighter pass.

Check any visual change in both renderers (see "Checking a change" in the README).

## Close-up views

A close-up view (crafting, radio) extends `views/close_view.gd`. It sets three things in its `setup()`: `_pose` (camera
transform), `_size` (orthographic width in metres) and `_focus` (the point it looks at). Then:
- `enter(now)` and `exit(now)` start the camera move; `t` eases 0 → 1 over `MOVE_FRAMES`.
- `room_camera.gd` asks the active view for `camera_pose(room_pose, room_size)` and uses it for both cameras.
- While a view is active, room hover is off and the
  overlay shows BACK once `settled()`.
- Clicks go to the view's `click(cursor, held)`. The views only *emit signals* (`cell_clicked`, `clicked`).
  `crafting/crafting.gd` listens to `cell_clicked` (see "Crafting" below). The radio's repair slots are UI, so
  `overlay.gd` hands them clicks before the view sees any (see "Fixing the radio" below).

`main.views` lists every view. `main.active_view()` returns the one opening or open, else one still easing out.

## Crafting

`crafting/crafting.gd` (`main.workbench`; `main.crafting` is the camera view) owns what lies on the cutting mat:
`placed`, a map of grid cell → `ItemData`. In the crafting view:
- holding an item and clicking an empty cell takes it out of the inventory and puts it on the mat;
- clicking a placed item with nothing held flies it back into the inventory;
- `result()` is the recipe whose ingredients are exactly the mat's items (cells don't matter), or `""`;
- `overlay.gd` draws the placed icons, and the result slot (`RESULT`) right of the mat: empty until `result()` names
  something, then that item's icon at 3x. Clicking it calls `craft()`, which uses up the mat, flies the result into
  the inventory and sets the flag `crafted_<id>`.

There are no recipes yet; the radio is fixed in its own close-up instead.

## Fixing the radio

Clicking the radio while it is broken opens the radio close-up. `main._on_radio_view_entered` calls
`interactions.inspect_broken_radio()` (the "inspect_radio_broken" monologue, flag `inspected_radio`), and
`radio/radio_repair.gd` (`main.radio_repair`) shows one square slot per entry in `SLOTS`: the speaker over the
`radio_speaker_hole` mesh, the battery over `psu_front_panel`. `slot_rect(id)` projects that mesh's centre with
`radio_view.screen_point()`, so the slots follow the rig if it moves. `overlay.gd` draws them and sends clicks on them
to `radio_repair.click(p, held)`:
- the matching item goes in and leaves the inventory; anything else goes back to its slot;
- a filled slot clicked with nothing held flies its part back into the inventory;
- once every slot is filled, `radio_fixed` is set. `main._check_dialogue_triggers()` then swaps in the repaired
  meshes (`start_hidden` grill on, the bare wires off), arms radio chatter and plays "radio_repaired".
  After that, a click answers a waiting call (a red ! above the radio) or opens the cabin log. J and L open
  the log too. Every monologue and call is stored there when its box closes (`GameState.cabin_log`). The !
  also marks the broken radio once the story has pointed at it; the battery and speaker stay unmarked. The !
  is a red sign with a point, drawn right above the top of the radio's case (`picker.screen_top()`, which
  leaves out the coax and cords hanging off it).

## The reef tank

The tank and its gauge board are `scenes/fish_tank.tscn`, and the widened left end of the cabin (stone wall, floor, ceiling) is `scenes/room_left.tscn`. Both are instanced under the room in `scenes/main.tscn`, and the left wall and its stones are shifted there too, so the editor matches the game. `room/fish_tank.gd` registers the tank's groups and materials and animates it (see its header). `scripts/dev/export_fish_tank.gd` rebuilds the tank scene from those builders. Clicking
either opens `views/tank_view.gd`; the first time it settles, `interactions.inspect_tank()` plays "inspect_tank"
then "inspect_tank_gauges" (both `once_flag`). While it's settled, `tank/tank_panel.gd` is up: `overlay.gd` draws its
`readings` (each a value with a bar range and a safe band, wobbling slightly via `live_value(i)`) and its `SLOTS`
item slots, and sends it clicks first. The slots take any item; nothing reads `contents` yet. To make items affect
the tank, connect to `tank_panel.changed` and change a reading's `value`. `tank/tank_water.gd` already does: the
shutters open while it's hotter outside than the water (`weather.temperature()`) warm it toward the outside
temperature, and a CLEAN WATER jug put in a slot is poured in at once (pH and oxygen move `WATER_CHANGE` of the way
to their targets) and the empty jug goes back under the filter's tap. Its rates are first guesses, to be balanced
with the rest of the tank's chemistry (issue #35).

## The leak, the water filter and the day

A hole is knocked through the wall low under the window, behind the left end of the sandbag pile's second row
(`build_pixel_scene.py`'s `wall_hole`). That row's left bag (parts `loose_bag_*`) is built in the hole;
`room/leak.gd` gathers its parts under a pivot and starts it up on top of the pile, so water runs in:
`leak_stream_a_*` / `_b_*` flicker while it's open and raining, and `leak_puddle*` scale with `level`, which
fills with the rain and dries once the hole is sealed. After the waking thoughts main.gd plays "leak_noticed"
(flag `dlg_leak_seen`), and from then `interactions.leak_alert()` puts the red ! over the sandbags. Clicking them
calls `leak.plug()` (flag `hole_plugged`). Clicking the water filter then calls `water_filter.click()`: its
`intake_idle_*` parts hide, its `intake_hole_*` parts show, the bag goes back up (`leak.make_way()`) and flag
`filter_installed` is set. The filter runs while the shutters are open and `weather.rain()` is above `MIN_RAIN`,
dripping (`filter_drip`) into the jug beside it (the `jug` group; `jug_water` is scaled up from the jug's floor
with `fill`). Clicking the full jug picks it up as `items/water_jug.tres`; `return_jug()` puts it back empty.

The hanging lamp, its cord and its pull chain are the `pendant` group. `room/pendant.gd` turns the `pendant_key`
light and the bulb off, `overlay.gd` fades to black (`blackout()`) and shows the DAY card (`card()`), and
`GameState.advance_day()` moves `day` on; the top-left box (`overlay._draw_hud()`) shows the day and
`weather.temperature()`. While the night runs (`busy()`) the room takes no clicks. Not while `leak.leaking()`.

## Dragging items

Any press on an inventory slot that picks an item up remembers where it started (`inventory_bar._drag_from`). On
release, `main._unhandled_input` asks `inventory.drag_released(cursor)`: if the cursor moved more than `DRAG_PX`, it
calls `main.click()` there with the item still held. So a drag and drop is exactly a click-to-hold followed by a
click on the target, and every target (room objects, mat cells, the radio's slots, other inventory slots) works
both ways with no extra code.

## The microfiche map

The map is split in two:
- `microfiche_map.gd` is data and maths: which sheet is showing, zoom level, scroll offset, lat/lon ↔ pixel.
  The sheets are images made by `pipeline/scene/make_fiche.py`. `ui/fiche_meta.json` gives each one's projection
  (equirectangular, so x is longitude and y is latitude).
- `microfiche_panel.gd` is the panel on screen: layout, mouse and keys, and drawing.

The panel draws the **blank** sheet, then the **printed** sheet clipped to every circle in `GameState.revealed`. That
list starts with `data/stations.json`'s `revealed` (the Pacific Northwest); `GameState.contact_station(id)` adds the
station's own circle. Zoom levels are 1/4 → 1/2 → full → the 4x detail map of a revealed area
(`fiche_detail_<id>.png`, one per area id in `stations.json`).

## Data files

| File | Written by | Read by |
|---|---|---|
| `assets/shelter.glb` | `pipeline/godot/export_glb.py` | `main.tscn` (WorldVP/Room) |
| `assets/scene_meta.json` | `export_glb.py` | `main.gd`: groups, materials, `start_hidden`, camera, `points` (window, radio_front, fiche_screen...), `craft` (mat grid) |
| `assets/palette.json` | `make_ui_assets.py` | `post_process.gd`, `pixel_draw.gd` |
| `ui/*` | `make_ui_assets.py` | `overlay.gd`, the microfiche, items' icons |
| `data/stations.json` | by hand | `game_state.gd`, `make_fiche.py` |
| `items/*.tres` | by hand, in the editor | `InventoryManager.get_item(id)` |

## Conventions

- **Units.** 3D is metres. Godot is Y-up; Blender (and the pipeline) is Z-up with the front facing -Y.
  `export_glb.py` converts. Screen positions are pixels on the 480x270 canvas, before upscaling.
- **Time.** Durations are in 24 fps frames (`main.clock`), named `*_FRAMES`.
- **Text on screen.** Capitals only, from the pixel font's set: `A–Z 0–9 . , ' - : ? ! ( ) / + = %`.
- **Names are load-bearing.** The code finds meshes, groups and materials by their Blender names (`grp_cabinet`,
  `cabinet_hinge_L`, `mat_fiche_screen_*`, `pa_led`). Renaming something in the pipeline means searching for its name
  here.
- **Script headers.** Every script starts with `##` comments: what it does, what it talks to, and how to extend it.
  Keep them current when you change a script.
- **Generated files** (`assets/`, `ui/`) are never edited by hand. See [`PIPELINE.md`](PIPELINE.md).
- **`scenes/prototypes/`** holds a Control-node inventory bar from before the pixel UI. The game doesn't use it;
  it's kept for reference.
