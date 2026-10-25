import bpy, json, os
SRC = r"F:/zombiecoreframeworkfivem/wasteland/resources/[wasteland]/wasteland_buildprops/stream/"
names = []
for kind in ['foundation','wall','doorway','windowframe','halfwall','ceiling','frame','stairs','ramp','hatch']:
    for t in ['wood','stone','metal']: names.append(f'wl_bp_{kind}_{t}')
names += ['wl_bp_door_wood','wl_bp_door_metal','wl_bp_garage_wood','wl_bp_gate_frame','wl_bp_gate_door','wl_bp_windowbar_wood','wl_bp_windowbar_metal','wl_bp_toolcupboard']
out = {}
for n in names:
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    bpy.ops.sollumz.import_assets(directory=SRC, files=[{"name": n + ".ydr"}])
    info = {'bounds': [], 'model': None}
    for o in bpy.data.objects:
        if o.sollum_type == 'sollumz_drawable_model':
            bb = [o.matrix_world @ __import__('mathutils').Vector(c) for c in o.bound_box]
            mn = [round(min(v[i] for v in bb), 3) for i in range(3)]; mx = [round(max(v[i] for v in bb), 3) for i in range(3)]
            info['model'] = {'min': mn, 'max': mx, 'tris': sum(len(p.vertices) - 2 for p in o.data.polygons)}
        elif o.sollum_type.startswith('sollumz_bound') and o.type == 'MESH':
            bb = [o.matrix_world @ __import__('mathutils').Vector(c) for c in o.bound_box]
            mn = [round(min(v[i] for v in bb), 3) for i in range(3)]; mx = [round(max(v[i] for v in bb), 3) for i in range(3)]
            info['bounds'].append({'type': o.sollum_type, 'min': mn, 'max': mx, 'rot': [round(r, 3) for r in o.matrix_world.to_euler()]})
    out[n] = info
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pieces.json'), 'w'), indent=1)
print('PROBED', len(out))
