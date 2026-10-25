# Puts the built wall (out/wall_wood.blend) into the structure of the current
# wl_bp_wall_wood.ydr (keeps its collision), with an embedded texture, and
# exports a native gen8 .ydr to out/export/.
import bpy, os, sys, importlib
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out', 'export')
os.makedirs(OUT, exist_ok=True)
SRC = r"F:/zombiecoreframeworkfivem/wasteland/resources/[wasteland]/wasteland_buildprops/stream/"
NAME = 'wl_bp_wall_wood'

for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.sollumz.import_assets(directory=SRC, files=[{"name": NAME + ".ydr"}])
with bpy.data.libraries.load(os.path.join(HERE, 'out', 'wall_wood.blend')) as (src, dst):
    dst.objects = ['wall_hi']
hi = dst.objects[0]

model = bpy.data.objects[NAME + '.model']
me = hi.data.copy()
me.name = NAME + '_mesh'
me.uv_layers[0].name = 'UVMap 0'
if not me.color_attributes:
    ca = me.color_attributes.new('Color 1', 'BYTE_COLOR', 'CORNER')
    for d in ca.data: d.color_srgb = (1, 1, 1, 1)
me.materials.clear()

sm = sys.modules[[k for k in sys.modules if k.endswith('sollumz.ydr.shader_materials')][0]]
mat = sm.create_shader('default.sps')
mat.name = 'wlbp_scrapwall'
tex = bpy.data.images.load(os.path.join(HERE, 'out', 'wlbp_scrapwall_d.dds'))
tex.name = 'wlbp_scrapwall_d'
for n in mat.node_tree.nodes:
    if n.type == 'TEX_IMAGE' and n.name == 'DiffuseSampler':
        n.image = tex
        n.texture_properties.embedded = True
me.materials.append(mat)
model.data = me
bpy.data.objects.remove(hi)

root = bpy.data.objects[NAME]
bpy.ops.object.select_all(action='DESELECT')
for o in [root] + list(root.children_recursive): o.select_set(True)
bpy.context.view_layer.objects.active = root
r = bpy.ops.sollumz.export_assets(directory=OUT, direct_export=True, use_custom_settings=True,
                                  target_formats={'NATIVE'}, target_versions={'GEN8'}, limit_to_selected=True)
print('EXPORT', r)
for root_dir, _, files in os.walk(OUT):
    for f in files: print('FILE', os.path.join(root_dir, f), os.path.getsize(os.path.join(root_dir, f)))
