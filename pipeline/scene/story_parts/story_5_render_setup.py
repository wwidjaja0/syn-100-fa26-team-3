# Part of pipeline/scene/build_story.py, which runs the parts in order in one shared
# namespace: names defined in earlier parts are used here as-is. Run build_story.py, not this.
#
# Video only: render settings and the object-mask passes (Cryptomatte, split into RGB files) that
# the video compositor used for hover outlines. The game makes its own mask live (MaskVP).

# ---------------------------------------------------------------- object masks (cryptomatte -> 3 RGB files x 6)
main_layer = scene.view_layers[0]
main_layer.use_pass_cryptomatte_object = True
if 'Mask' in scene.view_layers:
    scene.view_layers.remove(scene.view_layers['Mask'])


def kids(root_name):
    return [o.name for o in bpy.data.objects[root_name].children_recursive if o.type == 'MESH']


GROUPS = {
    'shutters': [o.name for o in sh_meshes],
    'cabinet': [o.name for o in cab_meshes if o not in jar_parts],
    'map': [o.name for o in map_parts],
    'speaker': [o.name for o in spk_parts],
    'radio': [o.name for o in radio_meshes] + [hole.name] + [w.name for w in wires],
    'jar': [o.name for o in jar_parts],
    'papers': [o.name for o in papers_parts],
    'bench': kids('01_wooden_workbench'),
    'sky': ['storm_window_emit'],
    'lantern': kids('10_emergency_lantern'),
    'instruments': kids('08_wall_weather_instruments'),
    'power': kids('04_portable_power_station'),
    'filter': kids('07_gravity_water_filter'),
    'crates': kids('09_supply_crates'),
    'sandbags': kids('06_sandbag_flood_barrier'),
    'flashlight': kids('11_flashlight'),
}
names = list(GROUPS)
MASK_FILES = [names[i:i + 3] for i in range(0, len(names), 3)]

scene.use_nodes = True
tree = scene.node_tree
tree.nodes.clear()
rl = tree.nodes.new('CompositorNodeRLayers'); rl.layer = main_layer.name
comp = tree.nodes.new('CompositorNodeComposite'); comp.location = (400, 200)
tree.links.new(rl.outputs['Image'], comp.inputs['Image'])
fo = tree.nodes.new('CompositorNodeOutputFile'); fo.location = (900, -300)
fo.base_path = str(ANIM / 'mask')
fo.format.file_format = 'PNG'
fo.format.color_mode = 'RGB'
fo.file_slots[0].path = 'm0_'
for j in range(1, len(MASK_FILES)):
    fo.file_slots.new(f'm{j}_')
for j, trio in enumerate(MASK_FILES):
    combine = tree.nodes.new('CompositorNodeCombineColor'); combine.location = (600, -300 - 300 * j)
    for i, key_name in enumerate(trio):
        cm = tree.nodes.new('CompositorNodeCryptomatteV2'); cm.location = (200, -200 - 300 * j - 100 * i)
        cm.source = 'RENDER'
        cm.scene = scene
        cm.layer_name = f'{main_layer.name}.CryptoObject'
        cm.matte_id = ','.join(GROUPS[key_name])
        tree.links.new(rl.outputs['Image'], cm.inputs['Image'])
        tree.links.new(cm.outputs['Matte'], combine.inputs[i])
    tree.links.new(combine.outputs['Image'], fo.inputs[j])

scene.frame_start, scene.frame_end = F_START, F_END
scene.render.fps = FPS
scene.eevee.taa_render_samples = 64
scene.render.filepath = str(ANIM / 'raw' / 'frame_')
scene.render.image_settings.file_format = 'PNG'
