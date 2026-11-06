# Props

The room's furniture and equipment as procedural low-poly models. Each prop is a Python function that assembles
named, flat-coloured parts, and each is exported as its own GLB. `pipeline/scene/build_pixel_scene.py` imports the
GLBs and places them in the room. See [`../../docs/PIPELINE.md`](../../docs/PIPELINE.md) for where this step sits.

```sh
pip install -r pipeline/props/requirements.txt    # once: trimesh 4.5.3 (pinned), numpy, Pillow
python3 pipeline/props/generate_assets.py         # rewrites assets/*.glb and asset_manifest.json
```

trimesh is pinned because newer versions export without the single `world` root node that
`build_pixel_scene.import_asset` relies on.

## Files

| File | What it is |
|---|---|
| `model.py` | `Model`: collects parts (`box`, `cyl`, `cone`, `sphere`, `rod`, `ring`, `frame`) and exports a GLB. `PAL`: the prop palette, by name |
| `generate_assets.py` | one function per prop, plus `BUILDERS`, the list of (file name, function) pairs to export |
| `assets/NN_name.glb` | the output, one per prop |
| `asset_manifest.json` | the output: each prop's parts and bounding box |
| `asset_preview_sheet.png` | an old contact sheet of the props (not regenerated) |

## The props

| GLB | Object | Size |
|---|---|---|
| `01_wooden_workbench` | planked workshop table, drawer, small vice | 2.1 m wide |
| `02_emergency_weather_radio` | the ham radio: grill, display, knobs, handle, antenna | 0.6 m wide |
| `03_supply_cabinet_closed` | two-door upright cabinet | 2.0 m high |
| `04_portable_power_station` | battery, socket panel, display, handle | 0.8 m high |
| `05_storm_shutters_closed` | two bolted wood panels over the window | 3.0 m across |
| `06_sandbag_flood_barrier` | stacked burlap bags | 2.5 m across |
| `07_gravity_water_filter` | frame, paired tanks, spigot, bucket | 1.5 m high |
| `08_wall_weather_instruments` | two gauges and a thermometer on a board | 1.9 m mounting height |
| `09_supply_crates` | three crates, one open with food tins | 1.5 m across |
| `10_emergency_lantern` | caged lantern: glass, flame, handle | 0.8 m high |
| `11_flashlight` | flashlight with lens | 0.7 m long |
| `12_supply_cabinet_open` | the cabinet open, with supplies inside | 2.0 m high |
| `13_storm_shutters_stowed` | the shutters parked to the sides | 5.4 m across |
| `14_microfiche_reader` | the wall-mounted map display in a wooden frame, control strip below | map-sized |

The open/closed pairs (`03`/`12`, `05`/`13`) give the Blender scene both states. In the game, the shutters and
cabinet doors swing on hinges instead (see `pipeline/scene/story_parts/story_3_rigs_and_camera.py`).

## Conventions

- GLB / glTF 2.0, metres, **Z up, front facing -Y**. Props stand on z = 0; wall-mounted ones sit at real heights.
- Every part is a separately **named** mesh (`door_pull`, `speaker_grill_bar`) with one flat colour from `PAL`; its
  material is called `mat_<part>_<n>`. The scene builders and the game find parts and materials by these names.
  Names containing `flame`, `lcd`, `display`, `lens`, `screen` or `pendant_bulb` glow.
- Low-poly: boxes, 8–16-sided cylinders, cones. One screen pixel is about 1.4 cm, so details under ~4 cm won't
  show.

The full rules (sizes, colours, outlines) are in [`../../ASSET_GUIDE.md`](../../ASSET_GUIDE.md). To add a prop,
follow "Add a prop to the room" in [`../../docs/HOW_TO.md`](../../docs/HOW_TO.md).
