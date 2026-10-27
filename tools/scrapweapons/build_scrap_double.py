# Improvised double-barrel (scrap_double_barrel): two pipes side by side
# with a welded rib and hose clamps, a wooden forend under them, a heavy
# breech plate with twin nail firing pins and two bent-bolt hammers, a door
# hinge, a sawn-down stock with an inner-tube recoil pad. Built on the game's
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
R, DY = 0.0128, 0.0131          # barrel radius, half the spacing


def rubber():
    m = C.Mat('rubber')
    c = m.ramp(m.noise(90, 3), (0.01, 0.01, 0.01, 1), (0.035, 0.035, 0.033, 1), 0.3, 0.75)
    return m.done(c, 0.85)


STEEL, BANDS, BLACK = C.old_steel(), C.band_steel(), C.black_metal()
WOOD = C.wood((0.4, 0.27, 0.17, 1), 7.0)
RUBBER = rubber()

# ---- barrels (swing open): two hollow pipes, welded rib, clamps, forend, bead
for y in (-DY, DY):
    C.place(C.tube_pipe(R, 0.0095, 0.276, STEEL, BREACH, 18), (0.15, y, BORE_Z), X)
rib = C.box((0.26, 0.006, 0.006), BANDS, BREACH); rib.location = (0.29, 0, BORE_Z + R - 0.002)
for x in (0.2, 0.37, 0.415):                                                              # clamps round both barrels
    bm_pts = []
    for i in range(33):
        a = i / 32 * 2 * math.pi
        y = math.cos(a) * (DY + R + 0.0015); z = math.sin(a) * (R + 0.0015)
        bm_pts.append((x, y, BORE_Z + z))
    C.poly_tube(bm_pts, 0.0022, BANDS, BREACH)
C.place(C.cylinder(0.0022, 0.008, BANDS, BREACH, 8), (0.41, 0, BORE_Z + R + 0.004), (0, 0, 1))  # bead
C.flat_xz([(0.25, BORE_Z - R + 0.003), (0.36, BORE_Z - R + 0.003), (0.355, BORE_Z - R - 0.02), (0.26, BORE_Z - R - 0.022)],
          0.032, WOOD, BREACH, 0.004, segments=2)                                        # forend
s = C.box((0.07, 0.016, 0.005), BANDS, BREACH); s.location = (0.185, 0, BORE_Z - R - 0.003)  # hinge strap

# ---- breech (stays): steel plate, twin firing pins, two hammers, hinge knuckle
C.flat_xz([(0.12, BORE_Z + 0.022), (0.15, BORE_Z + 0.022), (0.15, 0.006), (0.12, 0.006)], 0.06, STEEL, MAIN, 0.002)
for y in (-DY, DY):
    C.place(C.cylinder(0.004, 0.003, BLACK, MAIN, 10), (0.12, y, BORE_Z), (-1, 0, 0))
    C.poly_tube([(0.115, y, BORE_Z + 0.004), (0.098, y, BORE_Z + 0.012), (0.088, y, BORE_Z + 0.03), (0.094, y, BORE_Z + 0.04)],
                0.0036, BLACK, MAIN)                                                      # bent bolt hammer
    C.place(C.cylinder(0.0055, 0.006, BANDS, MAIN, 6, smooth=False), (0.094, y, BORE_Z + 0.038), (0, 0, 1))  # nut on its spur
C.place(C.cylinder(0.0065, 0.044, BANDS, MAIN, 12), (0.152, -0.022, 0.012), (0, 1, 0))
k = C.box((0.034, 0.04, 0.02), STEEL, MAIN, bevel=0.002); k.location = (0.135, 0, 0.016)

# ---- frame and sawn-down stock
C.flat_xz([(0.12, 0.03), (0.04, 0.032), (-0.01, 0.026), (-0.01, -0.004), (0.12, -0.002)], 0.03, STEEL, MAIN, 0.002)
stock = [(-0.01, 0.03), (-0.04, 0.024), (-0.09, -0.008), (-0.16, -0.01), (-0.22, 0.0), (-0.22, -0.1), (-0.17, -0.098),
         (-0.11, -0.084), (-0.08, -0.098), (-0.06, -0.08), (-0.035, -0.04), (-0.01, -0.006)]
C.flat_xz(stock, 0.034, WOOD, MAIN, 0.005, segments=2)
C.flat_xz([(-0.22, 0.002), (-0.236, 0.003), (-0.236, -0.102), (-0.22, -0.102)], 0.038, RUBBER, MAIN, 0.003)   # inner-tube pad
for i in range(4):
    g = C.box((0.003, 0.04, 0.0025), BLACK, MAIN); g.location = (-0.236, 0, -0.012 - i * 0.026)
pts = []
for i in range(70):                                                                       # wire binding frame to stock
    t = i / 69; a = t * 2 * math.pi * 6
    pts.append((-0.03 + t * 0.026, 0.0195 * math.cos(a), 0.012 + 0.019 * math.sin(a)))
C.poly_tube(pts, 0.001, BLACK, MAIN)

# ---- trigger guard and two triggers
C.flat_xz([(0.07, -0.002), (0.066, -0.036), (0.03, -0.046), (-0.012, -0.04), (-0.016, -0.03), (0.0, -0.033),
           (0.03, -0.038), (0.058, -0.032), (0.062, -0.002)], 0.008, BANDS, MAIN, 0.001)
for x in (0.022, 0.038):
    C.poly_tube([(x, 0, -0.002), (x + 0.002, 0, -0.014), (x - 0.004, 0, -0.026)], 0.0022, BLACK, TRIGGER)

o, tris = C.join_and_bake(OUT, 'scrap_double')
C.renders(o, OUT, 'scrap_double',
          [((0.1, 0, 0.0), (0.15, -0.72, 0.15), 50),
           ((0.1, 0, 0.0), (-0.5, -0.45, 0.35), 50),
           ((0.1, 0, 0.03), (0.06, -0.22, 0.12), 50)],
          (math.radians(-90), 0, math.radians(18)), 0.75)
print('BUILT scrap_double', tris, 'tris', flush=True)
