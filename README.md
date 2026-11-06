# Ouroboros' Cabin

First-person point-and-click in a climate shelter cabin, rendered as low-res toon pixel art.
Godot 4.7. Desktop game for Windows, macOS and Linux (Ubuntu), plus a WebGL build that runs in the browser
(GitHub Pages, see "Play in the browser").

**Making art or props? Read [`ASSET_GUIDE.md`](ASSET_GUIDE.md) first.**

## Run it

Open `project.godot` in Godot 4.7.x and press F5.

- Mouse to point and click. Push the cursor against the left or right edge (or hold A/D) to look around. Taking the
  mouse right off the game window's left or right side pans at full speed.
- Click an inventory slot to hold the item, then click something in the room to use it on that.
  Right-click or Esc puts it back.
- **Esc** always goes straight back to the room: it closes the microfiche (zoomed or not) and leaves the workbench and
  radio close-ups. Right-click steps back one level (out of a zoom first).
- Click the workbench for the crafting view, which looks straight down on the cutting mat's build grid. BACK, Esc or
  right-click returns to the room. (The crafting itself isn't built yet.)
- Click the ham radio for a close-up of the rig (BACK, Esc or right-click to leave). Talking on it isn't built yet.
- Click the microfiche map on the wall (left of the bench; it idles on a turning globe) to read the world sheet. Pan by
  dragging or with WASD / arrows.
  The map starts blank except around the shelter (the Pacific Northwest); every station you reach over the radio is
  marked and printed in. Hover a mark for that station's problems. **Zoom** with the wheel, the title bar's - / + or the - / = keys:
  1/4, 1/2, full scale, then 4x, which is a printed area's detail map (more towns, every river, named peaks).
  Clicking a printed area jumps straight to its detail map; right-click leaves it.
- **F9** opens the debug menu. Press a number or click a line:
  1 contact the next station, 2 contact all stations, 3 reveal the whole map, 4 reset the map, 5 give all items,
  6 clear the inventory, 7 open/close the shutters, 8 open/close the cabinet, 9 next day, 0 close.
  `DEBUG_MENU` in `scripts/main.gd` turns it off for a release.

## Renderers

| Platform | Renderer | Setting |
|---|---|---|
| Windows | Forward+ on Vulkan | `rendering_device/driver.windows` |
| macOS | Forward+ on Metal | `rendering_device/driver.macos` |
| Linux | Forward+ on Vulkan | Godot default |
| Web | Compatibility (WebGL 2) | `renderer/rendering_method.web`; browsers only support Compatibility |
| Fallback | Compatibility (OpenGL) | Used automatically when a machine can't run Vulkan or Metal |

On Macs that can't use Metal, Godot tries Vulkan (MoltenVK) first, then OpenGL.

Compatibility treats colour differently from Forward+. The shaders and `scripts/main.gd` (`compat`)
compensate, so the web build and the fallback look the same. See "Rendering rules" in the asset guide before touching
shaders or lights.

## Layout

```
project.godot, export_presets.cfg   Godot project (repo root)
scenes/main.tscn                    the cabin: viewports, camera, lights, UI layer
scripts/main.gd                     room setup, camera pan, hover/click, interactions
scripts/close_view.gd               close-up camera views: the ease in/out of the room camera, BACK
scripts/crafting.gd                 crafting view: top-down camera onto the bench's cutting mat, build-grid maths
scripts/radio_view.gd               radio view: the ham radio's front panel (communication hooks left open)
scripts/fiche.gd                    the microfiche map: panning world sheet, reveals, zoom, station marks and notes
scripts/ui.gd                       pixel UI: labels, inventory, microfiche panel, F9 menu, BACK/cell highlight, cursor
scripts/game_state.gd               autoload: day, story flags, stations reached (contact_station)
data/stations.json                  radio stations: callsign, name, lat/lon, problems (placeholders)
InventoryManager.gd                 autoload: what the player carries (ItemData list, 5 slots)
inventory_data.gd, item_data.gd     ItemData (id, name, icon) and InventoryData resource classes
items/                              one ItemData .tres per item (jar, papers, cig, speaker, battery)
InventoryBar.tscn, SlotUI.tscn      placeholder Control-based inventory bar (not used in the game yet)
shaders/toon.gdshader               every 3D surface + the object-id mask pass
shaders/post.gdshader               toon banding, dither, 40-colour palette, outline, heat
assets/                             shelter.glb (the room) + scene_meta.json + palette.json
ui/                                 font, cursors, item icons, microfiche sheet (generated)
pipeline/                           sources and build scripts for everything above (ignored by Godot)
  props/                            procedural low-poly prop GLBs (generate_assets.py)
  scene/                            Blender scene builders, pixel UI kit, map generator
  godot/                            exporters into this Godot project
```

## Rebuilding assets

You only need this when changing props, the room layout or UI art. See `ASSET_GUIDE.md` for the full flow.

```sh
pip install -r pipeline/props/requirements.txt            # once: trimesh is pinned (4.5.3)
python3 pipeline/props/generate_assets.py                  # props -> pipeline/props/assets/*.glb
python3 pipeline/scene/fetch_geo.py                        # only to change map layers: Natural Earth -> data/world_geo.json
python3 pipeline/scene/make_fiche.py                       # microfiche map: world (blank + printed), detail maps, globe
python3 pipeline/scene/make_map.py                         # PNW wall map (story video only)
python3 pipeline/scene/make_mat.py                         # cutting mat texture + build grid
blender -b --factory-startup --python pipeline/scene/build_pixel_scene.py -- --no-render
blender -b --factory-startup pipeline/scene/climate_shelter_pixel.blend --python pipeline/scene/build_story.py
blender -b --factory-startup pipeline/scene/climate_shelter_story.blend --python pipeline/godot/export_glb.py
python3 pipeline/godot/make_ui_assets.py                   # font, cursors, icons, palette -> ui/, assets/
```

`.blend` files are build outputs and are not committed.

## Exporting

Use Project > Export, or the command line. You need the Godot 4.7.2 export templates
(Editor > Manage Export Templates).

```sh
godot --headless --path . --export-release "Windows Desktop" build/windows/OuroborosCabin.exe
godot --headless --path . --export-release "macOS" build/macos/OuroborosCabin.zip
godot --headless --path . --export-release "Linux" build/linux/OuroborosCabin.x86_64
godot --headless --path . --export-release "Web" build/web/index.html
```

- **Windows:** one `.exe` with the game data embedded.
- **macOS:** a zipped universal `.app` (Intel and Apple Silicon), ad-hoc signed and **not notarized**.
  macOS warns that "Apple cannot check it for malicious software". To open it the first time, run
  `xattr -cr "Ouroboros' Cabin.app"` in Terminal, or click Open Anyway in System Settings > Privacy & Security.
  Control-click > Open also works on macOS 14 and earlier, but not on 15.
  `application/bundle_identifier` in `export_presets.cfg` is a placeholder.
- **Linux:** one x86_64 executable with the game data embedded, built for Ubuntu (any distro from the last
  few years works). Run it with `chmod +x OuroborosCabin.x86_64 && ./OuroborosCabin.x86_64`. It needs Vulkan
  drivers (Mesa, or NVIDIA's own driver). On Wayland desktops such as Ubuntu's it runs through XWayland.

- **Web:** `build/web/` (~40 MB, WebGL 2, single-threaded, so no special server headers are needed). Serve it over
  http, for example `python3 -m http.server` in `build/web`; opening `index.html` as a file won't work. Zipped, it's
  an HTML5 upload for itch.io.

### CI builds

`.github/workflows/build.yml` runs on every push to any branch. It exports all four platforms with Godot
4.7.2, and you can download them from the run's page under **Artifacts**
(`OuroborosCabin-windows`, `-macos`, `-linux-x86_64`, `-web`). Pushing a tag such as `v0.1` also attaches them to a
GitHub release. When the team moves to a new Godot version, change `GODOT_VERSION` in the workflow.

### Play in the browser (GitHub Pages)

The workflow can put the web build on **https://wwidjaja0.github.io/syn-100-fa26-team-3/**.
- Pushes to `main` deploy automatically.
- To put **any branch** online, go to Actions > Build > **Run workflow**, pick the branch, and leave "Deploy the web build
  to GitHub Pages" ticked. From a terminal: `gh workflow run build.yml --ref <branch>`. The site always shows the last
  build deployed.

One-time setup by a repo admin: Settings > Pages > Source: **GitHub Actions**. Then, under Settings > Environments >
`github-pages` > Deployment branches, allow the branches you want to deploy from. By default only `main` may deploy.

## Dev screenshots

`scripts/main.gd` has a scripted walkthrough that saves 480x270 screenshots:

```sh
godot --path . -- --demo screens            # walkthrough
godot --path . -- --demo screens --raw      # unprocessed lit frame + object-id mask
godot --path . --rendering-driver opengl3 -- --demo screens   # same through Compatibility (the OpenGL fallback)
```

## Temporary developer notes

In the FileSystem, you can (right-click) `items/` -> Create New -> Resource -> (double-click) ItemData and make
items like `items/battery.tres` or `items/speaker.tres`. Set `id` to the file name.
