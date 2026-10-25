# Builds the "scrap barricade" wood wall (4 x 0.2 x 3 m, origin bottom
# centre, outside = -Y), bakes one 1024 texture (wood + rust + grime + AO +
# spray paint) and renders previews. Run: blender -b --python build_wall.py
import bpy, bmesh, math, random, os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, 'tex')
OUT = os.path.join(HERE, 'out')
os.makedirs(OUT, exist_ok=True)
random.seed(1337)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def img(name, kind, colour=True):
    p = os.path.join(TEX, name, f'{name}_1K-JPG_{kind}.jpg')
    i = bpy.data.images.load(p, check_existing=True)
    if not colour: i.colorspace_settings.name = 'Non-Color'
    return i

# --- materials (rich, for baking) --------------------------------------------
def pbr(name, tex, tint=(1, 1, 1, 1), scale=1.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; n = nt.nodes; l = nt.links
    bsdf = n['Principled BSDF']
    tc = n.new('ShaderNodeTexCoord'); mp = n.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = (scale, scale, scale)
    l.new(tc.outputs['UV'], mp.inputs['Vector'])
    col = n.new('ShaderNodeTexImage'); col.image = img(tex, 'Color')
    l.new(mp.outputs['Vector'], col.inputs['Vector'])
    mix = n.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0
    l.new(col.outputs['Color'], mix.inputs['A']); mix.inputs['B'].default_value = tint
    # grime: dark noise blotches
    noise = n.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 3.0; noise.inputs['Detail'].default_value = 8
    l.new(tc.outputs['Object'], noise.inputs['Vector'])
    ramp = n.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.45; ramp.color_ramp.elements[0].color = (0.45, 0.42, 0.38, 1)
    ramp.color_ramp.elements[1].position = 0.75; ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    l.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    mix2 = n.new('ShaderNodeMix'); mix2.data_type = 'RGBA'; mix2.blend_type = 'MULTIPLY'; mix2.inputs['Factor'].default_value = 1.0
    l.new(mix.outputs['Result'], mix2.inputs['A']); l.new(ramp.outputs['Color'], mix2.inputs['B'])
    # mud splashed up from the ground: darker, browner below ~0.7 m
    sz = n.new('ShaderNodeSeparateXYZ'); l.new(tc.outputs['Object'], sz.inputs['Vector'])
    pos = n.new('ShaderNodeNewGeometry'); sw = n.new('ShaderNodeSeparateXYZ'); l.new(pos.outputs['Position'], sw.inputs['Vector'])
    mr = n.new('ShaderNodeMapRange'); mr.inputs['From Min'].default_value = 0.0; mr.inputs['From Max'].default_value = 0.75
    mr.inputs['To Min'].default_value = 1.0; mr.inputs['To Max'].default_value = 0.0
    nz2 = n.new('ShaderNodeTexNoise'); nz2.inputs['Scale'].default_value = 9.0
    l.new(pos.outputs['Position'], nz2.inputs['Vector'])
    zj = n.new('ShaderNodeMath'); zj.operation = 'ADD'
    l.new(sw.outputs['Z'], zj.inputs[0]); l.new(nz2.outputs['Fac'], zj.inputs[1])
    zj2 = n.new('ShaderNodeMath'); zj2.operation = 'SUBTRACT'; l.new(zj.outputs[0], zj2.inputs[0]); zj2.inputs[1].default_value = 0.5
    l.new(zj2.outputs[0], mr.inputs['Value'])
    mud = n.new('ShaderNodeMix'); mud.data_type = 'RGBA'
    l.new(mr.outputs['Result'], mud.inputs['Factor']); l.new(mix2.outputs['Result'], mud.inputs['A'])
    mud.inputs['B'].default_value = (0.09, 0.07, 0.05, 1)
    l.new(mud.outputs['Result'], bsdf.inputs['Base Color'])
    rough = n.new('ShaderNodeTexImage'); rough.image = img(tex, 'Roughness', False)
    l.new(mp.outputs['Vector'], rough.inputs['Vector']); l.new(rough.outputs['Color'], bsdf.inputs['Roughness'])
    nrm = n.new('ShaderNodeTexImage'); nrm.image = img(tex, 'NormalGL', False)
    l.new(mp.outputs['Vector'], nrm.inputs['Vector'])
    nm = n.new('ShaderNodeNormalMap'); l.new(nrm.outputs['Color'], nm.inputs['Color']); l.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    return m

WOOD = [pbr('wood_a', 'Planks012', (1, 1, 1, 1)), pbr('wood_b', 'Planks012', (0.78, 0.72, 0.66, 1)),
        pbr('wood_c', 'Wood049', (0.62, 0.55, 0.48, 1), 0.5)]
STUD = pbr('stud', 'Wood049', (0.55, 0.48, 0.4, 1), 0.5)
RUST = pbr('rust', 'Rust004', (1.35, 1.15, 1.0, 1), 2.0)

# Spray paint: a red X painted on the outside of the planks (projected from -Y).
def add_spray(m):
    nt = m.node_tree; n = nt.nodes; l = nt.links
    bsdf = n['Principled BSDF']
    base = bsdf.inputs['Base Color'].links[0].from_socket
    geo = n.new('ShaderNodeNewGeometry')
    sep = n.new('ShaderNodeSeparateXYZ'); l.new(geo.outputs['Position'], sep.inputs['Vector'])
    # X centred at (x=-0.6, z=1.55) on the wall, strokes 0.07 wide
    expr = n.new('ShaderNodeMath')  # placeholder chain built below
    def node(op, a, b=None):
        nd = n.new('ShaderNodeMath'); nd.operation = op
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): nd.inputs[i].default_value = v
            else: l.new(v, nd.inputs[i])
        return nd.outputs[0]
    dx = node('SUBTRACT', sep.outputs['X'], -0.6); dz = node('SUBTRACT', sep.outputs['Z'], 1.55)
    d1 = node('ABSOLUTE', node('SUBTRACT', dx, node('MULTIPLY', dz, 0.9)))
    d2 = node('ABSOLUTE', node('ADD', dx, node('MULTIPLY', dz, 0.9)))
    stroke = node('LESS_THAN', node('MINIMUM', d1, d2), 0.045)
    inbox = node('MULTIPLY', node('LESS_THAN', node('ABSOLUTE', dx), 0.55), node('LESS_THAN', node('ABSOLUTE', dz), 0.6))
    nsep = n.new('ShaderNodeSeparateXYZ'); l.new(geo.outputs['Normal'], nsep.inputs['Vector'])
    front = node('LESS_THAN', nsep.outputs['Y'], -0.5)
    # ragged edges: noise
    nz = n.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 40; l.new(geo.outputs['Position'], nz.inputs['Vector'])
    rag = node('GREATER_THAN', nz.outputs['Fac'], 0.32)
    fac = node('MULTIPLY', node('MULTIPLY', node('MULTIPLY', stroke, inbox), front), rag)
    mix = n.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    l.new(fac, mix.inputs['Factor']); l.new(base, mix.inputs['A']); mix.inputs['B'].default_value = (0.35, 0.02, 0.01, 1)
    l.new(mix.outputs['Result'], bsdf.inputs['Base Color'])
for m in WOOD: add_spray(m)

# --- geometry -----------------------------------------------------------------
parts = []
def box(name, size, loc, rot=(0, 0, 0), mat=None, uvscale=1.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name
    o.scale = size; bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=uvscale); bpy.ops.object.mode_set(mode='OBJECT')
    if mat: o.data.materials.append(mat)
    parts.append(o); return o

W, H, T = 4.0, 3.0, 0.2
# posts at both ends (inside face)
for x in (-W / 2 + 0.08, W / 2 - 0.08):
    box('post', (0.14, 0.12, H), (x, 0.03, H / 2), mat=STUD)
# horizontal planks on the outside face, crooked, with gaps
z = 0.02
while z < H - 0.05:
    h = random.uniform(0.24, 0.34)
    h = min(h, H - z - 0.01)
    gap = random.uniform(0.008, 0.035)
    tilt = math.radians(random.uniform(-1.4, 1.4))
    length = W - random.uniform(0.0, 0.06)
    xoff = random.uniform(-0.02, 0.02)
    box('plank', (length, 0.035, h), (xoff, -T / 2 + 0.03 + random.uniform(-0.006, 0.006), z + h / 2), rot=(0, tilt, 0),
        mat=random.choice(WOOD), uvscale=random.uniform(0.9, 1.3))
    z += h + gap
# braces on the inside: two rails and a diagonal
for zz in (0.55, 2.45):
    box('rail', (W - 0.3, 0.07, 0.14), (0, T / 2 - 0.045, zz), mat=STUD)
ang = math.atan2(2.45 - 0.55, W - 0.5)
box('brace', (math.hypot(W - 0.5, 1.9), 0.06, 0.13), (0, T / 2 - 0.05, 1.5), rot=(0, -ang, 0), mat=STUD)

# rusty corrugated patch on the outside (lower right), wavy sheet
def corrugated(name, w, h, loc, waves=16, depth=0.012, rot=0.0):
    bm = bmesh.new()
    nx = waves * 6
    verts = []
    for j in range(2):
        row = []
        for i in range(nx + 1):
            x = -w / 2 + w * i / nx
            y = math.sin(i / nx * waves * 2 * math.pi) * depth
            row.append(bm.verts.new((x, y, -h / 2 + h * j)))
        verts.append(row)
    for i in range(nx):
        bm.faces.new((verts[0][i], verts[0][i + 1], verts[1][i + 1], verts[1][i]))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    o.location = loc; o.rotation_euler = (0, rot, 0)
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    mod = o.modifiers.new('solid', 'SOLIDIFY'); mod.thickness = 0.004
    bpy.ops.object.modifier_apply(modifier='solid')
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=1.0); bpy.ops.object.mode_set(mode='OBJECT')
    o.select_set(False)
    o.data.materials.append(RUST); parts.append(o); return o
corrugated('sheet', 1.3, 1.0, (1.05, -T / 2 - 0.0, 0.75), rot=math.radians(4))
# a nailed-on cross board over the gap (classic barricade look)
box('xboard', (2.2, 0.03, 0.18), (-0.9, -T / 2 - 0.005, 2.35), rot=(0, math.radians(-14), 0), mat=WOOD[2])

# join everything into one mesh
bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
wall = bpy.context.active_object; wall.name = 'wall_hi'
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- bake to one texture --------------------------------------------------------
# second UV map, packed islands, for the bake
wall.data.uv_layers.new(name='bake')
wall.data.uv_layers.active = wall.data.uv_layers['bake']
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')

SIZE = 1024
bake_img = bpy.data.images.new('wl_bake_wall_wood', SIZE, SIZE)
for m in wall.data.materials:
    tn = m.node_tree.nodes.new('ShaderNodeTexImage'); tn.image = bake_img
    uvn = m.node_tree.nodes.new('ShaderNodeUVMap'); uvn.uv_map = 'bake'
    m.node_tree.links.new(uvn.outputs['UV'], tn.inputs['Vector'])
    m.node_tree.nodes.active = tn
# the plank/texture UVs are the first map; materials use 'UV' coord = active render map
wall.data.uv_layers[0].active_render = True

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
bpy.context.view_layer.objects.active = wall; wall.select_set(True)
# bake diffuse colour, then multiply in AO
scene.render.bake.use_pass_direct = False; scene.render.bake.use_pass_indirect = False; scene.render.bake.use_pass_color = True
scene.render.bake.margin = 6
bpy.ops.object.bake(type='DIFFUSE')
col = list(bake_img.pixels)
ao_img = bpy.data.images.new('ao', SIZE, SIZE)
for m in wall.data.materials:
    for nd in m.node_tree.nodes:
        if nd.type == 'TEX_IMAGE' and nd.image == bake_img: nd.image = ao_img; m.node_tree.nodes.active = nd
scene.cycles.samples = 48
bpy.ops.object.bake(type='AO')
ao = ao_img.pixels[:]
out = [0.0] * len(col)
for i in range(0, len(col), 4):
    a = 0.35 + 0.65 * ao[i]
    out[i] = col[i] * a; out[i + 1] = col[i + 1] * a; out[i + 2] = col[i + 2] * a; out[i + 3] = 1.0
bake_img.pixels = out
bake_img.filepath_raw = os.path.join(OUT, 'wl_bp_wall_wood_d.png'); bake_img.file_format = 'PNG'; bake_img.save()
print('BAKED', bake_img.filepath_raw)

# --- low (game) material: just the baked texture -----------------------------------
game = bpy.data.materials.new('game'); game.use_nodes = True
gn = game.node_tree.nodes; gb = gn['Principled BSDF']
ti = gn.new('ShaderNodeTexImage'); ti.image = bake_img
uv = gn.new('ShaderNodeUVMap'); uv.uv_map = 'bake'
game.node_tree.links.new(uv.outputs['UV'], ti.inputs['Vector'])
game.node_tree.links.new(ti.outputs['Color'], gb.inputs['Base Color'])
gb.inputs['Roughness'].default_value = 0.85
wall.data.materials.clear(); wall.data.materials.append(game)
# keep only the bake UVs (the game model has one UV map)
while len(wall.data.uv_layers) > 1:
    wall.data.uv_layers.remove(wall.data.uv_layers[0])
print('TRIS', sum(len(p.vertices) - 2 for p in wall.data.polygons))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'wall_wood.blend'))

# --- previews -------------------------------------------------------------------
scene.cycles.samples = 64
scene.render.resolution_x = 900; scene.render.resolution_y = 600
world = bpy.data.worlds.new('w'); scene.world = world; world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.32, 0.34, 0.33, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); bpy.context.collection.objects.link(sun)
sun.data.energy = 3.5; sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
ground = bpy.context.active_object
gm = bpy.data.materials.new('ground'); gm.use_nodes = True
gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.12, 0.11, 0.09, 1)
ground.data.materials.append(gm)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); bpy.context.collection.objects.link(cam); scene.camera = cam
cam.data.lens = 35
def shot(name, loc, target):
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
shot('preview_front.png', (2.6, -6.2, 1.9), (0, 0, 1.4))
shot('preview_back.png', (-2.4, 5.6, 1.8), (0, 0, 1.4))
shot('preview_close.png', (1.3, -2.2, 1.2), (0.6, 0, 1.0))
print('DONE')
