"""Turn climate_shelter_pixel.blend into climate_shelter_story.blend: the room plus the story's props.

blender -b --factory-startup climate_shelter_pixel.blend --python build_story.py [-- --render | --stills 1,300]

This began as the builder for the story video (a two-day run-through without a narrator: wake, the
PA speaker, open the shutters as heat floods in, the map, the mushrooms and papers, crafting, sleep;
day 2's storm, tearing the speaker down to fix the radio, tuning the pirate stations). The game
reuses its scene: pipeline/godot/export_glb.py reads the saved climate_shelter_story.blend at frame 1
and exports assets/shelter.glb from it.

The work is split into parts in story_parts/, run here in order in one shared namespace (each
part uses names the earlier ones defined, like one long script):

  story_1_setup.py              constants, the story clock, freeze the toggles, extend the room  [game]
  story_2_props.py              PA speaker, wall map, jar, papers, cutting mat, broken radio     [game]
  story_3_rigs_and_camera.py    shutter + cabinet hinge rigs, the video camera                   [game]
  story_4_animation.py          everything that moves in the video; sets frame 1's state          [game]
  story_5_render_setup.py       render settings and object-mask passes                     [video only]
  story_6_timeline_and_save.py  saves the .blend; video cursor path, timeline, rendering   [video only]

The video's cursor/UI/dither compositor (post_story.py) is not part of this repo; in the game,
Godot does all of that live.
"""
from pathlib import Path

PARTS = Path(__file__).resolve().parent / 'story_parts'
STEPS = ['story_1_setup.py', 'story_2_props.py', 'story_3_rigs_and_camera.py', 'story_4_animation.py',
         'story_5_render_setup.py', 'story_6_timeline_and_save.py']

namespace = {'__name__': '__main__', '__file__': __file__}
for step in STEPS:
    path = PARTS / step
    print('build_story:', step)
    exec(compile(path.read_text(), str(path), 'exec'), namespace)
