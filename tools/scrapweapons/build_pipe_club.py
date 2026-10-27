# Pipe club (scrap_pipe_club): a length of steel pipe with a heavy cast-iron
# tee screwed on top as a hammer head (caps on both ends), a coupling below
# it with bolts screwed through, a rubber bike grip and cord above it. Built
# on the game's crowbar: same length (z -0.157 .. 0.33), head at the top
# reaching forward (+X), everything on Gun_Main_Bone.
#   blender -b --python build_pipe_club.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(53)
C.start(TEX)
MAIN = 'Gun_Main_Bone'
Z = (0, 0, 1)


def cast_iron():
    """Dark cast iron with rust and old blood on the striking ends."""
    m = C.Mat('iron')
    base = m.ramp(m.noise(30, 8), (0.02, 0.018, 0.016, 1), (0.06, 0.052, 0.045, 1), 0.3, 0.75)
    rust = m.mix(m.tex('Rust004', 28.0), (0.45, 0.4, 0.36, 1), 1.0, 'MULTIPLY')
    c = m.mix(base, rust, m.above(m.noise(10, 8), 0.55))
    c = m.mix(c, (0.07, 0.008, 0.006, 1), m.above(m.noise(14, 8), 0.6))
    return m.done(m.grime(c, 0.7, 18), 0.6)


def cord():
    m = C.Mat('cord')
    c = m.ramp(m.noise(120, 3), (0.03, 0.025, 0.017, 1), (0.065, 0.055, 0.04, 1), 0.3, 0.7)
    return m.done(m.grime(c, 0.6, 15), 0.9)


def grip():
    m = C.Mat('grip')
    c = m.ramp(m.noise(150, 2), (0.01, 0.01, 0.01, 1), (0.035, 0.035, 0.033, 1), 0.3, 0.75)
    return m.done(c, 0.85)


STEEL, BANDS, BLACK = C.old_steel(), C.band_steel(), C.black_metal()
IRON, CORD, GRIP = cast_iron(), cord(), grip()

# ---- shaft: pipe from the butt to the tee
C.place(C.tube_pipe(0.0135, 0.0098, 0.44, STEEL, MAIN, 18), (0, 0, -0.152), Z)
C.place(C.cylinder(0.0155, 0.008, BANDS, MAIN, 8, smooth=False), (0, 0, -0.157), Z)       # hex plug in the butt

# ---- bike grip: ribbed rubber over the bottom of the pipe, flared end
C.place(C.cylinder(0.0168, 0.12, GRIP, MAIN, 18), (0, 0, -0.145), Z)
for i in range(10):
    C.place(C.ring(0.0168, 0.004, 0.0012, GRIP, MAIN, 18), (0, 0, -0.135 + i * 0.011), Z)
C.place(C.cylinder(0.02, 0.008, GRIP, MAIN, 18, r2=0.0168), (0, 0, -0.149), Z)

# ---- cord wound above the grip
pts = []
for i in range(120):
    t = i / 119; a = t * 2 * math.pi * 14
    pts.append((0.0148 * math.cos(a), 0.0148 * math.sin(a), -0.022 + t * 0.06))
C.poly_tube(pts, 0.0016, CORD, MAIN)

# ---- coupling with bolts screwed through, under the head
C.place(C.cylinder(0.0185, 0.04, IRON, MAIN, 20), (0, 0, 0.22), Z)
for z in (0.228, 0.248):
    C.place(C.ring(0.0185, 0.004, 0.0015, IRON, MAIN, 20), (0, 0, z), Z)
for k, a in enumerate((0.3, 2.4, 4.4)):
    d = Vector((math.cos(a), math.sin(a), 0))
    z = 0.232 + (k % 2) * 0.012
    C.place(C.cylinder(0.003, 0.034, BLACK, MAIN, 6), d * 0.012 + Vector((0, 0, z)), d)          # bolt shank sticking out
    C.place(C.cylinder(0.006, 0.005, BANDS, MAIN, 6, smooth=False), d * 0.0185 + Vector((0, 0, z)), d)   # nut

# ---- tee head: vertical branch on the pipe, run across (along X), caps both ends
C.place(C.cylinder(0.021, 0.04, IRON, MAIN, 20), (0, 0, 0.26), Z)
C.place(C.cylinder(0.0225, 0.11, IRON, MAIN, 20), (-0.025, 0, 0.308), (1, 0, 0))
for x, d in ((-0.025, -1), (0.085, 1)):
    C.place(C.ring(0.0225, 0.006, 0.002, IRON, MAIN, 20), (x if d > 0 else x - 0.0, 0, 0.308), (d, 0, 0))
    C.place(C.cylinder(0.0205, 0.014, BANDS, MAIN, 8, smooth=False), (x, 0, 0.308), (d, 0, 0))   # hex caps
# a bolt hammered into the front cap as a spike
C.place(C.cylinder(0.0035, 0.022, BLACK, MAIN, 6, r2=0.001), (0.099, 0, 0.308), (1, 0, 0))

o, tris = C.join_and_bake(OUT, 'pipe_club')
C.renders(o, OUT, 'pipe_club',
          [((0.02, 0, 0.09), (0.2, -0.75, 0.15), 50),
           ((0.02, 0, 0.09), (-0.5, -0.5, 0.4), 50),
           ((0.03, 0, 0.27), (0.12, -0.25, 0.07), 50)],
          (math.radians(-90), 0, math.radians(-45)), 0.58)
print('BUILT pipe_club', tris, 'tris', flush=True)
