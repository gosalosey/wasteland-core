# Scrap pump shotgun (scrap_pump_shotgun): a pipe barrel over a pipe magazine
# tube, a receiver welded from sheet steel, a pump made from a block of wood
# wrapped in old inner tube sliding on two rods, a stock cut from a plank with
# a taped wrist, a tyre-rubber butt pad and spare shells strapped to the side.
# Built on the game's pump shotgun: the pump and its rods are on Gun_Cock1 (the
# pump animation slides it), the trigger on Gun_Trigger_Pr, the rest on
# Gun_Main_Bone. X forward; bore along z = 0.036 to the muzzle at x = 0.597;
# left hand at x = 0.358 (pump), right hand at (-0.084, -0.068) (wrist).
#   blender -b --python build_scrap_pump.py -- <tex folder> <out folder>
import bpy, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(31)
C.start(TEX)

MAIN, PUMP, TRIGGER = 'Gun_Main_Bone', 'Gun_Cock1', 'Gun_Trigger_Pr'
BORE_Z, MAG_Z = 0.036, 0.006
X = (1, 0, 0)


def rubber():
    m = C.Mat('rubber')
    c = m.ramp(m.noise(90, 3), (0.012, 0.012, 0.012, 1), (0.04, 0.04, 0.038, 1), 0.3, 0.75)
    c = m.mix(c, (0.09, 0.085, 0.08, 1), m.above(m.noise(25, 6), 0.68))     # dusty scuffs
    return m.done(c, 0.85)


def shell_mat():
    m = C.Mat('shells')
    sep = m.n.new('ShaderNodeSeparateXYZ'); m.l.new(m.tc, sep.inputs['Vector'])
    brass = m.n.new('ShaderNodeMath'); brass.operation = 'LESS_THAN'; brass.inputs[1].default_value = -0.247
    m.l.new(sep.outputs['X'], brass.inputs[0])
    red = m.ramp(m.noise(40, 3), (0.12, 0.01, 0.008, 1), (0.22, 0.02, 0.015, 1), 0.3, 0.7)
    c = m.mix(red, (0.2, 0.13, 0.04, 1), brass.outputs[0])
    return m.done(c, 0.5)


STEEL, BANDS, BLACK = C.old_steel(), C.band_steel(), C.black_metal()
WOOD = C.wood((0.45, 0.33, 0.22, 1), 7.0)
TAPE, RUBBER, SHELLS = C.tape((0.12, 0.12, 0.115, 1)), rubber(), shell_mat()

# ---- barrel and magazine tube
C.place(C.tube_pipe(0.0125, 0.0095, 0.45, STEEL, MAIN, 20), (0.15, 0, BORE_Z), X)
C.place(C.ring(0.0125, 0.012, 0.0025, BANDS, MAIN, 20), (0.585, 0, BORE_Z), X)          # muzzle collar
C.place(C.cylinder(0.011, 0.36, STEEL, MAIN, 18), (0.15, 0, MAG_Z), X)                  # magazine tube
C.place(C.cylinder(0.0125, 0.014, BANDS, MAIN, 8, smooth=False), (0.508, 0, MAG_Z), X)  # its end cap (hex)
for x in (0.47, 0.54):                                                                   # straps tying barrel to tube
    s = C.flat_xz([(x, BORE_Z + 0.015), (x + 0.012, BORE_Z + 0.015), (x + 0.012, MAG_Z - 0.013), (x, MAG_Z - 0.013)],
                  0.03, BANDS, MAIN, 0.002)
C.place(C.cylinder(0.002, 0.012, BLACK, MAIN, 6), (0.575, 0, BORE_Z + 0.012), (0, 0, 1))  # bead sight (a bolt)

# ---- receiver: welded box with a port, weld beads, bolts, a rear sight plate
rcv = [(-0.03, 0.058), (0.15, 0.054), (0.155, -0.012), (0.06, -0.02), (-0.03, -0.02)]
C.flat_xz(rcv, 0.042, STEEL, MAIN, 0.002)
port = C.box((0.05, 0.004, 0.018), RUBBER, MAIN); port.location = (0.11, -0.021, 0.035)  # ejection port
for i in range(14):                                                                      # weld beads along the seams
    for z in (0.054, -0.018):
        C.place(C.cylinder(0.0028, 0.003, BANDS, MAIN, 6), (-0.025 + i * 0.012, -0.021, z), (0, -1, 0))
for x, z in ((0.0, 0.0), (0.0, 0.04), (0.13, 0.0)):
    for y in (-0.022, 0.022):
        C.place(C.cylinder(0.0035, 0.003, BLACK, MAIN, 6, smooth=False), (x, y, z), (0, 1 if y > 0 else -1, 0))
C.flat_xz([(0.0, 0.058), (0.016, 0.058), (0.016, 0.072), (0.011, 0.072), (0.008, 0.066), (0.005, 0.072), (0.0, 0.072)],
          0.004, BANDS, MAIN)                                                            # rear notch sight

# ---- pump: wood block wrapped in inner tube, clamps, two action rods back to the receiver
C.place(C.cylinder(0.019, 0.13, WOOD, PUMP, 10), (0.3, 0, MAG_Z), X)
for i in range(6):                                                                        # inner tube wraps, overlapping
    C.place(C.ring(0.019, 0.022, 0.0028, RUBBER, PUMP, 14), (0.305 + i * 0.019 + random.uniform(-0.002, 0.002), 0, MAG_Z), X)
for x in (0.3, 0.42):
    C.place(C.ring(0.0218, 0.007, 0.0014, BANDS, PUMP, 16), (x, 0, MAG_Z), X)
for y in (-0.014, 0.014):
    C.place(C.cylinder(0.0024, 0.16, STEEL, PUMP, 8), (0.145, y, MAG_Z - 0.004), X)

# ---- stock: a plank cut to shape, taped wrist, tyre-rubber pad, spare shells
stock = [(-0.03, 0.05), (-0.05, 0.03), (-0.09, -0.01), (-0.15, -0.012), (-0.3, 0.012), (-0.3, -0.112),
         (-0.25, -0.112), (-0.14, -0.082), (-0.11, -0.086), (-0.075, -0.1), (-0.05, -0.06), (-0.03, -0.02)]
C.flat_xz(stock, 0.036, WOOD, MAIN, 0.005, segments=2)
def lerp(a, b, x):
    return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])


for i in range(5):                                                                        # tape wound round the wrist
    x0 = -0.088 + i * 0.0075
    x1 = x0 + 0.0068
    top0, top1 = lerp((-0.09, -0.01), (-0.05, 0.03), x0), lerp((-0.09, -0.01), (-0.05, 0.03), x1)
    bot0, bot1 = lerp((-0.075, -0.1), (-0.05, -0.06), x0 + 0.012), lerp((-0.075, -0.1), (-0.05, -0.06), x1 + 0.012)
    C.flat_xz([(x0, top0 + 0.0015), (x1, top1 + 0.0015), (x1 + 0.012, bot1 - 0.0015), (x0 + 0.012, bot0 - 0.0015)],
              0.0395, TAPE, MAIN, 0.0012)
pad = C.flat_xz([(-0.3, 0.014), (-0.318, 0.016), (-0.318, -0.114), (-0.3, -0.114)], 0.04, RUBBER, MAIN, 0.002)
for i in range(4):                                                                        # tread grooves on the pad
    g = C.box((0.002, 0.042, 0.004), BLACK, MAIN); g.location = (-0.318, 0, -0.01 - i * 0.03)
strap = C.box((0.014, 0.004, 0.046), RUBBER, MAIN); strap.location = (-0.215, -0.0315, -0.03)
for i in range(3):                                                                        # shells under the strap
    C.place(C.cylinder(0.0055, 0.068, SHELLS, MAIN, 12), (-0.252, -0.0245, -0.042 + i * 0.012), X)

# ---- trigger guard (bent flat bar) and trigger
C.flat_xz([(0.06, -0.018), (0.055, -0.05), (0.02, -0.058), (-0.035, -0.052), (-0.04, -0.045), (-0.012, -0.048),
           (0.02, -0.052), (0.046, -0.046), (0.05, -0.018)], 0.008, BANDS, MAIN, 0.001)
C.poly_tube([(0.017, 0, -0.016), (0.019, 0, -0.026), (0.014, 0, -0.038)], 0.0025, BLACK, TRIGGER)

o, tris = C.join_and_bake(OUT, 'scrap_pump')
C.renders(o, OUT, 'scrap_pump',
          [((0.14, 0, -0.02), (0.15, -0.95, 0.15), 50),
           ((0.14, 0, -0.02), (-0.6, -0.6, 0.4), 50),
           ((0.1, 0, 0.0), (0.12, -0.32, 0.12), 50)],
          (math.radians(-90), 0, math.radians(18)), 0.95)
print('BUILT scrap_pump', tris, 'tris', flush=True)
