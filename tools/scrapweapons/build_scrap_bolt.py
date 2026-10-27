# Scrap bolt rifle (scrap_bolt_rifle): a long pipe barrel strapped to a full
# wooden stock, a thick pipe receiver with a working bolt (body on Gun_Cock2,
# handle on Gun_Cock1, so the bolt animation moves them), a tin box magazine,
# washer-and-bolt sights and a cracked stock patched with a steel plate.
# Built on the game's precision rifle: X forward, bore along z = 0.041 to the
# muzzle at x = 0.801; right hand (-0.073, -0.067), left hand x = 0.265.
#   blender -b --python build_scrap_bolt.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(41)
C.start(TEX)

MAIN, BOLT, HANDLE, TRIGGER = 'Gun_Main_Bone', 'Gun_Cock2', 'Gun_Cock1', 'Gun_Trigger_Pr'
BORE_Z = 0.041
X = (1, 0, 0)

STEEL, BANDS, BLACK = C.old_steel(), C.band_steel(), C.black_metal()
WOOD = C.wood((0.42, 0.3, 0.2, 1), 7.0)
TAPE = C.tape((0.12, 0.12, 0.115, 1))

# ---- stock and forend in one piece of wood
stock = [(0.43, 0.014), (0.42, 0.027), (-0.03, 0.027), (-0.06, 0.02), (-0.11, -0.008), (-0.2, -0.006), (-0.322, 0.028),
         (-0.322, -0.098), (-0.27, -0.104), (-0.14, -0.078), (-0.1, -0.098), (-0.065, -0.104), (-0.04, -0.06),
         (-0.01, -0.02), (0.18, -0.008), (0.42, 0.0)]
C.flat_xz(stock, 0.032, WOOD, MAIN, 0.005, segments=2)
C.flat_xz([(-0.322, 0.03), (-0.334, 0.03), (-0.334, -0.1), (-0.322, -0.1)], 0.034, TAPE, MAIN, 0.002)   # taped butt end
for side in (-1, 1):                                                                      # crack patched with a plate
    C.flat_xz([(-0.235, -0.02), (-0.17, -0.025), (-0.165, -0.06), (-0.23, -0.058)], 0.0016, BANDS, MAIN, y=side * 0.0168)
    for x, z in ((-0.225, -0.028), (-0.175, -0.032), (-0.175, -0.054), (-0.225, -0.052)):
        C.place(C.cylinder(0.0022, 0.002, BLACK, MAIN, 6), (x, side * 0.0176, z), (0, side, 0))

# ---- receiver: thick pipe with a coupling at the front, rear sight washer
C.place(C.cylinder(0.0165, 0.21, STEEL, MAIN, 20), (-0.03, 0, BORE_Z), X)
C.place(C.cylinder(0.0145, 0.022, BANDS, MAIN, 20), (0.18, 0, BORE_Z), X)
for x in (-0.01, 0.16):                                                                   # straps holding it to the stock
    C.flat_xz([(x, BORE_Z + 0.019), (x + 0.01, BORE_Z + 0.019), (x + 0.01, 0.012), (x, 0.012)], 0.036, BANDS, MAIN, 0.0015)
C.place(C.cylinder(0.0025, 0.012, BLACK, MAIN, 6), (0.17, 0, BORE_Z + 0.016), (0, 0, 1))        # rear sight post
C.place(C.ring(0.0035, 0.002, 0.003, BANDS, MAIN, 12), (0.17, -0.001, BORE_Z + 0.03), (0, 1, 0))  # washer peep

# ---- bolt (slides back) and handle (turns up)
C.place(C.cylinder(0.0068, 0.14, BLACK, BOLT, 12), (-0.02, 0, BORE_Z + 0.013), X)
C.place(C.cylinder(0.0092, 0.016, STEEL, BOLT, 12), (-0.038, 0, BORE_Z + 0.006), X)        # bolt shroud at the back
C.poly_tube([(0.048, -0.006, BORE_Z + 0.014), (0.05, -0.04, BORE_Z + 0.01), (0.047, -0.056, BORE_Z - 0.004)], 0.0032, STEEL, HANDLE)
C.place(C.cylinder(0.0072, 0.012, BANDS, HANDLE, 6, smooth=False), (0.047, -0.056, BORE_Z - 0.01), (0, 0, 1))  # nut for a knob

# ---- barrel: long pipe, collar, straps to the forend, front sight
C.place(C.tube_pipe(0.0105, 0.0072, 0.605, STEEL, MAIN, 18), (0.198, 0, BORE_Z), X)
C.place(C.ring(0.0105, 0.016, 0.002, BANDS, MAIN, 18), (0.786, 0, BORE_Z), X)
for x in (0.25, 0.4):
    C.flat_xz([(x, BORE_Z + 0.013), (x + 0.009, BORE_Z + 0.013), (x + 0.009, 0.004), (x, 0.004)], 0.035, BANDS, MAIN, 0.0015)
    C.place(C.cylinder(0.0025, 0.004, BLACK, MAIN, 6), (x + 0.0045, -0.0182, 0.02), (0, -1, 0))
pts = []
for i in range(60):                                                                       # wire binding at the forend tip
    t = i / 59; a = t * 2 * math.pi * 5
    pts.append((0.405 + t * 0.018, 0.0185 * math.cos(a), 0.024 + 0.022 * math.sin(a)))
C.poly_tube(pts, 0.0009, BLACK, MAIN)
C.flat_xz([(0.775, BORE_Z + 0.008), (0.785, BORE_Z + 0.008), (0.783, BORE_Z + 0.024), (0.777, BORE_Z + 0.024)], 0.003, BANDS, MAIN)

# ---- tin box magazine, trigger guard, trigger
C.flat_xz([(0.088, -0.006), (0.135, -0.006), (0.132, -0.052), (0.092, -0.052)], 0.024, STEEL, MAIN, 0.0015)
for z in (-0.02, -0.035):                                                                 # pressed ribs
    r = C.box((0.046, 0.026, 0.002), BANDS, MAIN); r.location = (0.111, 0, z)
C.flat_xz([(0.07, -0.012), (0.066, -0.044), (0.03, -0.05), (-0.01, -0.04), (-0.015, -0.028), (0.0, -0.034),
           (0.03, -0.042), (0.058, -0.038), (0.062, -0.012)], 0.007, BANDS, MAIN, 0.001)
C.poly_tube([(0.03, 0, -0.012), (0.032, 0, -0.024), (0.026, 0, -0.036)], 0.0024, BLACK, TRIGGER)

o, tris = C.join_and_bake(OUT, 'scrap_bolt')
C.renders(o, OUT, 'scrap_bolt',
          [((0.24, 0, -0.02), (0.15, -1.1, 0.18), 50),
           ((0.24, 0, -0.02), (-0.7, -0.7, 0.45), 50),
           ((0.05, 0, 0.02), (0.1, -0.3, 0.12), 50)],
          (math.radians(-90), 0, math.radians(18)), 1.15)
print('BUILT scrap_bolt', tris, 'tris', flush=True)
