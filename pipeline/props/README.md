# Climate Shelter: 3D Props Pack

Thirteen ready-made low-poly GLB models for a 2D/3D mixed-media point-and-click shelter scene.

## Included assets

| GLB file | Object | Approx. physical dimensions |
|---|---|---|
| `01_wooden_workbench.glb` | Planked workshop table, functional drawer, small vise | 2.1 m wide |
| `02_emergency_weather_radio.glb` | Tabletop radio, grill, display, knobs, handle, antenna | 0.6 m wide |
| `03_supply_cabinet_closed.glb` | Two-door upright supply cabinet | 2.0 m high |
| `04_portable_power_station.glb` | Portable battery, socket panel, display, handle | 0.8 m high |
| `05_storm_shutters_closed.glb` | Two bolted wood panels, sized for a wide window | 3.0 m across |
| `06_sandbag_flood_barrier.glb` | Stacked individually modeled burlap bags | 2.5 m across |
| `07_gravity_water_filter.glb` | Frame, paired tanks, spigot, collection bucket | 1.5 m high |
| `08_wall_weather_instruments.glb` | Two mechanical gauges and a thermometer on wood | 1.9 m mounting height |
| `09_supply_crates.glb` | Three crates, one open with food tins | 1.5 m across |
| `10_emergency_lantern.glb` | Caged lantern with glass, flame, hinged handle | 0.8 m high |
| `11_flashlight.glb` | Gripped flashlight with lens | 0.7 m long |
| `12_supply_cabinet_open.glb` | Alternate opened cabinet with interior supplies | 2.0 m high |
| `13_storm_shutters_stowed.glb` | Alternate shutters parked to the sides | 5.4 m across |


## Model convention

- Files: **GLB / glTF 2.0**, including meshes, PBR materials and colors. Each construction piece is named and separately editable after import.
- Coordinates: **Z up**, front views from **negative Y**. Units: meters. 3D props stand on approximately Z=0. Wall-mounted props are positioned at realistic heights relative to Z=0.
- Style: deliberately low polygon count, warm wood / muted steel / canvas colors; diffuse cartoon-friendly surfaces rather than heavy baked lighting.
- No external textures, files, rigging, animations, or dependencies are needed for the GLBs.

## Blender

File > Import > glTF 2.0, select a `.glb`. Separate named mesh objects can be moved, recolored, and hidden. For maximum uniformity, use the **same orthographic camera, key light, world light and resolution** for every rendered sprite.

## Godot 4

- Drag a `.glb` into the Godot project to import it as a **3D scene**. All models are separate static meshes.
- To turn a model into a sprite, render the GLB in Blender and bring the resulting transparent PNG into Godot using `Sprite2D` or `TextureRect`.
- Turn **Texture Filter** to `Nearest` so enlarged pixels remain crisp. For 2D lights, consider rendering sprites with mostly flat neutral lighting and applying light effects to the 2D scene.
- For cabinet and shutters, use the provided alternate GLBs as interaction states.

## Rebuild

`generate_assets.py` builds every model (`pip install -r requirements.txt`: trimesh **4.5.3**, numpy, Pillow): `python3 generate_assets.py` rewrites `assets/*.glb`. Newer trimesh exports without the single `world` root node that the Blender importer (`build_pixel_scene.import_asset`) needs.
