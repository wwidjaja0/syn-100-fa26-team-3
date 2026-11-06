# Asset guide

Read this before adding or changing anything the player sees. (How the code works is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); the build steps are in [`docs/PIPELINE.md`](docs/PIPELINE.md).) The look comes from a fixed
pipeline, and assets that ignore its constraints either vanish, smear or break hover detection.

## 1. The look in one paragraph

Low-poly 3D props with flat colours are rendered by a locked, first-person **orthographic** camera
at **480x270**, then upscaled 4x with nearest-neighbour. Lighting is banded into toon steps, colours
are snapped to a fixed **40-colour palette** (`assets/palette.json`) through a world-locked Bayer
dither, and props carry a dark **inverted-hull outline**. Hovered objects get a thick white outline,
drawn from an object-id mask. The UI is hand-placed pixel art on the same 480x270 grid. There is
no narrator, so text on screen is only hover labels, item names and diegetic UI (map, radio).

## 2. Hard numbers

| Thing | Value | Consequence |
|---|---|---|
| Screen | 480x270 (x4 = 1920x1080) | All UI art is authored at 1x and never scaled |
| World units per pixel | 6.6 m / 480 = **1.375 cm** (ortho, same at every depth) | Details under ~4 cm (3 px) won't read |
| Outline hull | 1.6 cm | Thin parts (<3 cm) turn into outline only |
| Camera | ortho width 6.6 m, tilted 8° down, looking at the back wall | Front faces and tops show; backs never do |
| Room (Blender coords) | back wall at y = 2.0; floor z = 0; ceiling beam z ≈ 3.05; x from -5.2 to 7.2 | Props live between y ≈ -1 and 2 |
| Camera pan | x from -1.85 to 3.0, visible half-width 3.3 m | Anything outside x ≈ -5.1…6.3 is never seen |
| Palette | 40 colours, `assets/palette.json` | Off-palette colours get dithered between neighbours |
| Object groups | **max 17** (16 used) | Ids are encoded as `(id + 4) * 12` in one 8-bit channel |

## 3. 3D props

**Format.** Use GLB / glTF 2.0 in metres, **Z-up, front facing -Y** (the Blender convention used by every
prop in `pipeline/props/assets`). Props stand on z = 0. Wall-mounted props sit at real heights.

**Geometry.** Keep it low-poly and blocky: boxes, 8–16-sided cylinders, cones. Bevels and curves under
about 4 cm are wasted. Every part is a separately **named** mesh, such as `door_pull`, `speaker_grill_bar`.
Code finds parts by name, and names are kept through every step. Close the meshes and keep normals pointing out:
back faces are culled, and the outline hull relies on them.

**Materials.** Use **one flat base colour per part**, metallic 0, roughness about 0.86, and no textures.
- Pick colours from the prop palette `PAL` in `pipeline/props/generate_assets.py`: warm woods, muted steels,
  olive, canvas, cream, a few accents. The final image is snapped to `palette.json`, so stay near those
  hues. Saturated greens or purples will dither badly.
- Props render darker than their base colour. The video's props were self-shadowed by their outline
  hull, and Godot reproduces that with `PROP_DIRECT_LIGHT = 0.12` in `scripts/room/room_materials.gd`. So choose prop
  colours a step lighter than you'd expect, and check them in a screenshot.
- Material names come out as `mat_<part>_<n>`. **Glowing parts are chosen by name**: a material whose name
  contains `flame`, `lcd`, `display`, `lens`, `screen`, `pendant_bulb` or `storm_window` becomes
  emissive (`EMISSIVE` in `pipeline/scene/build_pixel_scene.py`). Don't use those words in the names
  of parts that shouldn't glow.

**Textures (rare).** Only use a texture when the art can't be flat colour. The cutting mat is the example.
- Make it pixel art at screen resolution: 1 texel should be at least 1 screen pixel.
- Upscale it 4x with nearest-neighbour before use, and save it as sRGB PNG (see `pipeline/scene/make_mat.py`).
- The shader decodes sRGB by hand, so don't change texture hints in `toon.gdshader`.
- Godot extracts textures from `shelter.glb` as `assets/shelter_<image>.png`. Set a new one's import to
  Lossless with `detect_3d/compress_to=0`, copying `shelter_mat_texture.png.import`.
- Colours are multiplied by the warm pendant light (1.0, 0.70, 0.38). A blue needs to be far bluer than it
  should look; the mat uses (24, 86, 214).

**The crafting table.** Clicking the workbench swings the camera straight down onto the blue cutting mat
(`scripts/views/crafting_view.gd`). That view is **4 px per cm** (480 px = 1.2 m), and the mat texture
(`pipeline/scene/make_mat.py`) is drawn one texel per screen pixel, so its 5 cm grid cells are exact 20 px squares,
the size of an inventory slot. The grid is 12x7 cells. To change it, edit `make_mat.py` and re-export;
Godot reads the size, centre and grid from the `craft` block in `scene_meta.json`.
- Keep the bench's middle clear: the mat sits between the ham radio and the papers, the lantern is in the back-right
  corner, and the flashlight rides on the power station.
- Nothing tall goes in front of something you need to see: the camera looks almost level, so a prop at the front
  of the bench hides whatever is behind it up to its own height. That's why the radio sits right of the vice, not
  behind it, and it stays under 30 cm because the weather-gauge board hangs above it.
- Pieces built on the mat should be about one cell (5 cm) across. Use `crafting.cell_world(cell)` to place them.
- The mat has no outline hull, so it isn't dimmed like other props.

**Close-up views.** The crafting table and the ham radio are close-ups: the camera eases from the room into
a fixed pose and back (`scripts/views/close_view.gd`). To add another one (a shelf, a gauge), extend
`close_view.gd`, set `_pose`, `_size` (ortho width in m) and `_focus` (the point it looks at) in a
`setup()`, and add it to `views` in `scripts/main.gd` (step by step in `docs/HOW_TO.md`). Export the point you look at from `export_glb.py`
(`points`), like `radio_front`, rather than hard-coding coordinates. The sloped ceiling (`ceiling_panel_*`, `ceiling_rafter_*`
from `build_pixel_scene.py`) hides while any close-up is active, because the cameras swing up through
it. Keep the pendant lamp clear of the crafting camera's path: it hangs left of the bench (`PENDANT_X`)
and the top-down camera sits above it (`CAM_HEIGHT` in `crafting_view.gd`).

**The microfiche display** hangs on the wall where the paper map used to be (`14_microfiche_reader`): a map-sized
screen in a wooden map frame, with a control strip below. Its `fiche_screen` part is the only emissive one. The
game swaps its material for a turning globe (`toon.gdshader` kind 4, drawn from `ui/globe_equirect.png` and the
screen's centre and size, which `export_glb.py` writes to `points.fiche_screen`). The paper wall map is still built
for the story video, but `export_glb.py` leaves it out of the game.

**States.** For an object that changes (open/closed, broken/fixed), prefer **one model with hinged or
hideable parts** over two models. Examples are the shutter and cabinet hinges, or the radio grill that's
hidden until it's fixed. Hinges are empties named `<thing>_hinge_L/R` that the game rotates. Anything that starts
hidden goes in `start_hidden` (`pipeline/godot/export_glb.py`).

## 4. Making something interactable

1. **Group it.** Add an entry to `GROUPS` in `pipeline/godot/export_glb.py`. Every mesh in a group shares
   one hover outline and label. An object belongs to the first group that lists it. The limit is 17
   groups. To go past it, extend the id encoding in `toon.gdshader`, `post.gdshader` and `scripts/room/object_picker.gd`
   (`ID_OFFSET` / `MASK_ID_OFFSET`, `ID_STEP`) together.
2. **Label it.** Add the hover text to `LABELS` in `scripts/room/interactions.gd`. Use the pixel font's character set only:
   `A–Z 0–9 . , ' - : ? ! ( ) / + = %`, written in caps.
3. **Script it.** Add a branch to the `match` in `click()` (`scripts/room/interactions.gd`). Item-on-object combos
   go in `use_item()`. Story progress goes in `GameState` flags; carried items go through `InventoryManager`.
4. **Re-export** (section 6) and check the outline in a screenshot.

The full outline and hover come from the mask pass, so a group has to be **visible to the camera**
to be clickable. Hidden or fully occluded parts are never hovered.

## 5. 2D / UI art

Everything is drawn at 1x on the 480x270 canvas by `scripts/ui/overlay.gd` (with helpers in
`scripts/ui/pixel_draw.gd`, the inventory bar in `scripts/ui/inventory_bar.gd` and the map in `scripts/ui/microfiche/`).

| Asset | Source of truth | Spec |
|---|---|---|
| Font | `pipeline/scene/pixui.py` `_G` | 5x7 caps, 1 px spacing, 9 px line height |
| Item icons | `pixui.ICONS` + `ICON_COLORS` | 12x12 character grids, `K` ink outline, drawn in 20x20 slots |
| Cursors | `pixui.ARROW` / `HAND` | `X` ink, `W` fill, hotspot in `SPRITES` |
| Microfiche sheet | `pipeline/scene/make_fiche.py` | Rendered at three zoom levels (`LEVELS`: 2.5, 5 and 10 px per degree; `fiche_*_0/1.png` are the zoomed-out ones, with fewer labels). Each level comes as two copies of one world map: `fiche_blank.png` (paper and faint coastlines) and `fiche_world.png` (printed: land, sea, borders, rivers, lakes, cities, the shelter). They're 10 px per degree, equirectangular 80N..62S, and `fiche_meta.json` maps lat/lon to pixels. The game shows the printed copy only inside revealed circles (`GameState.revealed`). Every area id in `data/stations.json` (the starting `revealed` list and every station) also gets `fiche_detail_<id>.png`, a 4x map at 40 px per degree with every river, towns and named peaks, shown when the player clicks that area. After editing `stations.json`, re-run `make_fiche.py` and `make_ui_assets.py`. Geography comes from Natural Earth via `fetch_geo.py` into `data/world_geo.json`. City labels are placed greedily without overlaps, and the PNW labels' sides are set by hand. |
| Radio stations | `data/stations.json` | Callsign, name, lat/lon, problems (pixel-font characters only), and `reveal_deg`, the radius the map prints around the station once it's reached. `revealed` lists the areas printed from the start (the PNW). `GameState.contact_station(id)` marks a station and reveals its area; `GameState.reveal(lat, lon, deg)` reveals any area. |
| Items | `items/<id>.tres` (`ItemData`: id, name, icon) | `name` is the in-game label; `icon` is a 12x12 PNG from `ui/`. No icon draws a `?` box |

**Adding an item:** draw its icon in `pixui.ICONS` and regenerate (below), then create `items/<id>.tres`
(FileSystem > right-click `items/` > Create New > Resource > ItemData) with `id` matching the file name.
Pick it up with `pick_up("<group>", "<id>")` in `scripts/room/interactions.gd`. `pixui.ITEM_NAMES` only feeds the Blender video.

Rules:
- **Use palette colours exactly.** The UI is drawn after the palette snap, so off-palette colours show
  up as-is and look wrong. Panel colours are snapped in code (`panel_col`, `panel_hi`, `panel_lo` in `overlay.gd`).
- No anti-aliasing, gradients, alpha blending or soft shadows. Text outlines are a 1 px ink ring
  (`pixel_draw.gd`'s `text(..., shadow)`).
- After editing `pixui.py` or `make_fiche.py`, run `python3 pipeline/godot/make_ui_assets.py`. Never
  hand-edit the generated files in `ui/`.

## 6. Pipeline: from source to game

```
pipeline/props/generate_assets.py  --> pipeline/props/assets/NN_name.glb        (python + trimesh 4.5.3, see requirements.txt)
pipeline/scene/build_pixel_scene.py --> climate_shelter_pixel.blend             (Blender: room, layout, toon, lights)
pipeline/scene/make_mat.py          --> mat_texture.png + mat_meta.json          (cutting mat art + build grid)
pipeline/scene/build_story.py       --> climate_shelter_story.blend             (Blender: story props, mat, hinges; runs story_parts/)
pipeline/godot/export_glb.py        --> assets/shelter.glb + scene_meta.json    (Blender -> Godot)
pipeline/godot/make_ui_assets.py    --> ui/*, assets/palette.json
pipeline/godot/make_main_scene.py   --> scenes/main.tscn  (lights + camera; OVERWRITES hand edits, so rarely needed)
```

Commands are in [`docs/PIPELINE.md`](docs/PIPELINE.md). To add a new prop:
1. Write a function in `generate_assets.py`, or model it in Blender to the conventions above, and export it to
   `pipeline/props/assets/`.
2. Place it with `place(...)` in `build_pixel_scene.py` for room furniture, or build/place it in
   `pipeline/scene/story_parts/story_2_props.py` for story props.
3. Add it to `GROUPS` if it's interactable, re-run the Blender steps and `export_glb.py`, then add the label and logic.

`shelter.glb` materials are replaced at runtime by `toon.gdshader`, keyed on the Blender material name
(`scene_meta.json` carries each one's colour and kind). Don't tune materials in Godot's import dock;
change the source and re-export.

## 7. Rendering rules (shaders and lights)

The desktop game runs Godot's **Forward+** renderer: Vulkan on Windows and Linux, Metal on macOS. The web build
runs **Compatibility** (WebGL 2), and so do machines that can't run Vulkan or Metal (OpenGL). The two renderers differ in ways that were measured and
compensated for. Keep these intact:
- `toon.gdshader` hands colours to Compatibility **sRGB-encoded** (`srgb_io`) because it linearises
  `ALBEDO`/`EMISSION` itself, and decodes textures by hand. Don't add `source_color` hints.
- **No instance uniforms.** Per-object values are separate material copies (`scripts/room/room_materials.gd`).
- **Only one light casts shadows** (`pendant_key`). Compatibility adds every shadowed light in sRGB in an
  extra pass, which over-brightens; its energy is scaled by `COMPAT_SHADOW_LIGHT_SCALE` (`scripts/room/ambience.gd`). A new light should
  have shadows off.
- Light colours and material colours in the pipeline are **linear** (Blender values).
  `make_main_scene.py` converts light colours to Godot's sRGB `Color`.

## 8. Checking your work

```sh
godot --path . -- --demo screens                              # Forward+ walkthrough screenshots
godot --path . --rendering-driver opengl3 -- --demo screens   # same through Compatibility (OpenGL fallback)
godot --path . -- --demo screens --raw                        # raw lit frame + mask.png
```

Checklist:
- [ ] The prop reads at 480x270: silhouette clear, no shimmering sub-pixel detail.
- [ ] Colours land on the palette without ugly dithering (compare with nearby props).
- [ ] Hovering it outlines **only** it, and the label is right, in **both** renderers.
- [ ] `mask.png` red values are exact multiples of 12 (ids are intact).
- [ ] Textures are imported **lossless** (Import dock > Compress > Mode: Lossless), never VRAM compressed.
      Compression smears pixel art and uses a different format on each platform.
- [ ] The exports still build (commands in the README, "Exporting").
