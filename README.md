# Ouroboros' Cabin

A first-person point-and-click game set in a climate shelter cabin, drawn as low-res toon pixel art.
It's made with Godot 4.7. There are desktop builds for Windows, macOS and Linux (Ubuntu), plus a WebGL build that
runs in the browser (see "Play in the browser").

## Where to start

| You want to... | Read |
|---|---|
| Play it or run it from the editor | [Quick start](#quick-start) and [Controls](#controls) below |
| Understand how the game code fits together | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Add something: an interactable object, an item, a station, a prop, a close-up view | [`docs/HOW_TO.md`](docs/HOW_TO.md) |
| Make art, props or UI graphics | [`ASSET_GUIDE.md`](ASSET_GUIDE.md) (the look's rules and hard numbers) |
| Rebuild the room, props, map or UI art from source | [`docs/PIPELINE.md`](docs/PIPELINE.md) |
| Ship a build | [Exporting](#exporting) below |

Every script starts with a comment that says what it does and how it connects to the rest. When the docs and a
script's header disagree, the script is right, and the docs need fixing.

## Quick start

1. Install **Godot 4.7.2** (the standard build; you don't need .NET).
2. Open `project.godot` in it. The first import takes a minute.
3. Press **F5**.

You don't need Blender or Python unless you change the room, the props or the generated art
(see [`docs/PIPELINE.md`](docs/PIPELINE.md)). Their outputs (`assets/`, `ui/`) are committed.

## Controls

| Input | What it does |
|---|---|
| Title screen | Start Game, Settings and How to Play. Use the mouse, or Up / Down and Enter. |
| Mouse | Point. The cursor turns into a hand over anything you can click, and a label names it. |
| Left click | Use the UI if the cursor is on it; otherwise act on the object under the cursor. |
| Cursor at the left / right edge, or A / D, ← / → | Look around (pan the room). Taking the mouse right off the window's side pans at full speed. |
| Click an inventory slot | Hold that item on the cursor. Then click something in the room to use the item on it. |
| Right click | Put the held item back. Otherwise step back one level (out of a map zoom, then out of the map or a close-up). |
| Esc | Put the held item back, then go straight back to the room. From the room, open the pause / settings menu. |
| PAUSE button (top right) | Open the pause / settings menu from any view. It also has Quit to Title (a new game; nothing is saved yet). |
| X (top right of a menu), or Esc | Close the menu: settings, pause, how to play. |
| Mouse wheel, - / =, the map's - / + buttons | Zoom the microfiche map. |
| Drag, or WASD / arrows | Pan the microfiche map while it's open. |
| F9 | The debug menu (see below). |

What's in the room so far:
- **Storm shutters:** open and close; heat floods in while they're open.
- **Supply cabinet:** opens and closes.
- **Dried mushrooms, rolling papers:** click to pick them up into the inventory.
- **Workbench:** the crafting view, looking straight down on the cutting mat's build grid. Crafting itself isn't built yet.
- **Ham radio:** a close-up of the rig. Talking on it isn't built yet.
- **Microfiche map** (on the wall, left of the bench; it idles on a turning globe): a world map that starts blank
  except around the shelter (the Pacific Northwest). Every station you reach over the radio is marked and printed in;
  hover a mark to read that station's problems. Zoom goes 1/4, 1/2, full scale, then 4x, which is a printed area's
  detail map (more towns, every river, named peaks). Clicking a printed area jumps straight to its detail map.

**Menus.** The title screen, the pause / settings menu and the how-to-play page share one look
(`scripts/ui/menu_draw.gd`). All UI sounds (menus, inventory, map, BACK) are placeholders, synthesised in `scripts/ui/ui_sounds.gd`.
Fullscreen can't switch while the game runs embedded in the editor's Game tab; turn off "Embed Game on Next Play"
there, or run an exported build.

**Debug menu (F9).** Press a number or click a line:
1 contact the next station, 2 contact all stations, 3 reveal the whole map, 4 reset the map, 5 give all items,
6 clear the inventory, 7 open/close the shutters, 8 open/close the cabinet, 9 next day, 0 close.
Set `ENABLED` in `scripts/dev/debug_menu.gd` to `false` for a release.

## Repository map

```
project.godot, export_presets.cfg   the Godot project (it lives at the repo root)
scenes/
  main.tscn                         the game's only scene: viewports, camera, lights, UI layer
  prototypes/                       an early Control-based inventory bar, not used by the game
scripts/
  main.gd                           the root node: builds the parts below, runs them each frame, routes input
  game_state.gd                     autoload GameState: day, story flags, radio stations reached, map reveals
  room/                             the 3D room: materials, hover picking, interactions, shutters, cabinet,
                                    ambience, camera, post-processing
  views/                            close-up camera views: the crafting table and the ham radio
  ui/                               the pixel UI: overlay, inventory bar, drawing helpers
    microfiche/                     the microfiche map panel and its sheets/zoom maths
  inventory/                        autoload InventoryManager and the ItemData / InventoryData resources
  dev/                              the F9 debug menu and the scripted screenshot demo
shaders/
  toon.gdshader                     every 3D surface, plus the object-id mask pass
  post.gdshader                     toon banding, dither, 40-colour palette, hover outline, heat
items/                              one ItemData .tres per item (jar, papers, cig, speaker, battery)
data/stations.json                  radio stations and the map areas printed at the start (placeholders)
assets/                             shelter.glb (the room), scene_meta.json, palette.json   [generated]
ui/                                 font, cursors, item icons, microfiche sheets            [generated]
pipeline/                           sources and build scripts for everything marked [generated]
  props/                            procedural low-poly props (Python + trimesh)
  scene/                            Blender scene builders, the pixel UI kit, map and mat generators
  godot/                            exporters from Blender/Python into this Godot project
docs/                               architecture, pipeline and how-to guides
.github/workflows/build.yml         CI: exports all platforms; deploys the web build to GitHub Pages
```

`pipeline/` has a `.gdignore`, so Godot never imports it. Don't hand-edit files marked [generated]. Change the
source in `pipeline/` and re-run it ([`docs/PIPELINE.md`](docs/PIPELINE.md)).

## Renderers

| Platform | Renderer | Setting |
|---|---|---|
| Windows | Forward+ on Vulkan | `rendering_device/driver.windows` |
| macOS | Forward+ on Metal | `rendering_device/driver.macos` |
| Linux | Forward+ on Vulkan | Godot default |
| Web | Compatibility (WebGL 2) | `renderer/rendering_method.web`; browsers only support Compatibility |
| Fallback | Compatibility (OpenGL) | Used automatically when a machine can't run Vulkan or Metal |

On Macs that can't use Metal, Godot tries Vulkan (MoltenVK) first, then OpenGL.

Compatibility handles colour differently from Forward+. The shaders compensate, switched by `compat` in
`scripts/main.gd`, so the web build and the fallback look the same as desktop. Read "Rendering rules" in
[`ASSET_GUIDE.md`](ASSET_GUIDE.md) before touching shaders or lights.

## Checking a change

The game has a scripted walkthrough (`scripts/dev/demo.gd`). It clicks through the room and saves 480x270
screenshots, so you can compare them before and after a change:

```sh
godot --path . -- --demo screens                              # walkthrough -> screens/*.png
godot --path . -- --demo screens --raw                        # one unprocessed lit frame + the object-id mask
godot --path . --rendering-driver opengl3 -- --demo screens   # the same through Compatibility (as on the web)
```

`screens/` is git-ignored.

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
- **macOS:** a zipped universal `.app` (Intel and Apple Silicon). It's ad-hoc signed and **not notarized**, so
  macOS warns that "Apple cannot check it for malicious software". To open it the first time, run
  `xattr -cr "Ouroboros' Cabin.app"` in Terminal, or click Open Anyway in System Settings > Privacy & Security.
  Control-click > Open also works on macOS 14 and earlier, but not on 15.
  `application/bundle_identifier` in `export_presets.cfg` is a placeholder.
- **Linux:** one x86_64 executable with the game data embedded, built for Ubuntu (any distro from the last
  few years works). Run it with `chmod +x OuroborosCabin.x86_64 && ./OuroborosCabin.x86_64`. It needs Vulkan
  drivers (Mesa, or NVIDIA's own driver). On Wayland desktops such as Ubuntu's, it runs through XWayland.
- **Web:** `build/web/` (~40 MB, WebGL 2, single-threaded, so the server needs no special headers). Serve it over
  http, for example with `python3 -m http.server` in `build/web`; opening `index.html` as a file won't work. Zipped,
  it's an HTML5 upload for itch.io.

### CI builds

`.github/workflows/build.yml` runs on every push to any branch. It exports all four platforms with Godot
4.7.2, and you can download them from the run's page under **Artifacts**
(`OuroborosCabin-windows`, `-macos`, `-linux-x86_64`, `-web`). Pushing a tag such as `v0.1` also attaches them to a
GitHub release. When the team moves to a new Godot version, change `GODOT_VERSION` in the workflow.

### Play in the browser (GitHub Pages)

The workflow can publish the web build to **https://wwidjaja0.github.io/syn-100-fa26-team-3/**.
- Pushes to `main` deploy automatically.
- To put **any branch** online, go to Actions > Build > **Run workflow**, pick the branch, and leave "Deploy the web
  build to GitHub Pages" ticked. From a terminal: `gh workflow run build.yml --ref <branch>`. The site always shows
  the last build deployed.

One-time setup by a repo admin: Settings > Pages > Source: **GitHub Actions**. Then, under Settings > Environments >
`github-pages` > Deployment branches, allow the branches you want to deploy from. By default only `main` may deploy.

## Troubleshooting

- **Errors about missing scripts or old paths (e.g. `res://InventoryManager.gd`) after pulling.** Godot's cache
  in `.godot/` is out of date. Close the editor, delete the `.godot/` folder and reopen the project. It's git-ignored
  and rebuilt on import.
- **The room is missing or pink.** `assets/shelter.glb` didn't import. Check the Output panel, then try
  Project > Reload Current Project.
- **Hovering highlights the wrong object.** The object-group ids are out of step. See "Object groups and the mask" in
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
- **Godot rewrote `project.godot` and stripped settings.** Opening the project in a different Godot version can do
  this. Use 4.7.2 and revert the file.
- **`generate_assets.py` output won't import into Blender.** Check you're on trimesh 4.5.3
  (`pip install -r pipeline/props/requirements.txt`).
