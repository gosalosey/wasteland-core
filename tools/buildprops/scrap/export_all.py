# Each built piece (out/pieces/<name>.blend) goes into the structure of the
# original wasteland_buildprops model (its collision is kept), with its own
# embedded texture, and is exported as a native gen8 .ydr to out/export/.
import bpy, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, 'out', 'pieces')
OUT = os.path.join(HERE, 'out', 'export'); os.makedirs(OUT, exist_ok=True)
SRC = r"F:/zombiecoreframeworkfivem/wasteland/resources/[wasteland]/wasteland_buildprops/stream/"
sm = sys.modules[[k for k in sys.modules if k.endswith('sollumz.ydr.shader_materials')][0]]
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
names = argv or sorted(f[:-6] for f in os.listdir(P) if f.endswith('.blend'))
ok = 0
for name in names:
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials): bpy.data.materials.remove(m)
    for i in list(bpy.data.images): bpy.data.images.remove(i)
    bpy.ops.sollumz.import_assets(directory=SRC, files=[{"name": name + ".ydr"}])
    with bpy.data.libraries.load(os.path.join(P, name + '.blend')) as (src, dst):
        dst.objects = ['piece_hi']
    hi = dst.objects[0]
    model = bpy.data.objects[name + '.model']
    me = hi.data.copy(); me.name = name + '_mesh'
    me.uv_layers[0].name = 'UVMap 0'
    ca = me.color_attributes.new('Color 1', 'BYTE_COLOR', 'CORNER')
    for d in ca.data: d.color_srgb = (1, 1, 1, 1)
    me.materials.clear()
    short = name.replace('wl_bp_', 'wlbps_')
    mat = sm.create_shader('default.sps'); mat.name = short
    tex = bpy.data.images.load(os.path.join(P, name + '_d.dds')); tex.name = short + '_d'
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.name == 'DiffuseSampler':
            n.image = tex; n.texture_properties.embedded = True
    me.materials.append(mat)
    old = model.data
    model.data = me
    bpy.data.objects.remove(hi)
    root = bpy.data.objects[name]
    for x in bpy.context.selected_objects: x.select_set(False)
    for o in [root] + list(root.children_recursive): o.select_set(True)
    bpy.context.view_layer.objects.active = root
    r = bpy.ops.sollumz.export_assets(directory=OUT, direct_export=True, use_custom_settings=True,
                                      target_formats={'NATIVE'}, target_versions={'GEN8'}, limit_to_selected=True)
    f = os.path.join(OUT, name + '.ydr')
    print('EXPORTED', name, r, os.path.getsize(f) if os.path.exists(f) else 'MISSING', flush=True)
    ok += os.path.exists(f)
print('EXPORT DONE', ok, len(names))
