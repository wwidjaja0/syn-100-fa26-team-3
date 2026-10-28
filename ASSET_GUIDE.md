# Asset guide (for people and agents making assets)

Read this before adding or changing anything the player sees. The look comes from a fixed
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
  hull, and Godot reproduces that with `PROP_DIRECT_LIGHT = 0.12` in `scripts/main.gd`. So choose prop
  colours a step lighter than you'd expect, and check them in a screenshot.
- Material names come out as `mat_<part>_<n>`. **Glowing parts are chosen by name**: a material whose name
  contains `flame`, `lcd`, `display`, `lens`, `screen`, `pendant_bulb` or `storm_window` becomes
  emissive (`EMISSIVE` in `pipeline/scene/build_pixel_scene.py`). Don't use those words in the names
  of parts that shouldn't glow.

**Textures (rare).** Only use a texture when the art can't be flat colour; the wall map is the one example.
- Make it pixel art at screen resolution: 1 texel should be at least 1 screen pixel.
- Upscale it 4x with nearest-neighbour before use, and save it as sRGB PNG (see `pipeline/scene/make_map.py`).
- The shader decodes sRGB by hand, so don't change texture hints in `toon.gdshader`.

**States.** For an object that changes (open/closed, broken/fixed), prefer **one model with hinged or
hideable parts** over two models. Examples are the shutter and cabinet hinges, or the radio grill that's
hidden until it's fixed. Hinges are empties named `<thing>_hinge_L/R` that the game rotates. Anything that starts
hidden goes in `start_hidden` (`pipeline/godot/export_glb.py`).

## 4. Making something interactable

1. **Group it.** Add an entry to `GROUPS` in `pipeline/godot/export_glb.py`. Every mesh in a group shares
   one hover outline and label. An object belongs to the first group that lists it. The limit is 17
   groups. To go past it, extend the id encoding in `toon.gdshader`, `post.gdshader` and `main.gd`
   (`ID_OFFSET` / `MASK_ID_OFFSET`) together.
2. **Label it.** Add the hover text to `LABELS` in `scripts/main.gd`. Use the pixel font's character set only:
   `A–Z 0–9 . , ' - : ? ! ( ) / + = %`, written in caps.
3. **Script it.** Add a `match hover:` branch in `click()` (`scripts/main.gd`). Item-on-object combos
   go in `use_item()`. Story progress goes in `GameState` flags and inventory.
4. **Re-export** (section 6) and check the outline in a screenshot.

The full outline and hover come from the mask pass, so a group has to be **visible to the camera**
to be clickable. Hidden or fully occluded parts are never hovered.

## 5. 2D / UI art

Everything is drawn at 1x on the 480x270 canvas by `scripts/ui.gd`.

| Asset | Source of truth | Spec |
|---|---|---|
| Font | `pipeline/scene/pixui.py` `_G` | 5x7 caps, 1 px spacing, 9 px line height |
| Item icons | `pixui.ICONS` + `ICON_COLORS` | 12x12 character grids, `K` ink outline, drawn in 20x20 slots |
| Cursors | `pixui.ARROW` / `HAND` | `X` ink, `W` fill, hotspot in `SPRITES` |
| Map panel | `pipeline/scene/make_map.py` | 200x225 panel with frame, title strip and close box |
| Item names | `ITEM_NAMES` in `pixui.py` and `scripts/ui.gd` | Keep both in sync |

Rules:
- **Use palette colours exactly.** The UI is drawn after the palette snap, so off-palette colours show
  up as-is and look wrong. Panel colours are snapped in code (`panel_col`, `panel_hi`, `panel_lo`).
- No anti-aliasing, gradients, alpha blending or soft shadows. Text outlines are a 1 px ink ring
  (`ui.text(..., shadow)`).
- After editing `pixui.py` or `make_map.py`, run `python3 pipeline/godot/make_ui_assets.py`. Never
  hand-edit the generated files in `ui/`.

## 6. Pipeline: from source to game

```
pipeline/props/generate_assets.py  --> pipeline/props/assets/NN_name.glb        (python + trimesh)
pipeline/scene/build_pixel_scene.py --> climate_shelter_pixel.blend             (Blender: room, layout, toon, lights)
pipeline/scene/build_story.py       --> climate_shelter_story.blend             (Blender: story props, hinges, groups)
pipeline/godot/export_glb.py        --> assets/shelter.glb + scene_meta.json    (Blender -> Godot)
pipeline/godot/make_ui_assets.py    --> ui/*, assets/palette.json
pipeline/godot/make_main_scene.py   --> scenes/main.tscn  (lights + camera; OVERWRITES hand edits, so rarely needed)
```

Commands are in the README. To add a new prop:
1. Write a function in `generate_assets.py`, or model it in Blender to the conventions above, and export it to
   `pipeline/props/assets/`.
2. Place it with `place(...)` in `build_pixel_scene.py` for room furniture, or build/place it in
   `build_story.py` for story props.
3. Add it to `GROUPS` if it's interactable, re-run the Blender steps and `export_glb.py`, then add the label and logic.

`shelter.glb` materials are replaced at runtime by `toon.gdshader`, keyed on the Blender material name
(`scene_meta.json` carries each one's colour and kind). Don't tune materials in Godot's import dock;
change the source and re-export.

## 7. Rendering rules (shaders and lights)

The web build runs Godot's **Compatibility** renderer, and desktop runs **Forward+**. They differ in ways
that were measured and compensated for. Keep these intact:
- `toon.gdshader` hands colours to Compatibility **sRGB-encoded** (`srgb_io`) because it linearises
  `ALBEDO`/`EMISSION` itself, and decodes textures by hand. Don't add `source_color` hints.
- **No instance uniforms.** Per-object values are separate material copies (`_toonify` in `main.gd`).
- **Only one light casts shadows** (`pendant_key`). Compatibility adds every shadowed light in sRGB in an
  extra pass, which over-brightens; its energy is scaled by `COMPAT_SHADOW_LIGHT_SCALE`. A new light should
  have shadows off.
- Light colours and material colours in the pipeline are **linear** (Blender values).
  `make_main_scene.py` converts light colours to Godot's sRGB `Color`.

## 8. Checking your work

```sh
godot --path . -- --demo screens                              # Forward+ walkthrough screenshots
godot --path . --rendering-driver opengl3 -- --demo screens   # same through Compatibility (web)
godot --path . -- --demo screens --raw                        # raw lit frame + mask.png
```

Checklist:
- [ ] The prop reads at 480x270: silhouette clear, no shimmering sub-pixel detail.
- [ ] Colours land on the palette without ugly dithering (compare with nearby props).
- [ ] Hovering it outlines **only** it, and the label is right, in **both** renderers.
- [ ] `mask.png` red values are exact multiples of 12 (ids are intact).
- [ ] The web export works: `godot --headless --path . --export-release "Web" build/web/index.html`, served over
      http (e.g. `python3 -m http.server` in `build/web`).
