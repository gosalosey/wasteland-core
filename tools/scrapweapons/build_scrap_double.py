# Improvised double-barrel (scrap_double_barrel), v4 after the user's second
# reference picture: two thick pipes side by side in mottled tan and green
# camo paint, a coupling collar at the breech, a long receiver in chipped red
# paint with a raised ribbed panel and two small spring hammers, a bent-rod
# trigger guard, and a brown stock with a red-painted wrist wound in wide
# white bandage strips.
# Built on the game's sawed-off double-barrel: the barrels are on the hinge
# bone (Gun_Breach) so they swing open on reload, the triggers on
# Gun_Trigger_Pr, the rest on Gun_Main_Bone. X forward, bore line z = 0.046,
# muzzle x = 0.423, right hand (-0.084, -0.068).
#   blender -b --python build_scrap_double.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(97)
C.start(TEX)

MAIN, BREACH, TRIGGER = 'Gun_Main_Bone', 'Gun_Breach', 'Gun_Trigger_Pr'
BORE_Z = 0.046
X = (1, 0, 0)
R, DY = 0.0178, 0.0182          # barrel radius, half the spacing


def camo():
    """Tan/orange paint with green blotches, worn to rust in places."""
    m = C.Mat('camo')
    tan = m.ramp(m.noise(30, 4), (0.12, 0.05, 0.02, 1), (0.22, 0.1, 0.04, 1), 0.3, 0.75)
    green = m.ramp(m.noise(30, 4), (0.035, 0.06, 0.025, 1), (0.07, 0.11, 0.045, 1), 0.3, 0.75)
    c = m.mix(tan, green, m.above(m.noise(9, 5), 0.57))
    rust = m.mix(m.tex('Rust004', 24.0), (0.45, 0.4, 0.35, 1), 1.0, 'MULTIPLY')
    c = m.mix(c, rust, m.above(m.noise(22, 8), 0.68))
    return m.done(m.grime(c, 0.72, 16), 0.6)


def red_paint():
    """Red paint chipped down to dark steel along the wear."""
    m = C.Mat('redpaint')
    red = m.ramp(m.noise(40, 4), (0.16, 0.012, 0.012, 1), (0.3, 0.03, 0.025, 1), 0.3, 0.75)
    steel = m.ramp(m.noise(60, 4), (0.03, 0.03, 0.03, 1), (0.07, 0.065, 0.06, 1), 0.3, 0.7)
    c = m.mix(red, steel, m.above(m.noise(14, 8), 0.64))
    c = m.mix(c, (0.13, 0.12, 0.11, 1), m.above(m.noise(50, 6), 0.75))       # pale scratches
    return m.done(m.grime(c, 0.75, 18), 0.5)


def brown_stock():
    m = C.Mat('stock')
    c = m.mix(m.tex('Wood049', 8.0), (0.36, 0.2, 0.12, 1), 1.0, 'MULTIPLY')
    c = m.mix(c, (0.16, 0.012, 0.012, 1), m.above(m.noise(10, 6), 0.7))      # flecks of red paint
    return m.done(m.grime(c, 0.7, 14), 0.7)


def bandage():
    m = C.Mat('bandage')
    c = m.ramp(m.noise(90, 3), (0.13, 0.125, 0.115, 1), (0.24, 0.23, 0.21, 1), 0.3, 0.75)
    c = m.mix(c, m.ramp(m.noise(14, 6), (0.5, 0.45, 0.38, 1), (1, 1, 1, 1), 0.35, 0.7), 1.0, 'MULTIPLY')   # dirt
    c = m.mix(c, (0.12, 0.02, 0.015, 1), m.above(m.noise(11, 6), 0.7))     # rubbed-off red
    return m.done(c, 0.9)


CAMO, RED, STOCK, BAND = camo(), red_paint(), brown_stock(), bandage()
BLACK, BANDS = C.black_metal(), C.band_steel()

# ---- barrels (swing open): two thick hollow pipes, a coupling collar, bead
for y in (-DY, DY):
    C.place(C.tube_pipe(R, 0.0135, 0.27, CAMO, BREACH, 22), (0.155, y, BORE_Z), X)
    C.place(C.ring(R, 0.03, 0.0035, CAMO, BREACH, 22), (0.155, y, BORE_Z), X)              # coupling collar
    C.place(C.ring(R + 0.0035, 0.004, 0.0012, BANDS, BREACH, 22), (0.183, y, BORE_Z), X)    # its rim
C.flat_xz([(0.19, BORE_Z + R - 0.004), (0.42, BORE_Z + R - 0.004), (0.42, BORE_Z + R + 0.002), (0.19, BORE_Z + R + 0.002)],
          0.008, CAMO, BREACH, 0.0015)                                                   # rib between them
C.place(C.cylinder(0.0022, 0.007, BANDS, BREACH, 8), (0.412, 0, BORE_Z + R + 0.002), (0, 0, 1))   # bead
s = C.box((0.06, 0.02, 0.006), BANDS, BREACH); s.location = (0.18, 0, BORE_Z - R - 0.003)     # hinge strap

# ---- receiver (stays): long red body, ribbed panel, spring hammers, hinge
rcv = [(-0.005, BORE_Z + 0.008), (0.03, BORE_Z + 0.016), (0.155, BORE_Z + 0.016), (0.155, 0.006), (0.07, -0.002),
       (0.0, -0.006), (-0.01, 0.01)]
C.flat_xz(rcv, 0.07, RED, MAIN, 0.006, segments=2)
for side in (-1, 1):
    for i in range(9):                                                                    # raised ribs on the side panel
        r = C.box((0.004, 0.003, 0.016), RED, MAIN, bevel=0.001)
        r.location = (0.06 + i * 0.008, side * 0.0355, 0.028)
for y in (-0.012, 0.012):                                                                 # two spring hammers
    pts = [(0.05 + 0.006 * math.cos(a), y + 0.006 * math.sin(a), BORE_Z + 0.016 + t * 0.016)
           for t, a in [(i / 40, i / 40 * 2 * math.pi * 5) for i in range(41)]]
    C.poly_tube(pts, 0.0013, BLACK, MAIN)
    C.place(C.cylinder(0.0045, 0.006, BANDS, MAIN, 8, smooth=False), (0.05, y, BORE_Z + 0.032), (0, 0, 1))
    C.poly_tube([(0.05, y, BORE_Z + 0.036), (0.06, y, BORE_Z + 0.04), (0.07, y, BORE_Z + 0.036)], 0.0022, BLACK, MAIN)
C.place(C.cylinder(0.007, 0.075, BANDS, MAIN, 12), (0.152, -0.0375, 0.012), (0, 1, 0))   # hinge knuckle

# ---- trigger guard (bent rod) and two triggers
C.poly_tube([(0.072, 0, -0.002), (0.07, 0, -0.03), (0.05, 0, -0.042), (0.02, 0, -0.044), (-0.008, 0, -0.036), (-0.012, 0, -0.008)],
            0.0028, BANDS, MAIN)
for x in (0.022, 0.038):
    C.poly_tube([(x, 0, -0.002), (x + 0.002, 0, -0.014), (x - 0.004, 0, -0.026)], 0.0022, BLACK, TRIGGER)

# ---- stock: red-painted wrist, brown butt, wide white bandage strips
TOP = [(0.0, BORE_Z + 0.004), (-0.04, 0.02), (-0.09, -0.006), (-0.17, -0.004), (-0.29, 0.024)]
BOT = [(0.0, -0.008), (-0.04, -0.045), (-0.07, -0.092), (-0.1, -0.104), (-0.14, -0.096), (-0.24, -0.124), (-0.29, -0.12)]


def edge(chain, x):
    for (x0, z0), (x1, z1) in zip(chain, chain[1:]):
        if x1 <= x <= x0: return z0 + (z1 - z0) * (x - x0) / (x1 - x0)
    return chain[-1][1]


C.flat_xz(TOP + list(reversed(BOT)), 0.044, STOCK, MAIN, 0.008, segments=2)


def wrap(xa, xb, slant, mat, thick=0.0455):
    quad = [(xa + slant, edge(TOP, xa + slant) + 0.0014), (xb + slant, edge(TOP, xb + slant) + 0.0014),
            (xb, edge(BOT, xb) - 0.0014), (xa, edge(BOT, xa) - 0.0014)]
    C.flat_xz(quad, thick, mat, MAIN, 0.0082, segments=2)


wrap(-0.07, -0.002, 0.0, RED)                      # red paint over the wrist
for xa, xb, sl in ((-0.112, -0.078, 0.03), (-0.178, -0.14, -0.025), (-0.205, -0.17, 0.028), (-0.262, -0.226, -0.02)):
    wrap(xa, xb, sl, BAND, 0.0465)

o, tris = C.join_and_bake(OUT, 'scrap_double')
C.renders(o, OUT, 'scrap_double',
          [((0.06, 0, -0.01), (0.15, -0.85, 0.15), 50),
           ((0.06, 0, -0.01), (-0.55, -0.55, 0.4), 50),
           ((0.1, 0, 0.03), (0.08, -0.26, 0.14), 50)],
          (math.radians(-90), 0, math.radians(-40)), 0.85)
print('BUILT scrap_double', tris, 'tris', flush=True)
