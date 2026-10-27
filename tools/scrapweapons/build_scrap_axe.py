# Scrap-made axe (scrap_axe): a head cut from thick rusty steel plate with a
# freshly ground edge, bolted through a rough wooden handle and lashed with
# wire and a rag; a bent rebar spike on the back; tape on the grip. Built on
# the game's hatchet: same length (z -0.147 .. 0.384), the head at the top
# with the blade towards +X, everything on Gun_Main_Bone.
#   blender -b --python build_scrap_axe.py -- <tex folder> <out folder>
import bpy, bmesh, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(23)
C.start(TEX)
MAIN = 'Gun_Main_Bone'


def plate_steel():
    m = C.Mat('plate')
    base = m.ramp(m.noise(40, 6), (0.035, 0.03, 0.026, 1), (0.085, 0.075, 0.065, 1), 0.3, 0.75)
    rust = m.mix(m.tex('Rust004', 18.0), (0.55, 0.5, 0.45, 1), 1.0, 'MULTIPLY')
    c = m.mix(base, rust, m.above(m.noise(7, 8), 0.47))
    # the ground edge: bright steel along the front of the blade (object x > 0.085)
    sep = m.n.new('ShaderNodeSeparateXYZ'); m.l.new(m.tc, sep.inputs['Vector'])
    edge = m.n.new('ShaderNodeMath'); edge.operation = 'GREATER_THAN'; edge.inputs[1].default_value = 0.104
    m.l.new(sep.outputs['X'], edge.inputs[0])
    shiny = m.ramp(m.noise(120, 2), (0.075, 0.075, 0.075, 1), (0.15, 0.15, 0.145, 1), 0.3, 0.7)
    c = m.mix(c, shiny, edge.outputs[0])
    # old blood on the blade
    c = m.mix(c, (0.08, 0.01, 0.006, 1), m.above(m.noise(15, 8), 0.66))
    return m.done(m.grime(c, 0.7, 20), 0.5)


def rag():
    m = C.Mat('rag')
    c = m.ramp(m.noise(50, 6), (0.05, 0.04, 0.028, 1), (0.12, 0.1, 0.07, 1), 0.3, 0.75)
    c = m.mix(c, (0.1, 0.012, 0.008, 1), m.above(m.noise(10, 6), 0.6))
    return m.done(c, 0.9)


PLATE, WOOD, TAPE, BLACK, RUST, RAG = plate_steel(), C.wood((0.62, 0.48, 0.34, 1), 8.0), C.tape((0.12, 0.12, 0.115, 1)), C.black_metal(), C.rusty(), rag()


def flat(points, thick, mat, bevel=0.0015, y=0.0):
    """A flat shape in the XZ plane, thick along Y (centred on y)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y - thick / 2, z)) for x, z in points]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)], vec=(0, thick, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0: bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect='EDGES', clamp_overlap=True)
    return C.add(bm, 'flat', mat, MAIN)


# ---- handle: a rough branch, slightly crooked, thicker at the bottom
bm = bmesh.new(); rings = []; SEG = 12
zs = [-0.147 + i * 0.026 for i in range(23)]
for k, z in enumerate(zs):
    r = 0.0165 - 0.003 * (z + 0.147) / 0.58 + random.uniform(-0.0006, 0.0006)
    off = 0.004 * math.sin(z * 9.0)                       # a slight bend
    ring = [bm.verts.new((off + r * math.cos(2 * math.pi * i / SEG), r * 0.85 * math.sin(2 * math.pi * i / SEG), z)) for i in range(SEG)]
    rings.append(ring)
for k in range(len(rings) - 1):
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
h = C.add(bm, 'handle', WOOD, MAIN)
for p in h.data.polygons: p.use_smooth = True
# tape on the grip, wound in a few uneven wraps
for z in (-0.12, -0.095, -0.07, -0.045, -0.02, 0.005):
    C.place(C.ring(0.0158 - 0.003 * (z + 0.147) / 0.58, 0.027, 0.0012, TAPE, MAIN, 14), (0.004 * math.sin(z * 9) + random.uniform(-0.0005, 0.0005), 0, z), (random.uniform(-0.04, 0.04), random.uniform(-0.04, 0.04), 1))

# ---- head: thick plate in two layers (blade and a cheek plate each side)
blade = [(-0.02, 0.36), (0.03, 0.372), (0.075, 0.395), (0.112, 0.43), (0.124, 0.395), (0.128, 0.33), (0.122, 0.265),
         (0.108, 0.235), (0.07, 0.27), (0.03, 0.29), (-0.02, 0.295)]
flat(blade, 0.009, PLATE)
for side in (-1, 1):                                       # cheek plates bolted either side of the handle
    flat([(-0.03, 0.29), (0.035, 0.287), (0.035, 0.37), (-0.03, 0.372)], 0.003, RUST, 0.001, y=side * 0.0175)
    for z in (0.305, 0.355):
        C.place(C.cylinder(0.0045, 0.004, BLACK, MAIN, 6, smooth=False), (0.012, side * 0.019, z), (0, side, 0))   # bolt heads / nuts
# bevel facets of the grind: two thin strips along the edge, tilted
for side in (-1, 1):
    flat([(0.09, 0.40), (0.112, 0.427), (0.124, 0.395), (0.128, 0.33), (0.122, 0.268), (0.108, 0.24), (0.095, 0.26), (0.103, 0.33), (0.1, 0.39)],
         0.0012, PLATE, 0.0, y=side * 0.0048)
# back spike: bent rebar welded on, and the weld bead
C.poly_tube([(-0.02, 0, 0.335), (-0.045, 0, 0.338), (-0.065, 0, 0.33), (-0.078, 0, 0.318)], 0.0045, RUST, MAIN)
C.place(C.cylinder(0.0045, 0.012, RUST, MAIN, 8, r2=0.0005), (-0.077, 0, 0.318), (-0.6, 0, -0.8))
for i in range(6):
    C.place(C.cylinder(0.003, 0.002, BLACK, MAIN, 6), (-0.021 - i * 0.0015, 0, 0.326 + i * 0.003), (-1, 0, 0))

# ---- lashing: wire and a rag knotted round handle and head
pts = []
for i in range(90):
    t = i / 89; a = t * 2 * math.pi * 6
    pts.append((0.002 + 0.0148 * math.cos(a), 0.0128 * math.sin(a), 0.262 + t * 0.022))
C.poly_tube(pts, 0.001, BLACK, MAIN)
C.place(C.ring(0.017, 0.024, 0.003, RAG, MAIN, 12), (0.0, 0, 0.375), (0.1, 0.05, 1))
C.poly_tube([(0.004, -0.019, 0.39), (0.006, -0.026, 0.37), (0.003, -0.03, 0.345)], 0.003, RAG, MAIN)   # loose end

o, tris = C.join_and_bake(OUT, 'scrap_axe')
C.renders(o, OUT, 'scrap_axe',
          [((0.02, 0, 0.12), (0.2, -0.75, 0.15), 50),
           ((0.02, 0, 0.12), (-0.5, -0.5, 0.4), 50),
           ((0.04, 0, 0.33), (0.1, -0.28, 0.06), 50)],
          (math.radians(-90), 0, math.radians(-45)), 0.62)
print('BUILT scrap_axe', tris, 'tris', flush=True)
