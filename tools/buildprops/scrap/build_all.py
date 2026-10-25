# Scrap barricade building props: builds every piece (or the ones named after
# "--"), bakes one 1024 texture each (colour x AO) and renders a preview.
#   blender -b --python build_all.py [-- wl_bp_wall_wood wl_bp_door_wood ...]
# Output: out/pieces/<name>.blend (object "piece_hi", one material, UV "bake"),
#         out/pieces/<name>_d.png, out/previews/<name>.png
import bpy, bmesh, math, random, os, sys, json, zlib
from mathutils import Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, 'tex')
OUTP = os.path.join(HERE, 'out', 'pieces'); os.makedirs(OUTP, exist_ok=True)
OUTV = os.path.join(HERE, 'out', 'previews'); os.makedirs(OUTV, exist_ok=True)
SRC = r"F:/zombiecoreframeworkfivem/wasteland/resources/[wasteland]/wasteland_buildprops/stream/"
PIECES = json.load(open(os.path.join(HERE, 'pieces.json')))
SIZE = 1024

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
names = argv or list(PIECES.keys())

# ----------------------------------------------------------------------------- helpers
def clear():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials): bpy.data.materials.remove(m)
    for i in list(bpy.data.images):
        if i.users == 0 or i.name.startswith('bake_') or i.name.startswith('ao_'): bpy.data.images.remove(i)

def img(name, kind, colour=True):
    p = os.path.join(TEX, name, f'{name}_1K-JPG_{kind}.jpg')
    i = bpy.data.images.load(p, check_existing=True)
    if not colour: i.colorspace_settings.name = 'Non-Color'
    return i

class M:
    """A box-projected material built from layers (object space), baked later."""
    def __init__(self, name):
        self.m = bpy.data.materials.new(name); self.m.use_nodes = True
        self.nt = self.m.node_tree; self.n = self.nt.nodes; self.l = self.nt.links
        self.bsdf = self.n['Principled BSDF']
        self.tc = self.n.new('ShaderNodeTexCoord')
        self.geo = self.n.new('ShaderNodeNewGeometry')
        self.out = None
    def tex(self, name, scale=1.0, rot=0.0, offset=(0, 0, 0)):
        mp = self.n.new('ShaderNodeMapping')
        mp.inputs['Scale'].default_value = (scale, scale, scale)
        mp.inputs['Rotation'].default_value = (0, 0, rot)
        mp.inputs['Location'].default_value = offset
        self.l.new(self.tc.outputs['Object'], mp.inputs['Vector'])
        t = self.n.new('ShaderNodeTexImage'); t.image = img(name, 'Color')
        t.projection = 'BOX'; t.projection_blend = 0.25
        self.l.new(mp.outputs['Vector'], t.inputs['Vector'])
        return t.outputs['Color']
    def mix(self, a, b, fac, mode='MIX'):
        x = self.n.new('ShaderNodeMix'); x.data_type = 'RGBA'; x.blend_type = mode
        for sock, v in ((x.inputs['Factor'], fac), (x.inputs['A'], a), (x.inputs['B'], b)):
            if isinstance(v, (int, float)): sock.default_value = v
            elif isinstance(v, tuple): sock.default_value = v
            else: self.l.new(v, sock)
        return x.outputs['Result']
    def math(self, op, a, b=None):
        nd = self.n.new('ShaderNodeMath'); nd.operation = op
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): nd.inputs[i].default_value = v
            else: self.l.new(v, nd.inputs[i])
        return nd.outputs[0]
    def noise(self, scale, detail=6, coord=None):
        nz = self.n.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = scale; nz.inputs['Detail'].default_value = detail
        self.l.new(coord or self.tc.outputs['Object'], nz.inputs['Vector'])
        return nz.outputs['Fac']
    def ramp(self, fac, a, b, pa, pb):
        r = self.n.new('ShaderNodeValToRGB')
        r.color_ramp.elements[0].position = pa; r.color_ramp.elements[0].color = a
        r.color_ramp.elements[1].position = pb; r.color_ramp.elements[1].color = b
        self.l.new(fac, r.inputs['Fac']); return r.outputs['Color']
    def xyz(self, sock):
        s = self.n.new('ShaderNodeSeparateXYZ'); self.l.new(sock, s.inputs['Vector']); return s.outputs
    def finish(self, col, grime=0.55, mud=True):
        # grime blotches, mud near the ground, then out
        g = self.ramp(self.noise(2.5, 8), (grime, grime * 0.94, grime * 0.86, 1), (1, 1, 1, 1), 0.42, 0.78)
        col = self.mix(col, g, 1.0, 'MULTIPLY')
        if mud:
            p = self.xyz(self.geo.outputs['Position'])
            h = self.math('SUBTRACT', self.math('ADD', p[2], self.math('MULTIPLY', self.noise(7), 0.6)), 0.3)
            f = self.math('MULTIPLY', self.math('SUBTRACT', 1.0, self.math('MINIMUM', self.math('MAXIMUM', h, 0.0), 1.0)), 0.75)
            col = self.mix(col, (0.08, 0.065, 0.045, 1), f)
        self.out = col
        self.l.new(col, self.bsdf.inputs['Base Color'])
        self.bsdf.inputs['Roughness'].default_value = 0.85
        return self.m
    # ---- decals (object space, on faces whose normal points along `side`)
    def decal(self, kind, cx, cz, size, side=-1, colour=(0.38, 0.02, 0.01, 1), plane='XZ'):
        p = self.xyz(self.geo.outputs['Position']); nrm = self.xyz(self.geo.outputs['Normal'])
        u = p[0] if plane in ('XZ', 'XY') else p[1]
        v = p[2] if plane in ('XZ', 'YZ') else p[1]
        du = self.math('DIVIDE', self.math('SUBTRACT', u, cx), size)
        dv = self.math('DIVIDE', self.math('SUBTRACT', v, cz), size)
        A = lambda x: self.math('ABSOLUTE', x)
        if kind == 'x':
            d = self.math('MINIMUM', A(self.math('SUBTRACT', du, dv)), A(self.math('ADD', du, dv)))
            shape = self.math('MULTIPLY', self.math('LESS_THAN', d, 0.09),
                              self.math('MULTIPLY', self.math('LESS_THAN', A(du), 0.5), self.math('LESS_THAN', A(dv), 0.55)))
        elif kind == 'tally':   # four strokes and a slash
            fr = self.math('FRACT', self.math('MULTIPLY', self.math('ADD', du, 0.5), 5.0))
            strokes = self.math('MULTIPLY', self.math('LESS_THAN', A(self.math('SUBTRACT', fr, 0.5)), 0.12),
                                self.math('LESS_THAN', A(du), 0.4))
            slash = self.math('LESS_THAN', A(self.math('SUBTRACT', dv, self.math('MULTIPLY', du, 0.9))), 0.05)
            shape = self.math('MULTIPLY', self.math('MAXIMUM', strokes, self.math('MULTIPLY', slash, self.math('LESS_THAN', A(du), 0.5))),
                              self.math('LESS_THAN', A(dv), 0.42))
        elif kind == 'circle':  # ring with a slash: "do not enter"
            r = self.math('SQRT', self.math('ADD', self.math('MULTIPLY', du, du), self.math('MULTIPLY', dv, dv)))
            ring = self.math('LESS_THAN', A(self.math('SUBTRACT', r, 0.42)), 0.06)
            slash = self.math('MULTIPLY', self.math('LESS_THAN', A(self.math('ADD', du, dv)), 0.08), self.math('LESS_THAN', r, 0.42))
            shape = self.math('MAXIMUM', ring, slash)
        elif kind == 'blood':   # smear with drips
            blob = self.math('LESS_THAN', self.math('ADD', self.math('MULTIPLY', du, du), self.math('MULTIPLY', self.math('MULTIPLY', dv, 1.8), self.math('MULTIPLY', dv, 1.8))),
                             self.math('ADD', 0.12, self.math('MULTIPLY', self.noise(6), 0.18)))
            fr = self.math('FRACT', self.math('MULTIPLY', self.math('ADD', du, 2.0), 7.0))
            drip = self.math('MULTIPLY', self.math('MULTIPLY', self.math('LESS_THAN', A(self.math('SUBTRACT', fr, 0.5)), 0.1),
                                                   self.math('LESS_THAN', A(du), 0.3)),
                             self.math('MULTIPLY', self.math('LESS_THAN', dv, 0.0), self.math('GREATER_THAN', dv, self.math('MULTIPLY', self.noise(30), -1.1))))
            shape = self.math('MAXIMUM', blob, drip)
        rag = self.math('GREATER_THAN', self.noise(45), 0.3)
        axis = nrm[1] if plane in ('XZ', 'YZ') else nrm[2]
        facing = self.math('GREATER_THAN', self.math('MULTIPLY', axis, side), 0.5)
        if plane == 'YZ': facing = self.math('GREATER_THAN', self.math('MULTIPLY', nrm[0], side), 0.5)
        f = self.math('MULTIPLY', self.math('MULTIPLY', shape, rag), facing)
        self.out = self.mix(self.out, colour, f)
        self.l.new(self.out, self.bsdf.inputs['Base Color'])

# ---- tier materials
def wood_mat(name, tint=(1, 1, 1, 1), tex='Planks012', scale=1.0):
    m = M(name); c = m.mix(m.tex(tex, scale, offset=(random.random() * 5, random.random() * 5, 0)), tint, 1.0, 'MULTIPLY')
    return m, m.finish(c)
def stud_mat(name):
    m = M(name); c = m.mix(m.tex('Wood049', 0.5), (0.55, 0.47, 0.38, 1), 1.0, 'MULTIPLY'); return m, m.finish(c)
def rust_steel(name, base='CorrugatedSteel003', tint=(0.6, 0.6, 0.57, 1), rust=0.75, scale=1.0, desat=0.0):
    m = M(name)
    t = m.tex(base, scale, offset=(random.random() * 5, 0, 0))
    if desat:  # faded paint: towards grey
        t = m.mix(t, (0.5, 0.5, 0.5, 1), desat)
    c = m.mix(t, tint, 1.0, 'MULTIPLY')
    mask = m.math('GREATER_THAN', m.math('ADD', m.noise(1.8, 10), m.math('MULTIPLY', m.noise(14), 0.25)), 1.0 - rust * 0.55 + 0.15)
    c = m.mix(c, m.mix(m.tex('Rust004', 1.5), (1.25, 1.05, 0.95, 1), 1.0, 'MULTIPLY'), mask)
    streak = m.ramp(m.noise(0.9, 4, None), (0.55, 0.45, 0.36, 1), (1, 1, 1, 1), 0.3, 0.75)   # rust run-off / dirt
    return m, m.finish(m.mix(c, streak, 1.0, 'MULTIPLY'), 0.5)
def iron_mat(name):
    m = M(name); c = m.mix(m.tex('Metal046A', 1.0), m.tex('Rust004', 2.0), m.math('GREATER_THAN', m.noise(3, 8), 0.45))
    return m, m.finish(c, 0.5)
def cinder_mat(name, scale=1.0):
    m = M(name); c = m.mix(m.tex('Bricks066', 0.75 * scale), (0.72, 0.7, 0.66, 1), 1.0, 'MULTIPLY')
    stain = m.ramp(m.noise(1.2, 6), (0.55, 0.5, 0.42, 1), (1, 1, 1, 1), 0.35, 0.7)
    return m, m.finish(m.mix(c, stain, 1.0, 'MULTIPLY'), 0.5)
def concrete_mat(name):
    m = M(name); c = m.mix(m.tex('Concrete034', 0.5), (0.62, 0.6, 0.57, 1), 1.0, 'MULTIPLY')
    cracks = m.ramp(m.noise(9, 12), (0.25, 0.24, 0.22, 1), (1, 1, 1, 1), 0.28, 0.33)
    return m, m.finish(m.mix(c, cracks, 1.0, 'MULTIPLY'), 0.45)
def plate_mat(name):
    m = M(name); c = m.mix(m.tex('DiamondPlate001', 1.0), (0.7, 0.7, 0.68, 1), 1.0, 'MULTIPLY')
    mask = m.math('GREATER_THAN', m.noise(2.2, 10), 0.52)
    return m, m.finish(m.mix(c, m.tex('Rust004', 1.5), mask), 0.55)
def painted_mat(name, tex='PaintedMetal009', tint=(0.85, 0.85, 0.8, 1)):
    m = M(name); c = m.mix(m.tex(tex, 1.0), tint, 1.0, 'MULTIPLY'); return m, m.finish(c, 0.55)

# ----------------------------------------------------------------------------- geometry
parts = []
def box(size, center, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=rot)
    o = bpy.context.active_object; o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if mat: o.data.materials.append(mat)
    parts.append(o); return o
def cyl(r, depth, center, rot=(0, 0, 0), mat=None, verts=8):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=center, rotation=rot)
    o = bpy.context.active_object
    if mat: o.data.materials.append(mat)
    parts.append(o); return o
def corrugated(w, h, center, mat, waves_per_m=7, depth=0.012, rot=(0, 0, 0), axis='Z', thick=0.003):
    """Sheet in the XZ plane (corrugation runs along `axis`), or XY plane for axis 'Y'/'X' floors."""
    bm = bmesh.new()
    n = max(4, int(w * waves_per_m) * 4)
    waves = n / 4
    rows = []
    for j in range(2):
        row = []
        for i in range(n + 1):
            x = -w / 2 + w * i / n
            y = math.sin(i / n * waves * 2 * math.pi) * depth
            row.append(bm.verts.new((x, y, -h / 2 + h * j)))
        rows.append(row)
    for i in range(n):
        bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    me = bpy.data.meshes.new('sheet'); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new('sheet', me); bpy.context.collection.objects.link(o)
    o.location = center; o.rotation_euler = rot
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects: x.select_set(False)
    o.select_set(True)
    mod = o.modifiers.new('s', 'SOLIDIFY'); mod.thickness = thick
    bpy.ops.object.modifier_apply(modifier='s')
    o.data.materials.append(mat); parts.append(o); return o

def rnd(a, b): return random.uniform(a, b)

# ---- panels: one collision box of a wall-like piece, outside = -Y
def panel_wood(b, mats, big):
    (x0, y0, z0), (x1, y1, z1) = b['min'], b['max']
    w, h = x1 - x0, z1 - z0; cx = (x0 + x1) / 2
    # posts at both ends (inside)
    for x in (x0 + 0.065, x1 - 0.065):
        if w > 0.3: box((0.12, 0.11, h - 0.01), (x, y1 - 0.06, z0 + h / 2), mat=mats['stud'])
    if h > 1.3 and w > 0.5:
        for zz in (z0 + 0.45, z1 - 0.45):
            box((w - 0.25, 0.06, 0.12), (cx, y1 - 0.035, zz), mat=mats['stud'])
    # planks outside
    z = z0 + 0.01
    while z < z1 - 0.04:
        ph = min(rnd(0.2, 0.32), z1 - z - 0.005)
        tilt = math.radians(rnd(-1.2, 1.2)) if w > 1 else 0
        length = w - rnd(0.0, 0.04)
        box((length, 0.032, ph), (cx + rnd(-0.01, 0.01), y0 + 0.022 + rnd(-0.004, 0.004), z + ph / 2), rot=(0, tilt, 0),
            mat=random.choice(mats['planks']))
        z += ph + rnd(0.008, 0.03)
    if big and w > 1.2 and h > 2:
        a = math.radians(rnd(-18, 18))
        box((w * 0.75, 0.028, 0.17), (cx + rnd(-0.2, 0.2), y0 - 0.006, rnd(z0 + 1.6, z1 - 0.5)), rot=(0, a, 0), mat=mats['planks'][2])
        if random.random() < 0.7:
            sw, sh = rnd(0.9, min(1.3, w - 0.2)), rnd(0.7, 1.1)
            corrugated(sw, sh, (cx + rnd(-(w - sw) / 2 + 0.1, (w - sw) / 2 - 0.1), y0 - 0.004, z0 + 0.15 + sh / 2), mats['rust'],
                       rot=(0, math.radians(rnd(-5, 5)), 0))

def panel_stone(b, mats, big):
    (x0, y0, z0), (x1, y1, z1) = b['min'], b['max']
    w, h = x1 - x0, z1 - z0; cx = (x0 + x1) / 2
    box((w, (y1 - y0) - 0.02, h), (cx, (y0 + y1) / 2, z0 + h / 2), mat=mats['block'])
    # concrete cap and pillars at the ends
    box((w, y1 - y0, 0.12), (cx, (y0 + y1) / 2, z1 - 0.06), mat=mats['concrete'])
    for x in (x0 + 0.1, x1 - 0.1):
        if w > 0.5: box((0.2, y1 - y0, h - 0.12), (x, (y0 + y1) / 2, z0 + (h - 0.12) / 2), mat=mats['concrete'])
    # a few blocks sticking out / patched
    for _ in range(int(w * h / 2.5)):
        bw, bh = 0.39, 0.19
        bx = rnd(x0 + 0.3, x1 - 0.3); bz = rnd(z0 + 0.2, z1 - 0.3)
        box((bw, 0.025, bh), (bx, y0 - 0.002, bz), mat=mats['block'])
    if big and w > 1.2 and h > 2 and random.random() < 0.6:
        corrugated(rnd(0.8, 1.1), rnd(0.6, 0.9), (cx + rnd(-0.4, 0.4), y0 - 0.006, z0 + rnd(0.9, 1.6)), mats['rust'],
                   rot=(0, math.radians(rnd(-8, 8)), 0))

def panel_metal(b, mats, big):
    (x0, y0, z0), (x1, y1, z1) = b['min'], b['max']
    w, h = x1 - x0, z1 - z0; cx = (x0 + x1) / 2
    # angle-iron frame inside
    for x in (x0 + 0.04, x1 - 0.04):
        box((0.08, 0.08, h), (x, y1 - 0.045, z0 + h / 2), mat=mats['iron'])
    for zz in (z0 + 0.04, z1 - 0.04) + ((z0 + h / 2,) if h > 1.4 else ()):
        box((w - 0.08, 0.08, 0.07), (cx, y1 - 0.045, zz), mat=mats['iron'])
    if w > 1.2 and h > 1.4:
        a = math.atan2(h - 0.2, w - 0.2)
        box((math.hypot(w - 0.2, h - 0.2), 0.05, 0.06), (cx, y1 - 0.03, z0 + h / 2), rot=(0, -a, 0), mat=mats['iron'])
    # corrugated sheets outside, overlapping, a bit crooked
    x = x0
    while x < x1 - 0.05:
        sw = min(rnd(0.85, 1.15), x1 - x)
        sh = h - rnd(0.0, 0.06)
        mat = random.choices(mats['sheets'], weights=(6, 1, 1))[0]
        corrugated(sw, sh, (x + sw / 2, y0 + 0.016 + rnd(-0.002, 0.004), z0 + sh / 2 + rnd(0, 0.02)), mat,
                   rot=(0, math.radians(rnd(-0.8, 0.8)) if w > 1 else 0, 0))
        x += sw - 0.05
    if big and w > 1.2 and h > 2 and random.random() < 0.7:
        pw, ph = rnd(0.6, 1.0), rnd(0.5, 0.8)
        box((pw, 0.008, ph), (cx + rnd(-0.6, 0.6), y0 - 0.002, z0 + rnd(0.6, 1.8)), rot=(0, math.radians(rnd(-10, 10)), 0), mat=mats['patch'])

def make_mats(tier):
    mats = {}
    if tier == 'wood':
        mats['planks'] = [wood_mat('wa')[1], wood_mat('wb', (0.78, 0.7, 0.62, 1))[1], wood_mat('wc', (0.62, 0.54, 0.46, 1), 'Wood049', 0.5)[1]]
        mats['stud'] = stud_mat('stud')[1]
        mats['rust'] = rust_steel('rust', 'CorrugatedSteel003', rust=0.9)[1]
    elif tier == 'stone':
        mats['block'] = cinder_mat('block')[1]; mats['concrete'] = concrete_mat('conc')[1]
        mats['rust'] = rust_steel('rust', 'CorrugatedSteel003', rust=0.9)[1]
    else:
        mats['iron'] = iron_mat('iron')[1]
        mats['sheets'] = [rust_steel('s1')[1], rust_steel('s2', 'CorrugatedSteel001', (0.5, 0.52, 0.52, 1), 0.85, desat=0.6)[1],
                          rust_steel('s3', 'CorrugatedSteel002', (0.6, 0.5, 0.48, 1), 0.85, desat=0.5)[1]]
        mats['patch'] = painted_mat('patch', 'PaintedMetal009', (0.55, 0.52, 0.42, 1))[1]; mats['plate'] = plate_mat('plate')[1]
    return mats

def decorate(mats, panels, scale=1.0):
    """Spray paint / blood on the outside of the biggest panels."""
    big = sorted(panels, key=lambda b: -(b['max'][0] - b['min'][0]) * (b['max'][2] - b['min'][2]))
    kinds = ['x', 'tally', 'circle', 'blood']
    allm = [m for v in mats.values() for m in (v if isinstance(v, list) else [v])]
    for b in big[:2]:
        if random.random() < 0.25: continue
        (x0, _, z0), (x1, _, z1) = b['min'], b['max']
        if x1 - x0 < 0.9 or z1 - z0 < 0.9: continue
        k = random.choice(kinds)
        size = (rnd(0.7, 1.1) if k != 'blood' else rnd(0.5, 0.8)) * scale
        cx = rnd(x0 + size / 2 + 0.1, max(x0 + size / 2 + 0.1, x1 - size / 2 - 0.1)); cz = rnd(z0 + 0.9, max(z0 + 0.9, z1 - 0.6))
        colour = random.choice([(0.38, 0.02, 0.01, 1), (0.04, 0.04, 0.04, 1), (0.6, 0.6, 0.55, 1)]) if k != 'blood' else (0.16, 0.01, 0.005, 1)
        for m in allm:
            w = REG.get(m.name)
            if w: w.decal(k, cx, cz, size, -1, colour)

# keep a handle from material -> M so decals can be added after geometry
REG = {}   # material name -> M (decals are added after the geometry)
_orig_finish = M.finish
def _finish(self, col, grime=0.55, mud=True):
    r = _orig_finish(self, col, grime, mud); REG[self.m.name] = self; return r
M.finish = _finish

# ---- floors
def deck_wood(x0, x1, y0, y1, ztop, mats, joists=True):
    y = y0 + 0.005
    while y < y1 - 0.03:
        pw = min(rnd(0.18, 0.28), y1 - y - 0.003)
        box((x1 - x0 - rnd(0, 0.03), pw, 0.04), ((x0 + x1) / 2, y + pw / 2, ztop - 0.02 - rnd(0, 0.006)),
            rot=(rnd(-0.01, 0.01), 0, 0), mat=random.choice(mats['planks']))
        y += pw + rnd(0.006, 0.02)
    if joists:
        for x in [x0 + 0.08 + i * (x1 - x0 - 0.16) / 4 for i in range(5)]:
            box((0.1, y1 - y0 - 0.02, 0.14), (x, (y0 + y1) / 2, ztop - 0.04 - 0.07), mat=mats['stud'])

def build_foundation(tier, mats, info):
    if tier == 'wood':
        deck_wood(-2, 2, -2, 2, 1.0, mats, joists=False)
        box((3.9, 3.9, 4.9), (0, 0, -1.5), mat=mats['stud'])            # core
        for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            box((0.22, 0.22, 4.95), (sx * 1.89, sy * 1.89, -1.5), mat=mats['stud'])
        for side in range(4):  # skirt planks
            z = 0.94
            while z > -1.6:
                ph = rnd(0.2, 0.3)
                rot = (0, 0, side * math.pi / 2)
                d = Vector((0, -1.985, 0)); d.rotate(Euler(rot))
                box((3.75, 0.03, ph), (d.x, d.y, z - ph / 2), rot=rot, mat=random.choice(mats['planks']))
                z -= ph + rnd(0.01, 0.03)
    elif tier == 'stone':
        box((4, 4, 0.16), (0, 0, 0.92), mat=mats['concrete'])
        box((3.98, 3.98, 4.84), (0, 0, -1.58), mat=mats['block'])
        for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            box((0.3, 0.3, 4.9), (sx * 1.85, sy * 1.85, -1.55), mat=mats['concrete'])
    else:
        for i in range(2):
            for j in range(2):
                box((1.98, 1.98, 0.02), (-1 + i * 2, -1 + j * 2, 0.99), rot=(0, 0, math.radians(rnd(-0.5, 0.5))), mat=mats['plate'])
        box((3.96, 3.96, 4.9), (0, 0, -1.5), mat=mats['iron'])
        for side in range(4):
            rot = (0, 0, side * math.pi / 2)
            for k in range(4):
                d = Vector((-1.5 + k, -1.99, 0)); d.rotate(Euler(rot))
                corrugated(1.05, 2.4, (d.x, d.y, -0.2), random.choices(mats['sheets'], weights=(6, 1, 1))[0], rot=rot)
        for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            box((0.16, 0.16, 4.98), (sx * 1.92, sy * 1.92, -1.5), mat=mats['iron'])

def build_ceiling(tier, mats, info):
    if tier == 'wood':
        deck_wood(-2, 2, -2, 2, 0.2, mats)
    elif tier == 'stone':
        box((4, 4, 0.18), (0, 0, 0.11), mat=mats['concrete'])
        for x in (-1.3, 0, 1.3): box((0.25, 4, 0.04), (x, 0, 0.01), mat=mats['concrete'])
    else:
        for i in range(2):
            for j in range(2):
                box((1.98, 1.98, 0.02), (-1 + i * 2, -1 + j * 2, 0.19), mat=mats['plate'])
        for x in (-1.6, -0.55, 0.55, 1.6): box((0.08, 3.96, 0.16), (x, 0, 0.09), mat=mats['iron'])

PANEL = {'wood': panel_wood, 'stone': panel_stone, 'metal': panel_metal}

def build_reuse(name, tier, mats):
    """Keep the old model's shape (stairs, ramps, hatches, cupboard), new texture."""
    bpy.ops.sollumz.import_assets(directory=SRC, files=[{"name": name + ".ydr"}])
    src = bpy.data.objects[name + '.model']
    me = src.data.copy(); me.materials.clear()
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    o = bpy.data.objects.new('reuse', me); bpy.context.collection.objects.link(o)
    mat = {'wood': mats.get('planks', [None])[0], 'stone': mats.get('block'), 'metal': mats.get('plate')}.get(tier)
    me.materials.append(mat); parts.append(o)

def build_piece(name):
    random.seed(zlib.crc32(name.encode()))
    info = PIECES[name]
    kind = name[len('wl_bp_'):]
    tier = kind.split('_')[-1] if kind.split('_')[-1] in ('wood', 'stone', 'metal') else None
    base = kind.rsplit('_', 1)[0] if tier else kind
    if base in ('door', 'garage', 'gate', 'windowbar') or kind in ('gate_frame', 'gate_door', 'toolcupboard'):
        tier = tier or ('metal' if kind in ('gate_frame', 'gate_door', 'toolcupboard') else 'wood')
    mats = make_mats(tier)
    if tier != 'wood' and kind.endswith('_wood'): pass
    panels = []
    if base in ('wall', 'halfwall', 'doorway', 'windowframe', 'frame'):
        panels = info['bounds']
        biggest = max(panels, key=lambda b: (b['max'][0] - b['min'][0]) * (b['max'][2] - b['min'][2]))
        for b in panels: PANEL[tier](b, mats, b is biggest)
        decorate(mats, panels)
    elif base == 'foundation': build_foundation(tier, mats, info)
    elif base == 'ceiling': build_ceiling(tier, mats, info)
    elif base in ('stairs', 'ramp', 'hatch') or kind == 'toolcupboard':
        if kind == 'toolcupboard': mats = make_mats('metal'); mats['plate'] = rust_steel('locker', 'PaintedMetal004', (0.5, 0.42, 0.4, 1), 0.9, desat=0.55)[1]
        build_reuse(name, tier if kind != 'toolcupboard' else 'metal', mats)
    elif kind == 'door_wood':
        mats = make_mats('wood'); x = 0.0
        while x < 1.15:
            pw = min(rnd(0.14, 0.22), 1.16 - x)
            box((pw - 0.006, 0.035, 2.14 - rnd(0, 0.03)), (x + pw / 2, -0.02, 0.02 + 1.07), mat=random.choice(mats['planks'])); x += pw
        for zz in (0.35, 1.85): box((1.05, 0.03, 0.14), (0.58, 0.025, zz), mat=mats['stud'])
        a = math.atan2(1.5, 0.95)
        box((math.hypot(1.5, 0.95), 0.028, 0.13), (0.58, 0.025, 1.1), rot=(0, -a, 0), mat=mats['stud'])
        decorate(mats, [{'min': [0, -0.04, 0.02], 'max': [1.16, 0.04, 2.17]}], 0.55)
    elif kind == 'door_metal':
        mats = make_mats('metal')
        box((1.14, 0.012, 2.13), (0.58, -0.025, 1.095), mat=mats['patch'])
        for x in (0.04, 1.12): box((0.06, 0.05, 2.13), (x, 0.01, 1.095), mat=mats['iron'])
        for zz in (0.08, 1.1, 2.1): box((1.1, 0.05, 0.06), (0.58, 0.01, zz), mat=mats['iron'])
        corrugated(0.9, 0.7, (0.6, -0.034, 0.6), mats['sheets'][0], rot=(0, math.radians(3), 0))
        cyl(0.012, 1.0, (0.58, 0.02, 1.6), rot=(0, math.radians(60), 0), mat=mats['iron'])
        decorate(mats, [{'min': [0, -0.04, 0.02], 'max': [1.16, 0.04, 2.17]}], 0.55)
    elif kind == 'garage_wood':
        mats = make_mats('wood'); x = -1.58
        while x < 1.57:
            pw = min(rnd(0.15, 0.24), 1.58 - x)
            box((pw - 0.006, 0.04, 2.54 - rnd(0, 0.04)), (x + pw / 2, -0.025, 0.02 + 1.27), mat=random.choice(mats['planks'])); x += pw
        for zz in (0.4, 1.3, 2.2): box((3.1, 0.035, 0.15), (0, 0.03, zz), mat=mats['stud'])
        for sx in (-1, 1):
            a = math.atan2(0.9, 1.4) * sx
            box((math.hypot(1.4, 0.9), 0.03, 0.13), (sx * 0.78, 0.03, 0.85), rot=(0, a, 0), mat=mats['stud'])
        decorate(mats, [{'min': [-1.58, -0.05, 0.02], 'max': [1.58, 0.05, 2.58]}])
    elif kind == 'gate_door':
        mats = make_mats('metal'); x = 0.05
        while x < 4.5:
            sw = min(rnd(0.9, 1.1), 4.55 - x)
            corrugated(sw, 3.8, (x + sw / 2, -0.04, 2.0), random.choices(mats['sheets'], weights=(6, 1, 1))[0]); x += sw - 0.04
        for zz in (0.12, 2.0, 3.88): box((4.5, 0.06, 0.08), (2.28, 0.025, zz), mat=mats['iron'])
        for xx in (0.05, 2.28, 4.5): box((0.08, 0.06, 3.85), (xx, 0.025, 2.0), mat=mats['iron'])
        a = math.atan2(3.7, 2.2)
        for cx in (1.17, 3.39): box((math.hypot(2.2, 3.7), 0.05, 0.07), (cx, 0.03, 2.0), rot=(0, -a, 0), mat=mats['iron'])
        decorate(mats, [{'min': [0, -0.06, 0.05], 'max': [4.56, 0.06, 3.95]}, {'min': [2.3, -0.06, 0.05], 'max': [4.56, 0.06, 3.95]}])
    elif kind == 'gate_frame':
        mats = make_mats('metal'); wm = make_mats('wood'); mats.update({'planks': wm['planks'], 'stud': wm['stud']})
        for sx in (-1, 1):
            box((0.46, 0.46, 4.5), (sx * 2.55, 0, 2.25), mat=mats['iron'])
            for k in range(4):
                corrugated(0.5, 1.2, (sx * 2.55, -0.245, 0.6 + k * 1.05), mats['sheets'][0], rot=(0, math.radians(rnd(-3, 3)), 0))
        box((5.6, 0.48, 0.46), (0, 0, 4.25), mat=mats['iron'])
        z = 4.04
        for k in range(3):
            box((5.5, 0.03, 0.14), (0, -0.25, z + 0.07 + k * 0.15), rot=(0, math.radians(rnd(-1, 1)), 0), mat=random.choice(mats['planks']))
        for sx in (-1, 1):
            box((0.9, 0.08, 0.12), (sx * 2.1, 0, 3.7), rot=(0, sx * math.radians(40), 0), mat=mats['iron'])
        decorate(mats, [{'min': [-0.8, -0.25, 4.0], 'max': [0.8, 0.25, 4.5]}])
    elif kind == 'windowbar_wood':
        mats = make_mats('wood')
        for zz, a in ((1.2, 6), (1.5, -4), (1.8, 3)):
            box((1.2, 0.028, 0.15), (0, -0.01, zz), rot=(0, math.radians(a), 0), mat=random.choice(mats['planks']))
        box((1.3, 0.025, 0.14), (0, 0.015, 1.5), rot=(0, math.radians(38), 0), mat=mats['planks'][2])
    elif kind == 'windowbar_metal':
        mats = make_mats('metal')
        for i in range(7):
            cyl(0.011, 0.94, (-0.5 + i * (1.0 / 6), 0, 1.5), mat=mats['iron'])
        for zz in (1.08, 1.92): box((1.16, 0.035, 0.05), (0, 0, zz), mat=mats['iron'])
    else:
        print('SKIP', name); return False
    return True

# ----------------------------------------------------------------------------- bake + preview
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
def join_and_bake(name):
    for x in bpy.context.selected_objects: x.select_set(False)
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object; o.name = 'piece_hi'
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for uv in list(o.data.uv_layers): o.data.uv_layers.remove(uv)
    o.data.uv_layers.new(name='bake')
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
    bpy.ops.object.mode_set(mode='OBJECT')
    col = bpy.data.images.new('bake_' + name, SIZE, SIZE); ao = bpy.data.images.new('ao_' + name, SIZE, SIZE)
    def target(im):
        for m in o.data.materials:
            nt = m.node_tree
            t = nt.nodes.get('BAKE_T') or nt.nodes.new('ShaderNodeTexImage'); t.name = 'BAKE_T'; t.image = im
            u = nt.nodes.get('BAKE_U') or nt.nodes.new('ShaderNodeUVMap'); u.name = 'BAKE_U'; u.uv_map = 'bake'
            nt.links.new(u.outputs['UV'], t.inputs['Vector']); nt.nodes.active = t
    rb = scene.render.bake
    rb.use_pass_direct = False; rb.use_pass_indirect = False; rb.use_pass_color = True; rb.margin = 6
    target(col); scene.cycles.samples = 4; bpy.ops.object.bake(type='DIFFUSE')
    target(ao); scene.cycles.samples = 24; bpy.ops.object.bake(type='AO')
    c = list(col.pixels); a = ao.pixels[:]
    for i in range(0, len(c), 4):
        f = 0.35 + 0.65 * a[i]
        c[i] *= f; c[i + 1] *= f; c[i + 2] *= f; c[i + 3] = 1.0
    col.pixels = c
    col.filepath_raw = os.path.join(OUTP, name + '_d.png'); col.file_format = 'PNG'; col.save()
    game = bpy.data.materials.new('game'); game.use_nodes = True
    gn = game.node_tree.nodes; t = gn.new('ShaderNodeTexImage'); t.image = col
    game.node_tree.links.new(t.outputs['Color'], gn['Principled BSDF'].inputs['Base Color'])
    gn['Principled BSDF'].inputs['Roughness'].default_value = 0.85
    o.data.materials.clear(); o.data.materials.append(game)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    return o, tris

def preview(o, name):
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 480; scene.render.resolution_y = 360
    w = bpy.data.worlds.get('pw') or bpy.data.worlds.new('pw'); scene.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.22, 0.24, 0.21, 1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.9
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.data.energy = 3.2; sun.rotation_euler = (math.radians(50), math.radians(8), math.radians(-35))
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.lens = 40
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector([min(v[i] for v in bb) for i in range(3)]); mx = Vector([max(v[i] for v in bb) for i in range(3)])
    if name.startswith('wl_bp_foundation'): mn.z = max(mn.z, -0.6)
    ctr = (mn + mx) / 2; rad = max((mx - mn).length / 2, 0.6)
    cam.location = ctr + Vector((0.55, -1.0, 0.45)).normalized() * rad * 2.6
    cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(OUTV, name + '.png')
    bpy.ops.render.render(write_still=True)
    scene.render.engine = 'CYCLES'

done = []
for name in names:
    clear(); parts.clear(); REG.clear()
    if not build_piece(name): continue
    o, tris = join_and_bake(name)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTP, name + '.blend'), copy=True)
    preview(o, name)
    print('BUILT', name, tris, flush=True)
    done.append(name)
print('ALL DONE', len(done))
