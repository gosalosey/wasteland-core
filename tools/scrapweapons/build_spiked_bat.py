# Spiked baseball bat (scrap_spiked_bat): a worn wooden bat with a duct-tape
# grip, rusty nails driven through the barrel, a few turns of wire and old
# blood. Same length and handle as the game's bat so it sits in the hand the same.
#   blender -b --python build_spiked_bat.py -- <tex folder> <out folder>
# Output: <out>/spiked_bat.blend (object "piece_hi", UV "bake"), spiked_bat_d.png,
#         previews spiked_bat_view*.png and the icon spiked_bat_icon.png
import bpy, bmesh, math, random, os, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(7)
SIZE = 1024

for o in list(bpy.data.objects): bpy.data.objects.remove(o)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'


def img(name, kind, colour=True):
    i = bpy.data.images.load(os.path.join(TEX, name, f'{name}_1K-JPG_{kind}.jpg'), check_existing=True)
    if not colour: i.colorspace_settings.name = 'Non-Color'
    return i


def material(name):
    m = bpy.data.materials.new(name); m.use_nodes = True
    return m, m.node_tree.nodes, m.node_tree.links, m.node_tree.nodes['Principled BSDF']


def boxtex(n, l, name, scale, coord):
    mp = n.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (scale,) * 3
    l.new(coord, mp.inputs['Vector'])
    t = n.new('ShaderNodeTexImage'); t.image = img(name, 'Color'); t.projection = 'BOX'; t.projection_blend = 0.3
    l.new(mp.outputs['Vector'], t.inputs['Vector']); return t.outputs['Color']


def noise(n, l, scale, coord, detail=6):
    z = n.new('ShaderNodeTexNoise'); z.inputs['Scale'].default_value = scale; z.inputs['Detail'].default_value = detail
    l.new(coord, z.inputs['Vector']); return z.outputs['Fac']


def ramp(n, l, fac, a, b, pa, pb):
    r = n.new('ShaderNodeValToRGB')
    r.color_ramp.elements[0].position = pa; r.color_ramp.elements[0].color = a
    r.color_ramp.elements[1].position = pb; r.color_ramp.elements[1].color = b
    l.new(fac, r.inputs['Fac']); return r.outputs['Color']


def mix(n, l, a, b, fac, mode='MIX'):
    x = n.new('ShaderNodeMix'); x.data_type = 'RGBA'; x.blend_type = mode
    for s, v in ((x.inputs['Factor'], fac), (x.inputs['A'], a), (x.inputs['B'], b)):
        if isinstance(v, (int, float, tuple)): s.default_value = v
        else: l.new(v, s)
    return x.outputs['Result']


def blood(n, l, col, coord, amount):
    # dark dried blood in blotches, more towards the top of the barrel
    sep = n.new('ShaderNodeSeparateXYZ'); l.new(coord, sep.inputs['Vector'])
    top = n.new('ShaderNodeMapRange'); l.new(sep.outputs['Z'], top.inputs['Value'])
    top.inputs['From Min'].default_value = 0.30; top.inputs['From Max'].default_value = 0.66
    # stains where the noise is high; the bar is lower near the top, so more there
    thr = n.new('ShaderNodeMath'); thr.operation = 'MULTIPLY_ADD'
    l.new(top.outputs['Result'], thr.inputs[0]); thr.inputs[1].default_value = -0.10 * amount; thr.inputs[2].default_value = 0.64
    f = n.new('ShaderNodeMath'); f.operation = 'GREATER_THAN'
    l.new(noise(n, l, 14, coord, 8), f.inputs[0]); l.new(thr.outputs[0], f.inputs[1])
    return mix(n, l, col, (0.09, 0.012, 0.008, 1), f.outputs[0])


def wood_mat():
    m, n, l, b = material('wood'); tc = n.new('ShaderNodeTexCoord').outputs['Object']
    c = boxtex(n, l, 'Wood049', 9.0, tc)
    c = mix(n, l, c, (0.78, 0.62, 0.46, 1), 1.0, 'MULTIPLY')
    c = mix(n, l, c, ramp(n, l, noise(n, l, 30, tc), (0.45, 0.4, 0.34, 1), (1, 1, 1, 1), 0.35, 0.7), 1.0, 'MULTIPLY')  # grime
    c = blood(n, l, c, tc, 1.0)
    l.new(c, b.inputs['Base Color']); b.inputs['Roughness'].default_value = 0.8
    return m


def tape_mat():
    m, n, l, b = material('tape'); tc = n.new('ShaderNodeTexCoord').outputs['Object']
    c = ramp(n, l, noise(n, l, 60, tc, 3), (0.13, 0.13, 0.13, 1), (0.36, 0.36, 0.35, 1), 0.3, 0.75)
    c = mix(n, l, c, ramp(n, l, noise(n, l, 9, tc), (0.5, 0.44, 0.36, 1), (1, 1, 1, 1), 0.3, 0.6), 1.0, 'MULTIPLY')
    l.new(c, b.inputs['Base Color']); b.inputs['Roughness'].default_value = 0.6
    return m


def rust_mat():
    m, n, l, b = material('rust'); tc = n.new('ShaderNodeTexCoord').outputs['Object']
    c = boxtex(n, l, 'Rust004', 40.0, tc)
    c = mix(n, l, c, (0.42, 0.40, 0.38, 1), ramp(n, l, noise(n, l, 80, tc), (0, 0, 0, 1), (1, 1, 1, 1), 0.45, 0.6), 'MIX')
    c = blood(n, l, c, tc, 0.6)
    l.new(c, b.inputs['Base Color']); b.inputs['Roughness'].default_value = 0.7
    return m


WOOD, TAPE, RUST = wood_mat(), tape_mat(), rust_mat()
parts = []


def obj_from_bm(bm, name, mat):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); scene.collection.objects.link(o)
    me.materials.append(mat); parts.append(o); return o


# ---- the bat: a lathe profile (z, radius), same length as the game's (-0.137 .. 0.670)
PROFILE = [(-0.137, 0.0), (-0.137, 0.016), (-0.133, 0.021), (-0.124, 0.022), (-0.116, 0.016), (-0.110, 0.0128),
           (0.05, 0.0130), (0.15, 0.0142), (0.25, 0.0185), (0.34, 0.0255), (0.42, 0.0315), (0.55, 0.0335),
           (0.63, 0.0333), (0.655, 0.030), (0.667, 0.022), (0.670, 0.010), (0.6705, 0.0)]


def lathe(profile, segs, name, mat, wobble=0.0):
    bm = bmesh.new(); rings = []
    for z, r in profile:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            rr = r * (1 + (random.uniform(-wobble, wobble) if r > 0.02 else 0))
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    o = obj_from_bm(bm, name, mat)
    for p in o.data.polygons: p.use_smooth = True
    return o


lathe(PROFILE, 24, 'bat', WOOD, wobble=0.015)

# ---- duct tape on the handle: slightly thicker wraps with uneven edges
tape = [(-0.104, 0.0), (-0.104, 0.0142)]
z = -0.104
while z < 0.13:
    z2 = z + random.uniform(0.018, 0.026)
    tape += [(z + 0.003, 0.0146 + random.uniform(0, 0.0007)), (z2, 0.0141)]
    z = z2
tape += [(z + 0.002, 0.0145), (z + 0.004, 0.0)]
lathe(tape, 20, 'tape', TAPE)


def radius_at(z):
    for (z0, r0), (z1, r1) in zip(PROFILE, PROFILE[1:]):
        if z0 <= z <= z1 and z1 > z0: return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return 0.033


# ---- nails driven through the barrel, pointing out at different angles
def nail(z, ang, out_len, tilt):
    r = radius_at(z)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.0021, radius2=0.0006, depth=out_len + 0.012)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, (out_len + 0.012) / 2))
    o = obj_from_bm(bm, 'nail', RUST)
    out = Vector((math.cos(ang), math.sin(ang), 0))
    d = (out + Vector((0, 0, tilt))).normalized()
    o.matrix_world = Matrix.Translation(out * (r - 0.012) + Vector((0, 0, z))) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    # the flat head where it went in on the far side, flush with the wood
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.0042, radius2=0.0042, depth=0.0015)
    h = obj_from_bm(bm, 'head', RUST)
    back = -out
    h.matrix_world = Matrix.Translation(back * (r + 0.0003) + Vector((0, 0, z))) @ back.to_track_quat('Z', 'Y').to_matrix().to_4x4()


n_nails = 0
for k in range(7):                       # rows up the barrel, staggered
    zr = 0.40 + k * 0.038
    for i in range(3):
        a = (i / 3 + (k % 2) * 0.17 + random.uniform(-0.05, 0.05)) * 2 * math.pi
        nail(zr + random.uniform(-0.008, 0.008), a, random.uniform(0.028, 0.045), random.uniform(-0.25, 0.35))
        n_nails += 1


# ---- wire wrapped around the barrel (a few loose turns) with barbs
def tube(points, r, mat):
    cu = bpy.data.curves.new('wire', 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = r; cu.bevel_resolution = 1
    sp = cu.splines.new('POLY'); sp.points.add(len(points) - 1)
    for p, v in zip(sp.points, points): p.co = (v[0], v[1], v[2], 1)
    o = bpy.data.objects.new('wire', cu); scene.collection.objects.link(o)
    for x in bpy.context.selected_objects: x.select_set(False)
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.active_object; o.data.materials.clear(); o.data.materials.append(mat); parts.append(o); return o


pts = []
for i in range(140):
    t = i / 139; a = t * 2 * math.pi * 3.2
    zz = 0.43 + t * 0.15
    rr = radius_at(zz) + 0.0018 + 0.0008 * math.sin(i * 1.7)
    pts.append((rr * math.cos(a), rr * math.sin(a), zz))
tube(pts, 0.0011, RUST)
for i in range(6, 140, 14):              # barbs: short crossed spikes on the wire
    x, y, zz = pts[i]; d = Vector((x, y, 0)).normalized()
    for s in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.0008, radius2=0.0002, depth=0.012)
        o = obj_from_bm(bm, 'barb', RUST)
        v = (d + Vector((0, 0, 0.6 * s))).normalized()
        o.matrix_world = Matrix.Translation(Vector((x, y, zz)) + v * 0.004) @ v.to_track_quat('Z', 'Y').to_matrix().to_4x4()

# ---- join, UV, bake (colour x AO), save
for x in bpy.context.selected_objects: x.select_set(False)
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
o = bpy.context.active_object; o.name = 'piece_hi'
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for uv in list(o.data.uv_layers): o.data.uv_layers.remove(uv)
o.data.uv_layers.new(name='bake')
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')
col = bpy.data.images.new('bake_col', SIZE, SIZE); ao = bpy.data.images.new('bake_ao', SIZE, SIZE)


def target(im):
    for m in o.data.materials:
        nt = m.node_tree
        t = nt.nodes.get('BAKE_T') or nt.nodes.new('ShaderNodeTexImage'); t.name = 'BAKE_T'; t.image = im
        u = nt.nodes.get('BAKE_U') or nt.nodes.new('ShaderNodeUVMap'); u.name = 'BAKE_U'; u.uv_map = 'bake'
        nt.links.new(u.outputs['UV'], t.inputs['Vector']); nt.nodes.active = t


rb = scene.render.bake
rb.use_pass_direct = False; rb.use_pass_indirect = False; rb.use_pass_color = True; rb.margin = 8
target(col); scene.cycles.samples = 4; bpy.ops.object.bake(type='DIFFUSE')
target(ao); scene.cycles.samples = 32; bpy.ops.object.bake(type='AO')
c = list(col.pixels); a = ao.pixels[:]
for i in range(0, len(c), 4):
    f = 0.45 + 0.55 * a[i]
    c[i] *= f; c[i + 1] *= f; c[i + 2] *= f; c[i + 3] = 1.0
col.pixels = c
col.filepath_raw = os.path.join(OUT, 'spiked_bat_d.png'); col.file_format = 'PNG'; col.save()
game = bpy.data.materials.new('game'); game.use_nodes = True
gn = game.node_tree.nodes; t = gn.new('ShaderNodeTexImage'); t.image = col
game.node_tree.links.new(t.outputs['Color'], gn['Principled BSDF'].inputs['Base Color'])
gn['Principled BSDF'].inputs['Roughness'].default_value = 0.75
o.data.materials.clear(); o.data.materials.append(game)
tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'spiked_bat.blend'), copy=True)

# ---- previews (concept views) and the inventory icon
scene.render.engine = 'BLENDER_EEVEE'
w = bpy.data.worlds.new('pw'); scene.world = w; w.use_nodes = True
bg = w.node_tree.nodes['Background']; bg.inputs['Color'].default_value = (0.2, 0.21, 0.19, 1); bg.inputs['Strength'].default_value = 1.0
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
sun.data.energy = 3.5; sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(-30))
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam


def shot(path, ctr, loc, lens, rx, ry, transparent=False):
    scene.render.resolution_x, scene.render.resolution_y = rx, ry
    scene.render.film_transparent = transparent
    cam.data.lens = lens; cam.location = ctr + Vector(loc)
    cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = path; bpy.ops.render.render(write_still=True)


shot(os.path.join(OUT, 'spiked_bat_view1.png'), Vector((0, 0, 0.27)), (1.25, -0.55, 0.25), 50, 900, 600)
shot(os.path.join(OUT, 'spiked_bat_view2.png'), Vector((0, 0, 0.27)), (-0.5, -0.9, 0.55), 50, 900, 600)
shot(os.path.join(OUT, 'spiked_bat_view3.png'), Vector((0, 0, 0.53)), (0.22, -0.28, 0.12), 60, 900, 600)
# icon: the whole bat lying diagonally, seen from above, transparent background
o.rotation_euler = (0, math.radians(90), math.radians(-45))
o.location = (0, 0, 0)
bpy.context.view_layer.update()
bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
mid = sum(bb, Vector()) / 8
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 0.66
shot(os.path.join(OUT, 'spiked_bat_icon.png'), mid, (0, 0, 2.0), 50, 256, 256, transparent=True)
print('BUILT spiked_bat', tris, 'tris', n_nails, 'nails', flush=True)
