import bpy, os, json
from mathutils import Vector
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out', 'export') + os.sep
PIECES = json.load(open(os.path.join(HERE, 'pieces.json')))
bad = 0
for name, info in PIECES.items():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    bpy.ops.sollumz.import_assets(directory=OUT, files=[{"name": name + ".ydr"}])
    bounds = []
    tex_ok = False; tris = 0
    for o in bpy.data.objects:
        if o.sollum_type.startswith('sollumz_bound') and o.type == 'MESH':
            bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
            bounds.append(([round(min(v[i] for v in bb), 2) for i in range(3)], [round(max(v[i] for v in bb), 2) for i in range(3)]))
        if o.sollum_type == 'sollumz_drawable_model':
            tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
            for n in o.data.materials[0].node_tree.nodes:
                if n.name == 'DiffuseSampler' and n.image and n.texture_properties.embedded and n.image.size[0] == 1024: tex_ok = True
    want = sorted(([round(v, 2) for v in b['min']], [round(v, 2) for v in b['max']]) for b in info['bounds'])
    same = sorted(bounds) == want
    if not (same and tex_ok): bad += 1
    print('CHECK', name, 'collision ok' if same else 'COLLISION DIFFERS', 'tex ok' if tex_ok else 'TEX MISSING', tris)
print('VERIFY BAD', bad)
