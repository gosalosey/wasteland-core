# Pipe shotgun (scrap_pipe_shotgun): a single-shot break-open gun made from
# plumbing: a long dark rusty pipe barrel held by clamp rings, a heavy
# coupling breech, a ring trigger guard and a wooden rifle stock wrapped in
# grey duct tape over red cloth. Built on the game's sawed-off double-barrel
# layout: the barrel is on the hinge bone (Gun_Breach) so it swings open when
# reloading, the trigger on Gun_Trigger_Pr, everything else on Gun_Main_Bone.
# X is forward, the bore runs along z = 0.046 to the muzzle at x = 0.423; the
# right hand (Gun_GripR) is at x = -0.084, z = -0.068.
#   blender -b --python build_pipe_shotgun.py -- <tex folder> <out folder>
import bpy, bmesh, math, random, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(11)
C.start(TEX)

MAIN, BREACH, TRIGGER = 'Gun_Main_Bone', 'Gun_Breach', 'Gun_Trigger_Pr'
BORE_Z = 0.046
X = (1, 0, 0)


# ---- materials: dark old steel, darker rusty bands, taped stock, black iron
def old_steel():
    m = C.Mat('steel')
    base = m.ramp(m.noise(40, 6), (0.035, 0.028, 0.022, 1), (0.09, 0.075, 0.06, 1), 0.3, 0.75)
    rust = m.mix(m.tex('Rust004', 22.0), (0.55, 0.5, 0.45, 1), 1.0, 'MULTIPLY')
    c = m.mix(base, rust, m.above(m.noise(8, 8), 0.5))
    return m.done(m.grime(c, 0.7, 20), 0.6)


def band_steel():
    m = C.Mat('bands')
    c = m.mix(m.tex('Rust004', 35.0), (0.4, 0.33, 0.28, 1), 1.0, 'MULTIPLY')
    return m.done(m.grime(c, 0.6), 0.55)


def taped_stock():
    """Grey duct tape wound diagonally over red cloth; the red shows in the gaps."""
    m = C.Mat('taped')
    w1 = m.n.new('ShaderNodeTexWave'); w1.bands_direction = 'DIAGONAL'
    w1.inputs['Scale'].default_value = 13.0; w1.inputs['Distortion'].default_value = 3.0; w1.inputs['Detail'].default_value = 2.0
    m.l.new(m.tc, w1.inputs['Vector'])
    w2 = m.n.new('ShaderNodeTexWave'); w2.bands_direction = 'Y'
    w2.inputs['Scale'].default_value = 6.0; w2.inputs['Distortion'].default_value = 4.0
    m.l.new(m.tc, w2.inputs['Vector'])
    t1 = m.above(w1.outputs['Fac'], 0.32)
    t2 = m.above(w2.outputs['Fac'], 0.55)
    cover = m.n.new('ShaderNodeMath'); cover.operation = 'MAXIMUM'
    m.l.new(t1, cover.inputs[0]); m.l.new(t2, cover.inputs[1])
    red = m.ramp(m.noise(30, 4), (0.10, 0.008, 0.006, 1), (0.22, 0.016, 0.01, 1), 0.3, 0.7)
    tape = m.ramp(m.noise(70, 3), (0.06, 0.06, 0.058, 1), (0.14, 0.14, 0.135, 1), 0.3, 0.75)
    edge = m.ramp(w1.outputs['Fac'], (0.6, 0.6, 0.6, 1), (1, 1, 1, 1), 0.32, 0.4)   # dark line at the tape edge
    tape = m.mix(tape, edge, 1.0, 'MULTIPLY')
    c = m.mix(red, tape, cover.outputs[0])
    return m.done(m.grime(c, 0.6, 12), 0.65)


STEEL, BANDS, TAPED, BLACK = old_steel(), band_steel(), taped_stock(), C.black_metal()


def profile(points, thick, mat, bone, bevel=0.004):
    """A flat shape drawn in the XZ plane (x, z), given thickness along Y."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -thick / 2, z)) for x, z in points]
    f = bm.faces.new(vs)
    if f.normal.y > 0: f.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)], vec=(0, thick, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect='EDGES', clamp_overlap=True)
    o = C.add(bm, 'profile', mat, bone)
    for p in o.data.polygons: p.use_smooth = True
    return o


def clamp_ring(x, r, bone, width=0.009):
    """A thick steel band round the barrel with its bolt lug on the side."""
    C.place(C.ring(r, width, 0.0035, BANDS, bone, 20), (x, 0, BORE_Z), X)
    lug = C.box((width, 0.007, 0.008), BANDS, bone); lug.location = (x + width / 2, -(r + 0.006), BORE_Z)
    C.place(C.cylinder(0.0028, 0.012, BLACK, bone, 6), (x + width / 2, -(r + 0.004), BORE_Z + 0.006), (0, 0, -1))


# ---- barrel (swings open): long thick pipe, clamp rings, muzzle collar, sight
R = 0.0165
C.place(C.tube_pipe(R, 0.0115, 0.28, STEEL, BREACH, 20), (0.148, 0, BORE_Z), X)
C.place(C.ring(R, 0.014, 0.003, BANDS, BREACH, 20), (0.409, 0, BORE_Z), X)              # muzzle collar
for x in (0.19, 0.25, 0.31, 0.365):
    clamp_ring(x + random.uniform(-0.004, 0.004), R, BREACH)
C.place(C.cylinder(0.0022, 0.012, BLACK, BREACH, 6), (0.415, 0, BORE_Z + R + 0.002), (0, 0, 1))  # bead sight
s = C.box((0.07, 0.014, 0.005), BANDS, BREACH); s.location = (0.185, 0, BORE_Z - R - 0.002)      # hinge strap

# ---- breech (stays): heavy coupling, threaded nipple, end cap, nail hammer
C.place(C.cylinder(0.0235, 0.046, STEEL, MAIN, 24), (0.102, 0, BORE_Z), X)              # coupling
for x in (0.104, 0.142):                                                                 # its raised rims
    C.place(C.ring(0.0235, 0.004, 0.0015, BANDS, MAIN, 24), (x, 0, BORE_Z), X)
C.place(C.cylinder(0.019, 0.022, STEEL, MAIN, 24), (0.08, 0, BORE_Z), X)                # nipple
C.place(C.cylinder(0.0215, 0.016, BANDS, MAIN, 8, smooth=False), (0.064, 0, BORE_Z), X) # hex end cap
C.poly_tube([(0.064, 0, BORE_Z), (0.05, 0, BORE_Z + 0.004), (0.044, 0, BORE_Z + 0.02)], 0.0028, BLACK, MAIN)   # nail hammer
C.place(C.cylinder(0.0065, 0.04, BANDS, MAIN, 12), (0.152, -0.02, 0.019), (0, 1, 0))    # hinge knuckle
k = C.box((0.034, 0.03, 0.024), BANDS, MAIN, bevel=0.002); k.location = (0.136, 0, 0.022)

# ---- stock: one piece from under the breech, down the wrist to the butt, all taped
stock = [(0.10, 0.026), (0.04, 0.030), (-0.02, 0.016), (-0.07, -0.018), (-0.16, -0.026), (-0.30, -0.01),
         (-0.305, -0.13), (-0.27, -0.135), (-0.13, -0.098), (-0.10, -0.092), (-0.06, -0.06), (0.0, -0.012), (0.06, 0.0)]
profile(stock, 0.036, TAPED, MAIN)
bp = profile([(-0.300, -0.005), (-0.312, -0.006), (-0.317, -0.135), (-0.305, -0.136)], 0.040, BLACK, MAIN, 0.002)  # rubber butt pad
# wire binding the breech to the stock
pts = []
for i in range(80):
    t = i / 79; a = t * 2 * math.pi * 6
    pts.append((0.064 + t * 0.026, 0.0195 * math.cos(a), 0.034 + 0.0175 * math.sin(a)))
C.poly_tube(pts, 0.0011, BLACK, MAIN)

# ---- trigger guard ring and trigger
pts = [(0.03 + 0.025 * math.cos(a), 0, -0.024 + 0.02 * math.sin(a)) for a in [i * 2 * math.pi / 24 for i in range(25)]]
C.poly_tube(pts, 0.0025, BANDS, MAIN)
C.poly_tube([(0.032, 0, 0.0), (0.034, 0, -0.016), (0.028, 0, -0.03)], 0.0026, BLACK, TRIGGER)

o, tris = C.join_and_bake(OUT, 'pipe_shotgun')
C.renders(o, OUT, 'pipe_shotgun',
          [((0.05, 0, -0.03), (0.15, -0.8, 0.15), 50),
           ((0.05, 0, -0.03), (-0.55, -0.5, 0.35), 50),
           ((0.1, 0, 0.0), (0.12, -0.3, 0.12), 50)],
          (math.radians(-90), 0, math.radians(18)), 0.8)
print('BUILT pipe_shotgun', tris, 'tris', flush=True)
