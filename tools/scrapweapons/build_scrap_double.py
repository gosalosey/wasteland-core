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


def cloth_wrap():
    """Strips of mixed rags wound round the stock: faded red, pale green, grey."""
    m = C.Mat('cloth')
    w = m.n.new('ShaderNodeTexWave'); w.bands_direction = 'DIAGONAL'
    w.inputs['Scale'].default_value = 11.0; w.inputs['Distortion'].default_value = 3.5; w.inputs['Detail'].default_value = 2.0
    m.l.new(m.tc, w.inputs['Vector'])
    pick = m.n.new('ShaderNodeTexNoise'); pick.inputs['Scale'].default_value = 7.0
    m.l.new(m.tc, pick.inputs['Vector'])
    red = m.ramp(m.noise(70, 3), (0.11, 0.025, 0.025, 1), (0.22, 0.06, 0.055, 1), 0.3, 0.7)
    green = m.ramp(m.noise(70, 3), (0.05, 0.075, 0.045, 1), (0.1, 0.14, 0.08, 1), 0.3, 0.7)
    grey = m.ramp(m.noise(70, 3), (0.06, 0.058, 0.052, 1), (0.13, 0.125, 0.11, 1), 0.3, 0.7)
    c = m.mix(red, green, m.above(pick.outputs['Fac'], 0.5))
    c = m.mix(c, grey, m.above(pick.outputs['Fac'], 0.62))
    seam = m.ramp(w.outputs['Fac'], (0.45, 0.45, 0.45, 1), (1, 1, 1, 1), 0.08, 0.2)    # dark line between strips
    c = m.mix(c, seam, 1.0, 'MULTIPLY')
    return m.done(m.grime(c, 0.6, 12), 0.9)


STEEL, BANDS, BLACK = C.old_steel(), C.band_steel(), C.black_metal()
WOOD = C.wood((0.4, 0.27, 0.17, 1), 7.0)
RUBBER, GREEN, BRASS, CLOTH = rubber(), green_paint(), brass(), cloth_wrap()

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

# ---- breech (stays): chunky clamp block with bolts, firing pins, a spare brass shell on top
C.flat_xz([(0.1, BORE_Z + 0.026), (0.147, BORE_Z + 0.026), (0.147, 0.004), (0.1, 0.004)], 0.078, STEEL, MAIN, 0.003)
for y in (-0.03, 0.03):
    for z in (BORE_Z + 0.014, 0.016):
        C.place(C.cylinder(0.0045, 0.005, BANDS, MAIN, 6, smooth=False), (0.124, y + (0.009 if y > 0 else -0.009), z), (0, 1 if y > 0 else -1, 0))
for y in (-DY, DY):
    C.place(C.cylinder(0.004, 0.004, BLACK, MAIN, 10), (0.1, y, BORE_Z), (-1, 0, 0))     # nail firing pins
C.place(C.cylinder(0.0105, 0.05, BRASS, MAIN, 16), (0.088, 0, BORE_Z + 0.037), X)        # brass shell lying on top
C.place(C.cylinder(0.0118, 0.006, BRASS, MAIN, 16), (0.082, 0, BORE_Z + 0.037), X)       # its rim
for x in (0.096, 0.13):                                                                   # wire holding it
    pts = [(x, 0.0125 * math.cos(a), BORE_Z + 0.037 + 0.0125 * math.sin(a)) for a in [i / 16 * 2 * math.pi for i in range(17)]]
    C.poly_tube(pts, 0.0011, BLACK, MAIN)
C.place(C.cylinder(0.0075, 0.06, BANDS, MAIN, 12), (0.152, -0.03, 0.012), (0, 1, 0))     # hinge knuckle

# ---- long stock, all wound in rag strips, rubber pad
C.flat_xz([(0.1, 0.03), (0.04, 0.032), (-0.01, 0.026), (-0.01, -0.004), (0.1, -0.002)], 0.032, STEEL, MAIN, 0.002)
stock = [(-0.01, 0.032), (-0.04, 0.026), (-0.09, -0.006), (-0.17, -0.01), (-0.29, 0.016), (-0.29, -0.11), (-0.24, -0.114),
         (-0.13, -0.088), (-0.1, -0.1), (-0.07, -0.09), (-0.04, -0.045), (-0.01, -0.006)]
C.flat_xz(stock, 0.038, CLOTH, MAIN, 0.006, segments=2)
C.flat_xz([(-0.29, 0.018), (-0.304, 0.019), (-0.304, -0.112), (-0.29, -0.112)], 0.04, RUBBER, MAIN, 0.003)

# ---- trigger guard and two triggers
C.flat_xz([(0.07, -0.002), (0.066, -0.036), (0.03, -0.046), (-0.012, -0.04), (-0.016, -0.03), (0.0, -0.033),
           (0.03, -0.038), (0.058, -0.032), (0.062, -0.002)], 0.008, BANDS, MAIN, 0.001)
for x in (0.022, 0.038):
    C.poly_tube([(x, 0, -0.002), (x + 0.002, 0, -0.014), (x - 0.004, 0, -0.026)], 0.0022, BLACK, TRIGGER)

o, tris = C.join_and_bake(OUT, 'scrap_double')
C.renders(o, OUT, 'scrap_double',
          [((0.06, 0, -0.01), (0.15, -0.85, 0.15), 50),
           ((0.06, 0, -0.01), (-0.55, -0.55, 0.4), 50),
           ((0.12, 0, 0.04), (0.06, -0.24, 0.14), 50)],
          (math.radians(-90), 0, math.radians(-40)), 0.85)
print('BUILT scrap_double', tris, 'tris', flush=True)
