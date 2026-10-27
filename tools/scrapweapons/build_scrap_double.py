# Improvised double-barrel (scrap_double_barrel): two thick pipes side by
# side painted teal-green and worn to rust, clamp bands, a chunky breech block
# with bolts and a spare brass shell wired on top, and a long stock wound in
# strips of coloured rag (v2, after the user's reference picture). Built on the game's
# sawed-off double-barrel: the barrels and forend are on the hinge bone
# (Gun_Breach) so they swing open on reload, the trigger on Gun_Trigger_Pr,
# the rest on Gun_Main_Bone. X forward, bore line z = 0.046, muzzle x = 0.423.
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
R, DY = 0.0168, 0.0172          # barrel radius, half the spacing (thick pipes)


def rubber():
    m = C.Mat('rubber')
    c = m.ramp(m.noise(90, 3), (0.01, 0.01, 0.01, 1), (0.035, 0.035, 0.033, 1), 0.3, 0.75)
    return m.done(c, 0.85)


def green_paint():
    """Teal-green paint worn through to rust and bare steel."""
    m = C.Mat('greenpaint')
    paint = m.ramp(m.noise(35, 4), (0.012, 0.05, 0.04, 1), (0.03, 0.1, 0.075, 1), 0.3, 0.75)
    rust = m.mix(m.tex('Rust004', 24.0), (0.5, 0.45, 0.4, 1), 1.0, 'MULTIPLY')
    c = m.mix(paint, rust, m.above(m.noise(9, 8), 0.56))
    c = m.mix(c, (0.09, 0.09, 0.085, 1), m.above(m.noise(40, 6), 0.72))       # bare scratches
    return m.done(m.grime(c, 0.7, 18), 0.55)


def brass():
    m = C.Mat('brass')
    c = m.ramp(m.noise(50, 4), (0.12, 0.08, 0.015, 1), (0.25, 0.17, 0.035, 1), 0.3, 0.75)
    return m.done(m.grime(c, 0.75, 20), 0.4)


def rag(name, lo, hi):
    m = C.Mat(name)
    c = m.ramp(m.noise(80, 4), lo, hi, 0.3, 0.75)
    c = m.mix(c, m.ramp(m.noise(18, 6), (0.55, 0.52, 0.48, 1), (1, 1, 1, 1), 0.35, 0.7), 1.0, 'MULTIPLY')   # dirt
    return m.done(c, 0.9)


STEEL, BANDS, BLACK = C.old_steel(), C.band_steel(), C.black_metal()
WOOD = C.wood((0.4, 0.27, 0.17, 1), 7.0)
RUBBER, GREEN, BRASS = rubber(), green_paint(), brass()
RAGS = [rag('rag_red', (0.06, 0.013, 0.011, 1), (0.13, 0.03, 0.026, 1)),
        rag('rag_green', (0.028, 0.042, 0.024, 1), (0.06, 0.085, 0.045, 1)),
        rag('rag_grey', (0.035, 0.034, 0.031, 1), (0.075, 0.072, 0.065, 1)),
        rag('rag_tan', (0.05, 0.04, 0.025, 1), (0.1, 0.078, 0.05, 1))]

# ---- barrels (swing open): two thick painted pipes, collars, clamp bands, bead
for y in (-DY, DY):
    C.place(C.tube_pipe(R, 0.0125, 0.278, GREEN, BREACH, 20), (0.148, y, BORE_Z), X)
    C.place(C.ring(R, 0.016, 0.0025, BANDS, BREACH, 20), (0.41, y, BORE_Z), X)            # muzzle collars
    C.place(C.ring(R, 0.02, 0.003, GREEN, BREACH, 20), (0.148, y, BORE_Z), X)              # thread collars at the back
rib = C.box((0.24, 0.008, 0.007), BANDS, BREACH); rib.location = (0.28, 0, BORE_Z + R - 0.003)
for x in (0.215, 0.33):                                                                   # clamp bands round both
    pts = []
    for i in range(41):
        a = i / 40 * 2 * math.pi
        pts.append((x, math.cos(a) * (DY + R + 0.002), BORE_Z + math.sin(a) * (R + 0.002)))
    C.poly_tube(pts, 0.0028, BANDS, BREACH)
    C.place(C.cylinder(0.0032, 0.016, BLACK, BREACH, 6), (x, -(DY + R + 0.004), BORE_Z - 0.006), (0, 0, 1))   # band bolt
C.place(C.cylinder(0.0025, 0.009, BRASS, BREACH, 8), (0.405, 0, BORE_Z + R + 0.004), (0, 0, 1))  # brass bead
s = C.box((0.07, 0.02, 0.006), BANDS, BREACH); s.location = (0.185, 0, BORE_Z - R - 0.003)     # hinge strap

# ---- breech (stays): a pipe coupling round each barrel end on a back plate,
# side plates bolting the stock to it, firing pins, a spare brass shell on top
for y in (-DY, DY):
    C.place(C.cylinder(0.0215, 0.042, STEEL, MAIN, 20), (0.106, y, BORE_Z), X)
    for x in (0.106, 0.142):
        C.place(C.ring(0.0215, 0.005, 0.0016, BANDS, MAIN, 20), (x, y, BORE_Z), X)
    C.place(C.cylinder(0.004, 0.004, BLACK, MAIN, 10), (0.098, y, BORE_Z), (-1, 0, 0))   # nail firing pins
C.flat_xz([(0.094, BORE_Z + 0.02), (0.106, BORE_Z + 0.02), (0.106, 0.004), (0.094, 0.004)], 0.078, STEEL, MAIN, 0.002)
for side in (-1, 1):
    C.flat_xz([(0.03, 0.03), (0.13, 0.034), (0.13, 0.004), (0.03, 0.0)], 0.003, BANDS, MAIN, 0.001, y=side * 0.0215)
    for x, z in ((0.045, 0.01), (0.045, 0.024), (0.115, 0.012)):
        C.place(C.cylinder(0.0035, 0.004, BLACK, MAIN, 6, smooth=False), (x, side * 0.023, z), (0, side, 0))
C.place(C.cylinder(0.0105, 0.05, BRASS, MAIN, 16), (0.096, 0, BORE_Z + 0.034), X)        # brass shell lying on top
C.place(C.cylinder(0.0118, 0.006, BRASS, MAIN, 16), (0.09, 0, BORE_Z + 0.034), X)       # its rim
for x in (0.104, 0.138):                                                                  # wire holding it
    pts = [(x, 0.0125 * math.cos(a), BORE_Z + 0.034 + 0.0125 * math.sin(a)) for a in [i / 16 * 2 * math.pi for i in range(17)]]
    C.poly_tube(pts, 0.0011, BLACK, MAIN)
C.place(C.cylinder(0.0075, 0.06, BANDS, MAIN, 12), (0.152, -0.03, 0.012), (0, 1, 0))     # hinge knuckle

# ---- stock: one piece of wood up to the breech, wound in separate rag strips
TOP = [(0.1, 0.028), (0.04, 0.03), (-0.02, 0.026), (-0.06, 0.006), (-0.1, -0.008), (-0.17, -0.01), (-0.29, 0.016)]
BOT = [(0.1, -0.004), (0.0, -0.01), (-0.04, -0.045), (-0.07, -0.09), (-0.1, -0.1), (-0.13, -0.088), (-0.24, -0.114), (-0.29, -0.11)]
C.flat_xz(TOP + list(reversed(BOT)), 0.038, WOOD, MAIN, 0.006, segments=2)
C.flat_xz([(-0.29, 0.018), (-0.304, 0.019), (-0.304, -0.112), (-0.29, -0.112)], 0.04, RUBBER, MAIN, 0.003)


def edge(chain, x):
    for (x0, z0), (x1, z1) in zip(chain, chain[1:]):
        if x1 <= x <= x0: return z0 + (z1 - z0) * (x - x0) / (x1 - x0)
    return chain[-1][1]


x = -0.004
k = 0
while x > -0.278:
    w = random.uniform(0.028, 0.038)
    slant = 0.022
    if random.random() > 0.08:                                    # now and then a gap shows the wood
        xa, xb = x - w, x
        quad = [(xa + slant, edge(TOP, xa + slant) + 0.0012), (xb + slant, edge(TOP, xb + slant) + 0.0012),
                (xb, edge(BOT, xb) - 0.0012), (xa, edge(BOT, xa) - 0.0012)]
        C.flat_xz(quad, 0.0392, RAGS[(k + random.randint(0, 1)) % len(RAGS)], MAIN, 0.0062, segments=2)
        k += 1
    x -= w - random.uniform(0.003, 0.007)          # strips overlap a little

# ---- trigger guard (bent rod) and two triggers
C.poly_tube([(0.072, 0, -0.004), (0.07, 0, -0.03), (0.05, 0, -0.042), (0.02, 0, -0.044), (-0.008, 0, -0.036), (-0.01, 0, -0.012)],
            0.0028, BANDS, MAIN)
for x in (0.022, 0.038):
    C.poly_tube([(x, 0, -0.002), (x + 0.002, 0, -0.014), (x - 0.004, 0, -0.026)], 0.0022, BLACK, TRIGGER)

o, tris = C.join_and_bake(OUT, 'scrap_double')
C.renders(o, OUT, 'scrap_double',
          [((0.06, 0, -0.01), (0.15, -0.85, 0.15), 50),
           ((0.06, 0, -0.01), (-0.55, -0.55, 0.4), 50),
           ((0.12, 0, 0.04), (0.06, -0.24, 0.14), 50)],
          (math.radians(-90), 0, math.radians(-40)), 0.85)
print('BUILT scrap_double', tris, 'tris', flush=True)
