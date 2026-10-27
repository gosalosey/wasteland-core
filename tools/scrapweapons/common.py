# Shared helpers for the scrap weapon build scripts (Blender, run with -b):
# materials made from ambientCG textures and noise, simple shapes, parts that
# follow a bone of the game weapon (vertex group), the colour x AO bake, and
# the preview / icon renders.
import bpy, bmesh, math, random, os
from mathutils import Vector, Matrix

TEX = None
parts = []
scene = bpy.context.scene


def start(tex):
    global TEX
    TEX = tex
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    parts.clear()
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'


# ----------------------------------------------------------------------------- materials
def img(name, kind='Color', colour=True):
    i = bpy.data.images.load(os.path.join(TEX, name, f'{name}_1K-JPG_{kind}.jpg'), check_existing=True)
    if not colour: i.colorspace_settings.name = 'Non-Color'
    return i


class Mat:
    def __init__(self, name):
        self.m = bpy.data.materials.new(name); self.m.use_nodes = True
        self.n = self.m.node_tree.nodes; self.l = self.m.node_tree.links
        self.b = self.n['Principled BSDF']
        self.tc = self.n.new('ShaderNodeTexCoord').outputs['Object']

    def tex(self, name, scale):
        mp = self.n.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (scale,) * 3
        mp.inputs['Location'].default_value = (random.random(), random.random(), 0)
        self.l.new(self.tc, mp.inputs['Vector'])
        t = self.n.new('ShaderNodeTexImage'); t.image = img(name); t.projection = 'BOX'; t.projection_blend = 0.3
        self.l.new(mp.outputs['Vector'], t.inputs['Vector']); return t.outputs['Color']

    def noise(self, scale, detail=6):
        z = self.n.new('ShaderNodeTexNoise'); z.inputs['Scale'].default_value = scale; z.inputs['Detail'].default_value = detail
        self.l.new(self.tc, z.inputs['Vector']); return z.outputs['Fac']

    def ramp(self, fac, a, b, pa, pb):
        r = self.n.new('ShaderNodeValToRGB')
        r.color_ramp.elements[0].position = pa; r.color_ramp.elements[0].color = a
        r.color_ramp.elements[1].position = pb; r.color_ramp.elements[1].color = b
        self.l.new(fac, r.inputs['Fac']); return r.outputs['Color']

    def mix(self, a, b, fac, mode='MIX'):
        x = self.n.new('ShaderNodeMix'); x.data_type = 'RGBA'; x.blend_type = mode
        for s, v in ((x.inputs['Factor'], fac), (x.inputs['A'], a), (x.inputs['B'], b)):
            if isinstance(v, (int, float, tuple)): s.default_value = v
            else: self.l.new(v, s)
        return x.outputs['Result']

    def above(self, fac, threshold):
        f = self.n.new('ShaderNodeMath'); f.operation = 'GREATER_THAN'; f.inputs[1].default_value = threshold
        self.l.new(fac, f.inputs[0]); return f.outputs[0]

    def grime(self, c, amount=0.55, scale=30):
        return self.mix(c, self.ramp(self.noise(scale), (amount, amount * 0.92, amount * 0.84, 1), (1, 1, 1, 1), 0.35, 0.72), 1.0, 'MULTIPLY')

    def done(self, c, rough=0.8):
        self.l.new(c, self.b.inputs['Base Color']); self.b.inputs['Roughness'].default_value = rough
        return self.m


def wood(tint=(0.78, 0.62, 0.46, 1), scale=9.0):
    m = Mat('wood'); c = m.mix(m.tex('Wood049', scale), tint, 1.0, 'MULTIPLY')
    return m.done(m.grime(c))


def galvanized(rust=0.5):
    """Old galvanised steel pipe: grey zinc with rust breaking through."""
    m = Mat('pipe')
    zinc = m.ramp(m.noise(55, 4), (0.075, 0.08, 0.08, 1), (0.2, 0.205, 0.2, 1), 0.3, 0.75)
    c = m.mix(zinc, m.tex('Rust004', 25.0), m.above(m.noise(9, 8), 0.66 - rust * 0.16))
    return m.done(m.grime(c, 0.6), 0.55)


def rusty():
    m = Mat('rust')
    c = m.mix(m.tex('Rust004', 40.0), (0.035, 0.032, 0.03, 1), m.above(m.noise(70, 4), 0.6))
    return m.done(c, 0.7)


def tape(colour=(0.33, 0.33, 0.32, 1)):
    m = Mat('tape')
    c = m.ramp(m.noise(60, 3), tuple(x * 0.45 for x in colour[:3]) + (1,), colour, 0.3, 0.75)
    return m.done(m.grime(c, 0.5, 9), 0.6)


def black_metal():
    m = Mat('blackmetal')
    c = m.ramp(m.noise(40, 6), (0.03, 0.03, 0.03, 1), (0.12, 0.11, 0.1, 1), 0.3, 0.7)
    c = m.mix(c, m.tex('Rust004', 30.0), m.above(m.noise(12, 8), 0.68))
    return m.done(c, 0.5)


# ----------------------------------------------------------------------------- shapes
def add(bm, name, mat, bone):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); scene.collection.objects.link(o)
    me.materials.append(mat)
    g = o.vertex_groups.new(name=bone); g.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
    parts.append(o); return o


def place(o, loc, direction=None, up=(0, 0, 1)):
    """Move an object made along +Z so that +Z points along `direction` from `loc`."""
    rot = Vector(direction).normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4() if direction else Matrix()
    o.matrix_world = Matrix.Translation(Vector(loc)) @ rot @ o.matrix_world
    return o


def cylinder(r, length, mat, bone, segs=16, r2=None, smooth=True, caps=True):
    """Along +Z from 0 to length."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=length)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, length / 2))
    o = add(bm, 'cyl', mat, bone)
    if smooth:
        for p in o.data.polygons:
            if abs(p.normal.z) < 0.9: p.use_smooth = True
    return o


def tube_pipe(r_out, r_in, length, mat, bone, segs=16):
    """A hollow pipe along +Z (you can see into the muzzle)."""
    bm = bmesh.new()
    outer = []; inner = []
    for z in (0.0, length):
        outer.append([bm.verts.new((r_out * math.cos(2 * math.pi * i / segs), r_out * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)])
        inner.append([bm.verts.new((r_in * math.cos(2 * math.pi * i / segs), r_in * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)])
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((outer[0][i], outer[0][j], outer[1][j], outer[1][i]))
        bm.faces.new((inner[0][j], inner[0][i], inner[1][i], inner[1][j]))
        bm.faces.new((outer[1][i], outer[1][j], inner[1][j], inner[1][i]))
        bm.faces.new((outer[0][j], outer[0][i], inner[0][i], inner[0][j]))
    o = add(bm, 'pipe', mat, bone)
    for p in o.data.polygons:
        if abs(p.normal.z) < 0.9: p.use_smooth = True
    return o


def box(size, mat, bone, bevel=0.0):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect='EDGES')
    return add(bm, 'box', mat, bone)


def ring(r, width, thick, mat, bone, segs=20):
    """A band around +Z (hose clamp, tape wrap) from 0 to width."""
    return tube_pipe(r + thick, r, width, mat, bone, segs)


def poly_tube(points, r, mat, bone):
    cu = bpy.data.curves.new('wire', 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = r; cu.bevel_resolution = 1
    sp = cu.splines.new('POLY'); sp.points.add(len(points) - 1)
    for p, v in zip(sp.points, points): p.co = (v[0], v[1], v[2], 1)
    o = bpy.data.objects.new('wire', cu); scene.collection.objects.link(o)
    for x in bpy.context.selected_objects: x.select_set(False)
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.active_object; o.data.materials.clear(); o.data.materials.append(mat)
    g = o.vertex_groups.new(name=bone); g.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
    parts.append(o); return o


# ----------------------------------------------------------------------------- bake + renders
def join_and_bake(out, piece, size=1024):
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
    col = bpy.data.images.new('bake_col', size, size); ao = bpy.data.images.new('bake_ao', size, size)

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
    col.filepath_raw = os.path.join(out, piece + '_d.png'); col.file_format = 'PNG'; col.save()
    game = bpy.data.materials.new('game'); game.use_nodes = True
    gn = game.node_tree.nodes; t = gn.new('ShaderNodeTexImage'); t.image = col
    game.node_tree.links.new(t.outputs['Color'], gn['Principled BSDF'].inputs['Base Color'])
    gn['Principled BSDF'].inputs['Roughness'].default_value = 0.7
    o.data.materials.clear(); o.data.materials.append(game)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, piece + '.blend'), copy=True)
    return o, sum(len(p.vertices) - 2 for p in o.data.polygons)


def renders(o, out, piece, views, icon_rot, icon_scale):
    """views: list of (centre, camera offset, lens). Icon: object rotated by icon_rot, seen from above."""
    scene.render.engine = 'BLENDER_EEVEE'
    w = bpy.data.worlds.new('pw'); scene.world = w; w.use_nodes = True
    bg = w.node_tree.nodes['Background']; bg.inputs['Color'].default_value = (0.2, 0.21, 0.19, 1); bg.inputs['Strength'].default_value = 1.0
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.data.energy = 3.5; sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(-30))
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam

    def shot(path, ctr, loc, lens, rx, ry, transparent=False):
        scene.render.resolution_x, scene.render.resolution_y = rx, ry
        scene.render.film_transparent = transparent
        cam.data.lens = lens; cam.location = Vector(ctr) + Vector(loc)
        cam.rotation_euler = (Vector(ctr) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = path; bpy.ops.render.render(write_still=True)
    for i, (ctr, loc, lens) in enumerate(views, 1):
        shot(os.path.join(out, '%s_view%d.png' % (piece, i)), ctr, loc, lens, 900, 600)
    o.rotation_euler = icon_rot; o.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
    mid = sum(bb, Vector()) / 8
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = icon_scale
    shot(os.path.join(out, piece + '_icon.png'), mid, (0, 0, 2.0), 50, 256, 256, transparent=True)


# ----------------------------------------------------------------------------- looks shared by the guns
# (the approved pipe shotgun's palette: dark old steel, darker rusty bands)
def old_steel():
    m = Mat('steel')
    base = m.ramp(m.noise(40, 6), (0.035, 0.028, 0.022, 1), (0.09, 0.075, 0.06, 1), 0.3, 0.75)
    rust = m.mix(m.tex('Rust004', 22.0), (0.55, 0.5, 0.45, 1), 1.0, 'MULTIPLY')
    c = m.mix(base, rust, m.above(m.noise(8, 8), 0.5))
    return m.done(m.grime(c, 0.7, 20), 0.6)


def band_steel():
    m = Mat('bands')
    c = m.mix(m.tex('Rust004', 35.0), (0.4, 0.33, 0.28, 1), 1.0, 'MULTIPLY')
    return m.done(m.grime(c, 0.6), 0.55)


def flat_xz(points, thick, mat, bone, bevel=0.0, y=0.0, segments=1):
    """A flat shape drawn in the XZ plane (x, z), thick along Y, centred on y."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y - thick / 2, z)) for x, z in points]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)], vec=(0, thick, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect='EDGES', clamp_overlap=True)
    o = add(bm, 'flat', mat, bone)
    if segments > 1:
        for p in o.data.polygons: p.use_smooth = True
    return o
