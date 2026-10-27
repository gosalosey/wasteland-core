# Heavy scrap maul (scrap_maul): a head cut from a chunk of steel I-beam,
# welded to a thick pipe handle with gusset plates, rebar studs on both
# striking faces, a length of chain wrapped round the neck, a taped and
# rag-wrapped grip. Built on the game's bat (two-handed): same length
# (z -0.137 .. 0.670), head across the top along X, all on Gun_Main_Bone.
#   blender -b --python build_scrap_maul.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(83)
C.start(TEX)
MAIN = 'Gun_Main_Bone'
Z = (0, 0, 1)


def beam_steel():
    m = C.Mat('beam')
    base = m.ramp(m.noise(30, 6), (0.03, 0.026, 0.022, 1), (0.075, 0.065, 0.055, 1), 0.3, 0.75)
    rust = m.mix(m.tex('Rust004', 14.0), (0.5, 0.45, 0.4, 1), 1.0, 'MULTIPLY')
    c = m.mix(base, rust, m.above(m.noise(6, 8), 0.45))
    c = m.mix(c, (0.075, 0.009, 0.006, 1), m.above(m.noise(12, 8), 0.6))      # blood on the faces
    return m.done(m.grime(c, 0.7, 18), 0.55)


def rag():
    m = C.Mat('rag')
    c = m.ramp(m.noise(50, 6), (0.022, 0.018, 0.012, 1), (0.055, 0.046, 0.032, 1), 0.3, 0.75)
    c = m.mix(c, (0.09, 0.01, 0.007, 1), m.above(m.noise(10, 6), 0.6))
    return m.done(c, 0.9)


BEAM, STEEL, BANDS, BLACK = beam_steel(), C.old_steel(), C.band_steel(), C.black_metal()
TAPE, RAG = C.tape((0.12, 0.12, 0.115, 1)), rag()
HEAD_Z = 0.60          # centre height of the head

# ---- handle: thick pipe, end cap, grip of tape with a rag wound over the top of it
C.place(C.cylinder(0.0155, 0.66, STEEL, MAIN, 18), (0, 0, -0.135), Z)
C.place(C.cylinder(0.019, 0.012, BANDS, MAIN, 8, smooth=False), (0, 0, -0.137), Z)
for i in range(9):
    C.place(C.ring(0.0155, 0.026, 0.0013, TAPE, MAIN, 16),
            (random.uniform(-0.0004, 0.0004), 0, -0.12 + i * 0.024), (random.uniform(-0.03, 0.03), random.uniform(-0.03, 0.03), 1))
for i in range(4):
    C.place(C.ring(0.017, 0.022, 0.0028, RAG, MAIN, 12), (0, 0, 0.1 + i * 0.018), (random.uniform(-0.08, 0.08), random.uniform(-0.08, 0.08), 1))

# ---- head: an I-beam section lying across (along X): two flanges and a web
L, W, H = 0.22, 0.075, 0.085          # length (X), flange width (Y), height (Z)
TF, TW = 0.011, 0.009                 # flange and web thickness
for z in (HEAD_Z + H / 2 - TF / 2, HEAD_Z - H / 2 + TF / 2):
    f = C.box((L, W, TF), BEAM, MAIN, bevel=0.0015); f.location = (0, 0, z)
web = C.box((L, TW, H - 2 * TF), BEAM, MAIN); web.location = (0, 0, HEAD_Z)
# end plates welded on as striking faces, with rebar studs
for side in (-1, 1):
    p = C.box((0.012, W + 0.004, H + 0.004), BEAM, MAIN, bevel=0.002); p.location = (side * (L / 2 + 0.006), 0, HEAD_Z)
    for dy in (-0.022, 0.0, 0.022):
        for dz in (-0.024, 0.0, 0.024):
            if (dy == 0.0) != (dz == 0.0): continue            # an X of five studs
            C.place(C.cylinder(0.0055, 0.012, BLACK, MAIN, 8, r2=0.0035), (side * (L / 2 + 0.012), dy, HEAD_Z + dz), (side, 0, 0))
# the handle runs up through the bottom flange; gusset plates either side
for side in (-1, 1):
    C.flat_xz([(-0.05, HEAD_Z - H / 2), (0.05, HEAD_Z - H / 2), (0.016, HEAD_Z - H / 2 - 0.06), (-0.016, HEAD_Z - H / 2 - 0.06)],
              0.006, BEAM, MAIN, 0.001, y=side * 0.0185)
for i in range(10):                                                                       # weld bead round the handle
    a = i / 10 * 2 * math.pi
    C.place(C.cylinder(0.004, 0.004, BANDS, MAIN, 6), (0.017 * math.cos(a), 0.017 * math.sin(a), HEAD_Z - H / 2 - 0.002), Z)

# ---- chain wrapped round the neck: small links along a helix, alternating flat and standing
N = 30
for i in range(N):
    t = i / (N - 1); a = t * 2 * math.pi * 2.6
    radial = Vector((math.cos(a), math.sin(a), 0))
    pos = radial * 0.0195 + Vector((0, 0, 0.462 + t * 0.04))
    tang = Vector((-math.sin(a), math.cos(a), 0.06)).normalized()
    axis = radial if i % 2 == 0 else tang.cross(radial).normalized()
    C.place(C.ring(0.0034, 0.0026, 0.0021, BLACK, MAIN, 10), pos - axis * 0.0013, axis)

o, tris = C.join_and_bake(OUT, 'scrap_maul')
C.renders(o, OUT, 'scrap_maul',
          [((0.0, 0, 0.27), (0.3, -1.05, 0.25), 50),
           ((0.0, 0, 0.27), (-0.6, -0.65, 0.55), 50),
           ((0.0, 0, 0.56), (0.18, -0.35, 0.12), 50)],
          (math.radians(-90), 0, math.radians(-45)), 0.85)
print('BUILT scrap_maul', tris, 'tris', flush=True)
