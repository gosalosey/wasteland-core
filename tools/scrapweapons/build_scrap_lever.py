# Scrap lever rifle (scrap_lever_rifle): a long octagonal barrel over a tube
# magazine, a receiver with tarnished brass side plates and a loading gate, a
# big loop lever under the wrist, an exposed hammer, a saddle ring, buckhorn
# sights and a wooden stock and forend studded with brass tacks.
# The game has no lever-action, so it is built on the precision rifle's frame
# (X forward, bore along z = 0.041 to the muzzle at x = 0.801; right hand
# (-0.073, -0.067), left hand x = 0.265). The lever stays on Gun_Main_Bone
# (the precision rifle's bolt bones would swing it oddly); trigger on Gun_Trigger_Pr.
#   blender -b --python build_scrap_lever.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(71)
C.start(TEX)

MAIN, TRIGGER = 'Gun_Main_Bone', 'Gun_Trigger_Pr'
BORE_Z, MAG_Z = 0.041, 0.019
X = (1, 0, 0)


def brass():
    m = C.Mat('brass')
    c = m.ramp(m.noise(50, 6), (0.07, 0.045, 0.012, 1), (0.16, 0.11, 0.035, 1), 0.3, 0.75)
    c = m.mix(c, (0.03, 0.04, 0.025, 1), m.above(m.noise(12, 8), 0.62))     # green-black tarnish
    return m.done(m.grime(c, 0.65, 20), 0.45)


STEEL, BANDS, BLACK, BRASS = C.old_steel(), C.band_steel(), C.black_metal(), brass()
WOOD = C.wood((0.38, 0.25, 0.15, 1), 7.0)

# ---- barrel (octagonal), tube magazine, bands
C.place(C.cylinder(0.0115, 0.665, STEEL, MAIN, 8, smooth=False), (0.138, 0, BORE_Z), X)
C.place(C.cylinder(0.0045, 0.004, BLACK, MAIN, 12), (0.8, 0, BORE_Z), X)              # bore (dark)
C.place(C.cylinder(0.0085, 0.56, STEEL, MAIN, 16), (0.14, 0, MAG_Z), X)
C.place(C.cylinder(0.0095, 0.01, BANDS, MAIN, 16), (0.7, 0, MAG_Z), X)                # tube cap
for x in (0.39, 0.67):
    C.flat_xz([(x, BORE_Z + 0.013), (x + 0.012, BORE_Z + 0.013), (x + 0.012, MAG_Z - 0.01), (x, MAG_Z - 0.01)],
              0.026, BANDS, MAIN, 0.002)
C.flat_xz([(0.775, BORE_Z + 0.01), (0.787, BORE_Z + 0.01), (0.785, BORE_Z + 0.022), (0.778, BORE_Z + 0.022)], 0.003, BRASS, MAIN)  # front blade
C.flat_xz([(0.24, BORE_Z + 0.01), (0.25, BORE_Z + 0.01), (0.25, BORE_Z + 0.027), (0.247, BORE_Z + 0.022), (0.243, BORE_Z + 0.022),
           (0.24, BORE_Z + 0.027)], 0.024, BANDS, MAIN)                                                                          # buckhorn rear

# ---- receiver: steel core, brass side plates, loading gate, hammer, saddle ring
rcv = [(-0.035, 0.058), (0.142, 0.056), (0.145, 0.0), (0.06, -0.006), (-0.035, -0.004)]
C.flat_xz(rcv, 0.036, STEEL, MAIN, 0.002)
for side in (-1, 1):
    C.flat_xz([(-0.028, 0.05), (0.132, 0.05), (0.135, 0.004), (-0.028, 0.004)], 0.0016, BRASS, MAIN, 0.0006, y=side * 0.0186)
    for x, z in ((-0.018, 0.04), (0.12, 0.04), (0.05, 0.012)):
        C.place(C.cylinder(0.0026, 0.0018, STEEL, MAIN, 8), (x, side * 0.0196, z), (0, side, 0))     # screw heads
gate = C.flat_xz([(0.08, 0.035), (0.118, 0.035), (0.118, 0.018), (0.08, 0.018)], 0.002, BLACK, MAIN, y=-0.0198)
C.poly_tube([(-0.03, 0, 0.05), (-0.04, 0, 0.066), (-0.055, 0, 0.074), (-0.064, 0, 0.072)], 0.0042, BLACK, MAIN)   # hammer spur
C.place(C.ring(0.009, 0.003, 0.0022, BANDS, MAIN, 16), (0.06, 0.0205, 0.03), (0, 1, 0))                        # saddle ring
C.place(C.cylinder(0.003, 0.004, BANDS, MAIN, 8), (0.06, 0.0185, 0.03), (0, 1, 0))

# ---- lever: trigger guard and a big finger loop under the wrist
lever = [(0.07, 0, -0.004), (0.07, 0, -0.028), (0.052, 0, -0.042), (0.0, 0, -0.045), (-0.05, 0, -0.07), (-0.095, 0, -0.091),
         (-0.103, 0, -0.084), (-0.1, 0, -0.072), (-0.07, 0, -0.055), (-0.045, 0, -0.022), (-0.03, 0, -0.004)]
C.poly_tube(lever, 0.0034, STEEL, MAIN)
C.poly_tube([(0.03, 0, -0.004), (0.032, 0, -0.018), (0.027, 0, -0.03)], 0.0024, BLACK, TRIGGER)

# ---- stock and forend, brass tacks
stock = [(-0.035, 0.05), (-0.06, 0.03), (-0.11, -0.006), (-0.2, -0.004), (-0.322, 0.026), (-0.322, -0.1),
         (-0.27, -0.108), (-0.15, -0.085), (-0.11, -0.072), (-0.07, -0.05), (-0.035, -0.006)]
C.flat_xz(stock, 0.032, WOOD, MAIN, 0.005, segments=2)
C.flat_xz([(-0.322, 0.027), (-0.33, 0.027), (-0.33, -0.1), (-0.322, -0.1)], 0.034, BANDS, MAIN, 0.002)   # steel butt plate
C.flat_xz([(0.165, 0.032), (0.38, 0.03), (0.385, 0.02), (0.38, 0.004), (0.165, 0.004)], 0.026, WOOD, MAIN, 0.004, segments=2)
for side in (-1, 1):                                                                      # tacks in a diamond and a row
    for x, z in ((-0.2, -0.03), (-0.215, -0.045), (-0.185, -0.045), (-0.2, -0.06), (-0.26, -0.02), (-0.26, -0.08),
                 (0.2, 0.017), (0.25, 0.017), (0.3, 0.017), (0.35, 0.017)):
        y = side * (0.0165 if x < 0 else 0.0135)
        C.place(C.cylinder(0.0028, 0.0016, BRASS, MAIN, 10), (x, y, z), (0, side, 0))

o, tris = C.join_and_bake(OUT, 'scrap_lever')
C.renders(o, OUT, 'scrap_lever',
          [((0.24, 0, -0.02), (0.15, -1.1, 0.18), 50),
           ((0.24, 0, -0.02), (-0.7, -0.7, 0.45), 50),
           ((0.0, 0, 0.0), (0.12, -0.32, 0.1), 50)],
          (math.radians(-90), 0, math.radians(18)), 1.15)
print('BUILT scrap_lever', tris, 'tris', flush=True)
