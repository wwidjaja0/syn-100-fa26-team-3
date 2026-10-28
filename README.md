# Before the Surge

First-person point-and-click in a climate shelter cabin, rendered as low-res toon pixel art.
Godot 4.7. Hosted on itch.io as a web build.

**Making art or props? Read [`ASSET_GUIDE.md`](ASSET_GUIDE.md) first.**

## Run it

Open `project.godot` in Godot 4.7.x and press F5.

- Mouse to point and click. Push the cursor against the left or right edge (or hold A/D) to look around.
- Click an inventory slot to hold the item, then click something in the room to use it on that.
  Right-click or Esc puts it back. Esc also closes panels.

## Renderers

| Build | Renderer | Why |
|---|---|---|
| Editor and desktop | Forward+ on Vulkan | `renderer/rendering_method`, `rendering_device/driver.windows` |
| Web (itch.io) | Compatibility (WebGL 2) | Browsers only support Compatibility, set by `renderer/rendering_method.web` |

The two renderers treat colour differently. The shaders and `scripts/main.gd` (`compat`) compensate,
so both builds look the same. See "Rendering rules" in the asset guide before touching
shaders or lights.

## Layout

```
project.godot, export_presets.cfg   Godot project (repo root)
scenes/main.tscn                    the cabin: viewports, camera, lights, UI layer
scripts/main.gd                     room setup, camera pan, hover/click, interactions
scripts/ui.gd                       pixel UI: labels, inventory, map panel, cursor
scripts/game_state.gd               autoload: day, inventory, story flags
shaders/toon.gdshader               every 3D surface + the object-id mask pass
shaders/post.gdshader               toon banding, dither, 40-colour palette, outline, heat
assets/                             shelter.glb (the room) + scene_meta.json + palette.json
ui/                                 font, cursors, item icons, map panel (generated)
pipeline/                           sources and build scripts for everything above (ignored by Godot)
  props/                            procedural low-poly prop GLBs (generate_assets.py)
  scene/                            Blender scene builders, pixel UI kit, map generator
  godot/                            exporters into this Godot project
```

## Rebuilding assets

You only need this when changing props, the room layout or UI art. See `ASSET_GUIDE.md` for the full flow.

```sh
python3 pipeline/props/generate_assets.py                  # props -> pipeline/props/assets/*.glb
python3 pipeline/scene/make_map.py                         # PNW map texture + panel
blender -b --factory-startup --python pipeline/scene/build_pixel_scene.py -- --no-render
blender -b --factory-startup pipeline/scene/climate_shelter_pixel.blend --python pipeline/scene/build_story.py
blender -b --factory-startup pipeline/scene/climate_shelter_story.blend --python pipeline/godot/export_glb.py
python3 pipeline/godot/make_ui_assets.py                   # font, cursors, icons, palette -> ui/, assets/
```

`.blend` files are build outputs and are not committed.

## Exporting for itch.io

Project > Export > **Web** writes `build/web/`. Zip the contents of that folder and upload it to itch.io as an
HTML game, with "This file will be played in the browser" checked. The preset is single-threaded, so
itch's SharedArrayBuffer option isn't needed. The **Windows Desktop** preset is there for a downloadable build.

From the command line: `godot --headless --path . --export-release "Web" build/web/index.html`.

## Dev screenshots

`scripts/main.gd` has a scripted walkthrough that saves 480x270 screenshots:

```sh
godot --path . -- --demo screens            # walkthrough
godot --path . -- --demo screens --raw      # unprocessed lit frame + object-id mask
godot --path . --rendering-driver opengl3 -- --demo screens   # same through Compatibility (the web renderer)
```
