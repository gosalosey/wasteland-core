# Scrap machete (scrap_machete): a blade cut from rusty steel plate with a
# freshly ground edge, saw teeth hacked into the spine, old bolt holes from
# whatever it used to be, a bent-bar guard, a cord-wrapped handle and a hex
# nut for a pommel. Built on the game's machete: handle z -0.043 .. 0.08,
# blade up to z 0.438, edge towards -X, spine towards +X; Gun_Root.
#   blender -b --python build_scrap_machete.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(61)
C.start(TEX)
BONE = 'Gun_Root'
Z = (0, 0, 1)


def blade_steel():
    m = C.Mat('blade')
    base = m.ramp(m.noise(40, 6), (0.035, 0.03, 0.026, 1), (0.085, 0.075, 0.065, 1), 0.3, 0.75)
    rust = m.mix(m.tex('Rust004', 20.0), (0.55, 0.5, 0.45, 1), 1.0, 'MULTIPLY')
    c = m.mix(base, rust, m.above(m.noise(7, 8), 0.5))
    c = m.mix(c, (0.075, 0.009, 0.006, 1), m.above(m.noise(16, 8), 0.62))     # old blood
    return m.done(m.grime(c, 0.7, 20), 0.5)


def ground_edge():
    m = C.Mat('edge')
    c = m.ramp(m.noise(140, 2), (0.075, 0.075, 0.075, 1), (0.15, 0.15, 0.145, 1), 0.3, 0.7)
    c = m.mix(c, (0.075, 0.009, 0.006, 1), m.above(m.noise(16, 8), 0.68))
    return m.done(c, 0.35)


def cord():
    m = C.Mat('cord')
    c = m.ramp(m.noise(120, 3), (0.02, 0.022, 0.016, 1), (0.05, 0.055, 0.04, 1), 0.3, 0.7)   # dark olive paracord
    return m.done(m.grime(c, 0.6, 15), 0.9)


BLADE, EDGE, CORD, BANDS, BLACK = blade_steel(), ground_edge(), cord(), C.band_steel(), C.black_metal()
WOOD = C.wood((0.4, 0.28, 0.18, 1), 8.0)
T = 0.0045      # blade thickness

# ---- blade
blade = [(0.022, 0.07), (0.026, 0.2), (0.03, 0.36), (0.022, 0.415), (-0.005, 0.44), (-0.03, 0.426), (-0.045, 0.39),
         (-0.043, 0.3), (-0.033, 0.18), (-0.024, 0.07)]
C.flat_xz(blade, T, BLADE, BONE, 0.0008)
# ground edge: a bright band along the edge on both faces
band = [(-0.024, 0.075), (-0.033, 0.18), (-0.043, 0.3), (-0.045, 0.39), (-0.03, 0.426), (-0.005, 0.44),
        (-0.004, 0.428), (-0.024, 0.414), (-0.035, 0.385), (-0.034, 0.3), (-0.024, 0.18), (-0.016, 0.08)]
for side in (-1, 1):
    C.flat_xz(band, 0.0005, EDGE, BONE, y=side * (T / 2 + 0.0002))
# saw teeth hacked into the spine
for i in range(9):
    z = 0.12 + i * 0.018
    x = 0.022 + (z - 0.07) / (0.2 - 0.07) * 0.004 if z < 0.2 else 0.026 + (z - 0.2) / 0.16 * 0.004
    C.flat_xz([(x - 0.001, z), (x + 0.007, z + 0.004), (x - 0.001, z + 0.014)], T, BLADE, BONE)
# old bolt holes (dark discs on both faces)
for x, z in ((0.012, 0.15), (0.015, 0.26), (-0.01, 0.35)):
    for side in (-1, 1):
        C.place(C.cylinder(0.0045, 0.0006, BLACK, BONE, 10), (x, side * (T / 2 + 0.0001), z), (0, side, 0))

# ---- guard: a bent flat bar across the blade's root
C.flat_xz([(-0.038, 0.074), (0.034, 0.072), (0.04, 0.084), (0.033, 0.08), (-0.032, 0.082), (-0.042, 0.088)], 0.014, BANDS, BONE, 0.0015)

# ---- handle: two wood slabs on the tang, wound in cord, a hex nut pommel
C.flat_xz([(-0.018, 0.072), (0.02, 0.072), (0.024, -0.03), (0.006, -0.038), (-0.012, -0.03)], 0.022, WOOD, BONE, 0.004, segments=2)
pts = []
for i in range(400):
    t = i / 399; a = t * 2 * math.pi * 23
    z = 0.066 - t * 0.092
    w = 0.0198 - t * 0.001
    pts.append((0.001 + t * 0.005 + w * math.cos(a), 0.0118 * math.sin(a), z))
C.poly_tube(pts, 0.0021, CORD, BONE)
C.place(C.cylinder(0.014, 0.012, BANDS, BONE, 6, smooth=False), (0.012, 0, -0.05), Z)
C.place(C.cylinder(0.004, 0.012, BLACK, BONE, 8), (0.012, 0, -0.046), Z)                 # tang end peened over the nut

o, tris = C.join_and_bake(OUT, 'scrap_machete')
C.renders(o, OUT, 'scrap_machete',
          [((0.0, 0, 0.2), (0.12, -0.7, 0.12), 50),
           ((0.0, 0, 0.2), (-0.45, -0.45, 0.35), 50),
           ((0.0, 0, 0.06), (0.06, -0.22, 0.06), 50)],
          (math.radians(-90), 0, math.radians(-45)), 0.55)
print('BUILT scrap_machete', tris, 'tris', flush=True)
