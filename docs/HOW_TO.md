# How to...

Step-by-step recipes for the common changes. Each one names the files to touch, in order. For background, see
[`ARCHITECTURE.md`](ARCHITECTURE.md) (the code) and [`PIPELINE.md`](PIPELINE.md) (the assets). For the look's
rules, see [`../ASSET_GUIDE.md`](../ASSET_GUIDE.md).

- [Make an object clickable](#make-an-object-clickable)
- [Make something happen when an item is used on an object](#use-an-item-on-an-object)
- [Add an inventory item](#add-an-inventory-item)
- [Add a radio station, or a map area printed from the start](#add-a-radio-station-or-a-starting-map-area)
- [Record story progress](#record-story-progress)
- [Add a prop to the room](#add-a-prop-to-the-room)
- [Add an object that opens and closes](#add-an-object-that-opens-and-closes)
- [Add a close-up view](#add-a-close-up-view)
- [Build on the crafting or radio view](#build-on-the-crafting-or-radio-view)
- [Add a debug menu command](#add-a-debug-menu-command)
- [Add a step to the screenshot demo](#add-a-step-to-the-screenshot-demo)
- [Change the font, an icon or a cursor](#change-the-font-an-icon-or-a-cursor)

---

## Make an object clickable

Every clickable thing is an **object group**: a set of meshes that hover, outline and click together.

1. **Group it.** In `pipeline/godot/export_glb.py`, add an entry to `GROUPS`:
   ```python
   'kettle': kids('15_kettle'),          # every mesh under the imported prop
   # or: 'kettle': named('kettle_'),      # every mesh whose name starts with kettle_
   ```
   A mesh belongs to the first group that lists it. There's room for 17 groups and 16 are used. To go past that,
   see "Object groups and the mask" in [`ARCHITECTURE.md`](ARCHITECTURE.md).
2. **Re-export** the room (`export_glb.py`, see [`PIPELINE.md`](PIPELINE.md) step 5) and let Godot re-import.
3. **Label it.** In `scripts/room/interactions.gd`, add the hover text to `LABELS`:
   ```gdscript
   "kettle": "KETTLE",
   ```
   Capitals only, using the pixel font's characters: `A–Z 0–9 . , ' - : ? ! ( ) / + = %`. A group with no label
   can't be hovered.
4. **Say what a click does.** Add a branch to `click()` in the same file:
   ```gdscript
   "kettle":
       GameState.set_flag("kettle_on")
   ```
5. **Check it.** Run the game, hover the object and check that only it gets the white outline, in both renderers
   (README, "Checking a change").

## Use an item on an object

The player clicks a slot to hold an item, then clicks an object. That calls
`use_item(item, group)` in `scripts/room/interactions.gd`:

```gdscript
func use_item(item: ItemData, group: String) -> bool:
    if item.id == "battery" and group == "radio":
        InventoryManager.remove_item(item)     # used up
        GameState.set_flag("radio_powered")
        return true
    return false
```

The item goes back to its slot unless you remove it. The hover label already says `USE <ITEM> ON <OBJECT>`.

## Add an inventory item

1. **Draw the icon** in `pipeline/scene/pixui.py`: add a 12x12 character grid to `ICONS` under the item's id. Each
   letter is a colour from `ICON_COLORS`, `K` is the ink outline, and `.` is transparent.
2. **Regenerate** the UI art: `python3 pipeline/godot/make_ui_assets.py`. This writes `ui/icon_<id>.png`.
3. **Create the item.** In Godot's FileSystem dock, right-click `items/` > Create New > Resource > **ItemData**, and
   save it as `items/<id>.tres`. Set `id` to the file name, `name` to the label shown in game (capitals), and `icon`
   to `ui/icon_<id>.png`.
4. **Give it to the player**, either:
   - by picking it up from the room: `pick_up("<group>", "<id>")` in `interactions.gd`'s `click()`. This hides the
     group and flies the icon into the bar; or
   - directly: `InventoryManager.add_item(InventoryManager.get_item("<id>"))`. It returns `false` if all 5 slots are full.

`pixui.ITEM_NAMES` only feeds the old Blender video; the game takes names from the `.tres`.

## Add a radio station or a starting map area

Stations live in `data/stations.json` (the current ones are placeholders):

```json
{
  "id": "vk2_sydney",
  "callsign": "VK2SR",
  "name": "SYDNEY RELIEF",
  "lat": -33.9, "lon": 151.2,
  "problems": ["WATER RATIONED", "GRID DOWN"],
  "reveal_deg": 5
}
```

- `lat`/`lon` are in degrees, with north and east positive. `reveal_deg` is the radius printed on the map once the
  station is reached. Text uses the pixel font's characters.
- Areas printed from the start go in `revealed` (`id`, `name`, `lat`, `lon`, `radius_deg`).
- Every id gets its own zoomed detail map. After editing the file, run
  `python3 pipeline/scene/make_fiche.py` and then `python3 pipeline/godot/make_ui_assets.py`.

To reach a station from game code (the radio, once it's built), call `GameState.contact_station("vk2_sydney")`. This
marks it on the map, prints its area and emits `station_contacted`. To print any area without a station, call
`GameState.reveal(lat, lon, radius_deg)`. In-game, F9 → 1 contacts the next station, for testing.

## Record story progress

Use `GameState` (`scripts/game_state.gd`), an autoload you can reach from any script:

```gdscript
GameState.set_flag("radio_fixed")        # emits GameState.changed
if GameState.flag("radio_fixed"): ...
GameState.day += 1
```

Name flags as plain facts (`window_opened`, `took_jar`). Things the player carries go through `InventoryManager`, not
flags.

## Add a prop to the room

1. **Model it.** Either:
   - add a function to `pipeline/props/generate_assets.py` (look at the existing ones; parts come from `Model` in
     `model.py` and colours from `PAL`), and add it to `BUILDERS` at the bottom of the file; or
   - model it in Blender to the conventions in [`../ASSET_GUIDE.md`](../ASSET_GUIDE.md) (Z-up, metres, front -Y,
     named parts, flat colours) and export it as `pipeline/props/assets/NN_name.glb`.
2. **Place it.** Room furniture goes in `pipeline/scene/build_pixel_scene.py`:
   `place('15_kettle', x, y_back=WALL_Y - 0.05, on_surface='01_wooden_workbench')`. Story props are built in
   `pipeline/scene/story_parts/story_2_props.py`.
3. **Rebuild** from that step on ([`PIPELINE.md`](PIPELINE.md), "Everything, in order").
4. If it should be clickable, follow [Make an object clickable](#make-an-object-clickable).
5. Check it in a screenshot. Props render darker than their base colour, so you may need to lighten it.

## Add an object that opens and closes

Use the cabinet as the template (`scripts/room/cabinet.gd`).

1. In Blender, give the moving parts a **hinge**: an empty named `<thing>_hinge_L` / `_R` that the parts are
   parented to. The shutter and cabinet rigs are in `pipeline/scene/story_parts/story_3_rigs_and_camera.py`.
2. Copy `cabinet.gd` to `scripts/room/<thing>.gd`. It finds the hinges by name, eases an open value with
   `room/ease.gd`, and rotates the hinges each frame.
3. In `scripts/main.gd`, preload it, create it in `_ready()` like the others, and call its `update()` in `_process`.
4. In `interactions.gd`, add a `click()` branch that calls `_main.<thing>.toggle()`.
5. For parts that should start hidden and appear later, list them in `start_hidden` (`export_glb.py`).

## Add a close-up view

A close-up view swings the camera from the room into a fixed pose (the workbench and the radio work this way).

1. **Export the point to look at.** In `pipeline/godot/export_glb.py`, add a position to `points`, such as
   `'shelf_front': to_godot(...)`, and re-export. Don't hard-code coordinates in the game.
2. **Write the view.** Create `scripts/views/<name>_view.gd`:
   ```gdscript
   extends "res://scripts/views/close_view.gd"
   ## What this close-up shows and what clicking in it does.

   signal clicked(cursor: Vector2, held: ItemData)

   func setup(meta: Dictionary) -> void:
       var f: Array = meta.points.shelf_front
       _focus = Vector3(f[0], f[1], f[2])
       var b := Basis.from_euler(Vector3(-deg_to_rad(6.0), 0, 0))
       _pose = Transform3D(b, _focus + b.z * 1.2)     # 1.2 m in front, looking slightly down
       _size = 0.9                                     # metres across the screen

   func click(cursor: Vector2, held: ItemData) -> void:
       if settled():
           clicked.emit(cursor, held)
   ```
   `radio_view.gd` is a complete small example.
3. **Register it** in `scripts/main.gd`: preload it, create it in `_ready()` (`x = X.new(); _add(x, "ShelfView");
   x.setup(meta)`), and add it to `views`.
4. **Open it** from `interactions.gd`'s `click()`: `_main.shelf_view.enter(_main.clock)`.

Esc, right-click and the BACK button already close any view. The ceiling hides while a view is active. Keep the camera
path clear of the pendant lamp (see the asset guide).

## Build on the crafting or radio view

Both views stop at "the player clicked here". They emit signals, so the game logic can live in its own script:

| View | Signals |
|---|---|
| `crafting_view.gd` | `cell_hovered(cell)`, `cell_clicked(cell, held)`; `cell_world(cell)` gives a cell's 3D centre for placing a piece; the grid is 12x7 cells of 5 cm |
| `radio_view.gd` | `clicked(cursor, held)`; `screen_point(world)` maps a 3D point to the screen |

A crafting system, for example, could be a new `scripts/crafting/crafting.gd` that main.gd creates, which runs
`main.crafting.cell_clicked.connect(_on_cell_clicked)` in its `setup()`.

## Add a debug menu command

In `scripts/dev/debug_menu.gd`, add a line to `commands()`:

```gdscript
["0", "FIX THE RADIO", func(): GameState.set_flag("radio_fixed"); say("RADIO FIXED")],
```

Keys 1–9 then 0 run the lines in order, so the key shown must match the line's position. There are ten keys and all
ten are taken, so to add a command, replace one or make the "CLOSE THIS MENU" line (Esc does the same) yours. `say()` shows a feedback line for
3 seconds. Set `ENABLED := false` to remove the menu from a release.

## Add a step to the screenshot demo

`scripts/dev/demo.gd` runs `STEPS`, a timeline of `[frame, action, args...]` (24 fps frames since start). The actions
are listed in `_do()`. Some examples:

```gdscript
[1100, "hover", "kettle"], [1120, "shot", "33_hover_kettle"], [1121, "click"],
```

Keep `quit` last, with the highest frame number. To add a new action, add a branch to `_do()`.

## Change the font, an icon or a cursor

They're character grids in `pipeline/scene/pixui.py`: `_G` (the 5x7 font), `ICONS` and `ICON_COLORS`, and
`ARROW` / `HAND` with their hotspots in `SPRITES`. Edit them, then run `python3 pipeline/godot/make_ui_assets.py`.
Never edit the files in `ui/` by hand.
