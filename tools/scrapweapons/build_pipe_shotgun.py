# Pipe shotgun (scrap_pipe_shotgun): a single-shot break-open gun made from
# plumbing. Built on the game's sawed-off double-barrel layout: the barrel is
# on the hinge bone (Gun_Breach) so it swings open when reloading, the trigger
# on Gun_Trigger_Pr, everything else on Gun_Main_Bone. X is forward, the bore
# runs along z = 0.046 to the muzzle at x = 0.423.
#   blender -b --python build_pipe_shotgun.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(11)
C.start(TEX)

MAIN, BREACH, TRIGGER = 'Gun_Main_Bone', 'Gun_Breach', 'Gun_Trigger_Pr'
PIPE, RUST, WOOD, TAPE, BLACK = C.galvanized(0.55), C.rusty(), C.wood((0.72, 0.6, 0.45, 1), 7.0), C.tape(), C.black_metal()
BORE_Z = 0.046
X = (1, 0, 0)

# ---- barrel (swings open): hollow pipe, tape forend, clamp, front sight, hinge strap
C.place(C.tube_pipe(0.0145, 0.0105, 0.273, PIPE, BREACH, 18), (0.152, 0, BORE_Z), X)
C.place(C.cylinder(0.0168, 0.016, PIPE, BREACH, 18), (0.152, 0, BORE_Z), X)            # thread collar at the back
C.place(C.ring(0.0146, 0.075, 0.0016, TAPE, BREACH, 20), (0.285, 0, BORE_Z), X)       # duct-tape forend
for x in (0.30, 0.325, 0.345):                                                          # tape edges, a bit lumpy
    C.place(C.ring(0.0160, 0.004, 0.0007, TAPE, BREACH, 20), (x + random.uniform(-0.003, 0.003), 0, BORE_Z), X)
C.place(C.ring(0.0146, 0.007, 0.0012, RUST, BREACH, 20), (0.205, 0, BORE_Z), X)       # hose clamp
b = C.box((0.008, 0.005, 0.006), RUST, BREACH); b.location = (0.209, 0.012, BORE_Z + 0.006)   # its screw housing
C.place(C.cylinder(0.0018, 0.012, BLACK, BREACH, 6), (0.41, 0, BORE_Z + 0.0135), (0, 0, 1))   # bolt as front sight
s = C.box((0.06, 0.012, 0.004), RUST, BREACH); s.location = (0.18, 0, BORE_Z - 0.0165)         # hinge strap under the barrel

# ---- breech (stays): coupling, end cap, firing-pin nail, hinge knuckle
C.place(C.cylinder(0.0215, 0.05, PIPE, MAIN, 20), (0.102, 0, BORE_Z), X)               # coupling the shell sits in
C.place(C.cylinder(0.0195, 0.024, PIPE, MAIN, 20), (0.078, 0, BORE_Z), X)              # end cap
for i in range(8):                                                                      # cap's octagon flats
    a = i * math.pi / 4
    f = C.box((0.022, 0.004, 0.0016), PIPE, MAIN)
    f.location = (0.09, math.cos(a) * 0.0198, BORE_Z + math.sin(a) * 0.0198); f.rotation_euler = (a, 0, 0)
C.place(C.cylinder(0.0045, 0.003, BLACK, MAIN, 10), (0.075, 0, BORE_Z), (-1, 0, 0))    # nail head (firing pin)
C.place(C.cylinder(0.0015, 0.012, BLACK, MAIN, 6), (0.072, 0, BORE_Z), (-1, 0, 0))
C.place(C.cylinder(0.006, 0.034, RUST, MAIN, 12), (0.154, -0.017, 0.012), (0, 1, 0))   # hinge knuckle
C.place(C.cylinder(0.0025, 0.04, BLACK, MAIN, 8), (0.154, -0.02, 0.012), (0, 1, 0))    # hinge pin
k = C.box((0.03, 0.03, 0.02), RUST, MAIN); k.location = (0.14, 0, 0.02)                 # bracket from cap to knuckle

# ---- spine and grip: flat bar, sawn 2x4 grip hung under its back end, side plates, wire
sp = C.box((0.24, 0.012, 0.006), RUST, MAIN); sp.location = (0.03, 0, 0.022)
tilt = math.radians(15)                                   # grip leans back like a pistol grip
top = Vector((-0.072, 0, 0.019))
g = C.box((0.04, 0.03, 0.12), WOOD, MAIN, bevel=0.003)
g.rotation_euler = (0, tilt, 0); g.location = top + Vector((-0.06 * math.sin(tilt), 0, -0.06 * math.cos(tilt)))
for y in (-0.0162, 0.0162):                               # steel side plates bolting grip to the bar
    pl = C.box((0.042, 0.0018, 0.036), RUST, MAIN); pl.location = (-0.07, y, 0.008)
    for bx in (-0.082, -0.058):
        C.place(C.cylinder(0.003, 0.002, BLACK, MAIN, 6), (bx, y, 0.006), (0, 1 if y > 0 else -1, 0))
pts = []
for i in range(70):                                       # wire lashed round bar and grip top
    t = i / 69; a = t * 2 * math.pi * 5
    pts.append((-0.05 + t * 0.022, 0.0185 * math.cos(a), 0.012 + 0.0135 * math.sin(a)))
C.poly_tube(pts, 0.0009, BLACK, MAIN)

# ---- trigger: a bent rod on its own bone, and a guard of bent wire
C.poly_tube([(0.03, 0, 0.018), (0.031, 0, 0.0), (0.026, 0, -0.016), (0.018, 0, -0.026)], 0.0024, BLACK, TRIGGER)
C.poly_tube([(0.06, 0, 0.019), (0.058, 0, -0.03), (0.035, 0, -0.042), (-0.02, 0, -0.04), (-0.058, 0, -0.022)], 0.0016, RUST, MAIN)

o, tris = C.join_and_bake(OUT, 'pipe_shotgun')
C.renders(o, OUT, 'pipe_shotgun',
          [((0.17, 0, 0.0), (0.25, -0.62, 0.2), 50),
           ((0.17, 0, 0.0), (-0.45, -0.4, 0.3), 50),
           ((0.1, 0, 0.02), (0.08, -0.22, 0.1), 50)],
          (math.radians(-90), 0, math.radians(18)), 0.6)
print('BUILT pipe_shotgun', tris, 'tris', flush=True)
