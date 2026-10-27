# Puts a built weapon mesh into the game's original weapon model (its bones
# and collision are kept, so it sits in the hand like the original) with its
# own embedded texture, and exports a native gen8 .ydr.
#   blender -b --python export_weapon.py -- <original.ydr> <built folder> <piece> <new model name>
# e.g. -- .../w_me_bat.ydr out/bat spiked_bat wl_w_me_spikedbat
# Needs <built folder>/<piece>.blend (object "piece_hi") and <piece>_d.dds.
import bpy, os, sys
argv = sys.argv[sys.argv.index('--') + 1:]
ORIG, BUILT, PIECE, NAME = argv
sm = sys.modules[[k for k in sys.modules if k.endswith('sollumz.ydr.shader_materials')][0]]

for o in list(bpy.data.objects): bpy.data.objects.remove(o)
src_dir, src_file = os.path.split(ORIG)
old_name = src_file[:-4]
bpy.ops.sollumz.import_assets(directory=src_dir, files=[{"name": src_file}])
root = bpy.data.objects[old_name]
root.name = NAME
for o in root.children_recursive:
    if o.name.startswith(old_name): o.name = NAME + o.name[len(old_name):]
model = next(o for o in root.children_recursive if o.sollum_type == 'sollumz_drawable_model')
bone = model.vertex_groups[0].name   # every vertex follows the bone the original used

with bpy.data.libraries.load(os.path.join(BUILT, PIECE + '.blend')) as (src, dst):
    dst.objects = ['piece_hi']
hi = dst.objects[0]
me = hi.data.copy(); me.name = NAME + '_mesh'
me.uv_layers[0].name = 'UVMap 0'
ca = me.color_attributes.new('Color 1', 'BYTE_COLOR', 'CORNER')
for d in ca.data: d.color_srgb = (1, 1, 1, 1)
me.materials.clear()
mat = sm.create_shader('default.sps'); mat.name = NAME
tex = bpy.data.images.load(os.path.join(BUILT, PIECE + '_d.dds')); tex.name = NAME + '_d'
for n in mat.node_tree.nodes:
    if n.type == 'TEX_IMAGE' and n.name == 'DiffuseSampler':
        n.image = tex; n.texture_properties.embedded = True
me.materials.append(mat)
model.data = me
model.vertex_groups.clear()
g = model.vertex_groups.new(name=bone)
g.add(list(range(len(me.vertices))), 1.0, 'REPLACE')

for x in bpy.context.selected_objects: x.select_set(False)
for o in [root] + list(root.children_recursive): o.select_set(True)
bpy.context.view_layer.objects.active = root
r = bpy.ops.sollumz.export_assets(directory=BUILT, direct_export=True, use_custom_settings=True,
                                  target_formats={'NATIVE'}, target_versions={'GEN8'}, limit_to_selected=True)
f = os.path.join(BUILT, NAME + '.ydr')
print('EXPORTED', NAME, r, os.path.getsize(f) if os.path.exists(f) else 'MISSING', 'bone', bone, flush=True)

# check: import what was written; same bones, one model, texture embedded
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.sollumz.import_assets(directory=BUILT, files=[{"name": NAME + ".ydr"}])
arm = bpy.data.objects[NAME]
print('VERIFY bones', [b.name for b in arm.data.bones])
for o in arm.children_recursive:
    if o.type == 'MESH':
        print('VERIFY', o.name, o.sollum_type, 'verts', len(o.data.vertices), 'dims', tuple(round(v, 3) for v in o.dimensions),
              'groups', [x.name for x in o.vertex_groups])
