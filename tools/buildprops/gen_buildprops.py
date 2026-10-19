"""Wasteland building props generator.

Writes CodeWalker XML for every base-building piece (model, collision,
archetypes) plus original procedural textures, ready for `wlprops build`.
Everything here is made from scratch (simple boxes and code-painted
textures), so the result can be shared freely with Wasteland Core.

usage: python gen_buildprops.py <outDir>
"""
import io, math, os, random, struct, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
TXD = 'wl_buildprops'
TEX = 512

# ---------------------------------------------------------------------------
# Textures (painted with code)
# ---------------------------------------------------------------------------

def noise(size, scale, seed, amp):
    rnd = random.Random(seed)
    small = Image.new('L', (max(1, size // scale), max(1, size // scale)))
    small.putdata([rnd.randint(128 - amp, 128 + amp) for _ in range(small.size[0] * small.size[1])])
    return small.resize((size, size), Image.BICUBIC)

def tint(gray, dark, light):
    lut = []
    for c in range(3):
        lut += [int(dark[c] + (light[c] - dark[c]) * i / 255) for i in range(256)]
    return Image.merge('RGB', (gray, gray, gray)).point(lut)

def blend(a, b, mask):
    return Image.composite(b, a, mask)

def wood(seed=1):
    rnd = random.Random(seed)
    img = Image.new('RGB', (TEX, TEX))
    d = ImageDraw.Draw(img)
    boards, y = 8, 0
    bh = TEX // boards
    for i in range(boards):
        base = rnd.randint(-18, 18)
        grain = noise(TEX, 6, seed * 100 + i, 40).resize((TEX * 4, bh), Image.BICUBIC).crop((0, 0, TEX, bh))
        streak = Image.effect_noise((TEX, bh), 30).filter(ImageFilter.GaussianBlur(1)).resize((TEX, bh))
        g = Image.blend(grain, streak, 0.35)
        col = tint(g, (62 + base, 44 + base, 28 + base), (150 + base, 112 + base, 72 + base))
        img.paste(col, (0, y))
        # gap and nails
        d.rectangle((0, y, TEX, y + 2), fill=(22, 16, 10))
        for nx in (18, TEX // 2, TEX - 22):
            cy = y + bh // 2
            d.ellipse((nx - 4, cy - 4, nx + 4, cy + 4), fill=(48, 44, 40))
            d.ellipse((nx - 2, cy - 2, nx + 1, cy + 1), fill=(110, 100, 88))
        y += bh
    # dirt and weathering
    dirt = noise(TEX, 32, seed + 7, 60)
    img = blend(img, tint(dirt, (30, 26, 20), (80, 70, 55)), dirt.point(lambda v: max(0, v - 150) * 2))
    return img

def metal(seed=2):
    rnd = random.Random(seed)
    w = TEX
    ridge = Image.new('L', (w, 1))
    ridge.putdata([int(128 + 70 * math.sin(x / w * math.pi * 2 * 10)) for x in range(w)])
    ridge = ridge.resize((w, w))
    streaks = noise(w, 4, seed, 30).resize((w, w // 16), Image.BICUBIC).resize((w, w), Image.BICUBIC)
    g = Image.blend(ridge, streaks, 0.3)
    img = tint(g, (58, 62, 64), (150, 154, 152))
    # rust patches and drips
    rust = noise(w, 40, seed + 3, 90)
    mask = rust.point(lambda v: max(0, v - 140) * 3)
    img = blend(img, tint(noise(w, 3, seed + 4, 50), (70, 32, 14), (160, 82, 34)), mask)
    d = ImageDraw.Draw(img)
    for _ in range(26):
        x = rnd.randint(0, w); y = rnd.randint(0, w // 2)
        d.line((x, y, x + rnd.randint(-3, 3), y + rnd.randint(40, 200)), fill=(96, 48, 22), width=rnd.randint(1, 3))
    # rivets along the top and bottom
    for x in range(16, w, 64):
        for y in (14, w - 14):
            d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(70, 72, 72)); d.ellipse((x - 3, y - 3, x + 1, y + 1), fill=(170, 170, 165))
    return img.filter(ImageFilter.SMOOTH)

def stone(seed=3):
    rnd = random.Random(seed)
    img = Image.new('RGB', (TEX, TEX), (70, 68, 62))
    d = ImageDraw.Draw(img)
    rows = 8; rh = TEX // rows
    for r in range(rows):
        x = -rnd.randint(0, 60) if r % 2 else 0
        while x < TEX:
            bw = rnd.randint(70, 120)
            shade = rnd.randint(-22, 22)
            tile = tint(noise(bw, 3, rnd.randint(0, 9999), 45).resize((bw, rh)), (88 + shade, 84 + shade, 76 + shade), (160 + shade, 154 + shade, 140 + shade))
            img.paste(tile.crop((0, 0, max(1, bw - 6), rh - 6)), (x + 3, r * rh + 3))
            x += bw
    grime = noise(TEX, 24, seed + 9, 70)
    img = blend(img, tint(grime, (28, 30, 22), (60, 66, 44)), grime.point(lambda v: max(0, v - 155) * 2))
    return img

def dark_metal(seed=4):
    g = noise(TEX, 8, seed, 25)
    img = tint(g, (34, 34, 34), (78, 78, 76))
    d = ImageDraw.Draw(img)
    for y in range(0, TEX, 128):
        d.rectangle((0, y, TEX, y + 5), fill=(24, 24, 24))
    rust = noise(TEX, 30, seed + 1, 90)
    img = blend(img, tint(noise(TEX, 3, seed + 2, 40), (66, 30, 12), (130, 66, 30)), rust.point(lambda v: max(0, v - 165) * 3))
    return img

def write_dds(img, path):
    """Uncompressed BGRA8 DDS with a full mip chain."""
    img = img.convert('RGBA')
    mips = [img]
    while mips[-1].size[0] > 4:
        s = mips[-1].size[0] // 2
        mips.append(mips[-1].resize((s, s), Image.LANCZOS))
    w, h = img.size
    DDSD_CAPS, DDSD_HEIGHT, DDSD_WIDTH, DDSD_PITCH, DDSD_PIXELFORMAT, DDSD_MIPMAPCOUNT = 0x1, 0x2, 0x4, 0x8, 0x1000, 0x20000
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PITCH | DDSD_PIXELFORMAT | DDSD_MIPMAPCOUNT
    pf = struct.pack('<IIIIIIII', 32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    caps = 0x1000 | 0x8 | 0x400000
    header = struct.pack('<4sIIIIIII', b'DDS ', 124, flags, h, w, w * 4, 0, len(mips)) + b'\0' * 44 + pf + struct.pack('<IIIII', caps, 0, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(header)
        for m in mips:
            r, g, b, a = m.split()
            f.write(Image.merge('RGBA', (b, g, r, a)).tobytes())
    return len(mips)

TEXTURES = {
    'wlbp_wood': wood(11),
    'wlbp_metal': metal(22),
    'wlbp_stone': stone(33),
    'wlbp_darkmetal': dark_metal(44),
}
items = []
for name, img in TEXTURES.items():
    levels = write_dds(img, os.path.join(OUT, name + '.dds'))
    img.save(os.path.join(OUT, name + '_preview.png'))
    items.append(f'''  <Item>
   <Name>{name}</Name>
   <Unk32 value="128" />
   <Usage>DIFFUSE</Usage>
   <UsageFlags>UNK24</UsageFlags>
   <ExtraFlags value="0" />
   <Width value="{TEX}" />
   <Height value="{TEX}" />
   <MipLevels value="{levels}" />
   <Format>D3DFMT_A8R8G8B8</Format>
   <FileName>{name}.dds</FileName>
  </Item>''')
with open(os.path.join(OUT, TXD + '.ytd.xml'), 'w', encoding='utf-8') as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<TextureDictionary>\n' + '\n'.join(items) + '\n</TextureDictionary>\n')

# ---------------------------------------------------------------------------
# Geometry: boxes (and a wedge for ramps) in metres
# ---------------------------------------------------------------------------

UV_SCALE = 0.5  # one texture repeat per 2 m

def box(x0, y0, z0, x1, y1, z1):
    """6 faces, each 4 corners (counter-clockwise seen from outside) + normal."""
    return [
        ((0, 0, 1), [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]),
        ((0, 0, -1), [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)]),
        ((0, -1, 0), [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]),
        ((0, 1, 0), [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)]),
        ((1, 0, 0), [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)]),
        ((-1, 0, 0), [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)]),
    ]

def wedge(x0, y0, x1, y1, h):
    """Ramp: rises from y0 (height 0) to y1 (height h)."""
    l = math.hypot(y1 - y0, h)
    n = (0, -h / l, (y1 - y0) / l)
    return [
        (n, [(x0, y0, 0), (x1, y0, 0), (x1, y1, h), (x0, y1, h)]),
        ((0, 0, -1), [(x0, y1, 0), (x1, y1, 0), (x1, y0, 0), (x0, y0, 0)]),
        ((0, 1, 0), [(x1, y1, 0), (x0, y1, 0), (x0, y1, h), (x1, y1, h)]),
        ((1, 0, 0), [(x1, y0, 0), (x1, y1, 0), (x1, y1, h), (x1, y1, h)]),
        ((-1, 0, 0), [(x0, y1, 0), (x0, y0, 0), (x0, y1, h), (x0, y1, h)]),
    ]

def uv(p, n):
    ax = max(range(3), key=lambda i: abs(n[i]))
    if ax == 2: u, v = p[0], p[1]
    elif ax == 1: u, v = p[0], p[2]
    else: u, v = p[1], p[2]
    return u * UV_SCALE, -v * UV_SCALE

def mesh(faces):
    verts, idx, tris = [], [], []
    for n, quad in faces:
        base = len(verts)
        for p in quad:
            verts.append((p, n, uv(p, n)))
        for a, b, c in ((0, 1, 2), (0, 2, 3)):
            if len({quad[a], quad[b], quad[c]}) == 3:
                idx += [base + a, base + b, base + c]
                tris.append((quad[a], quad[b], quad[c]))
    return verts, idx, tris

def f(v): return ('%.6f' % v).rstrip('0').rstrip('.') if v != 0 else '0'

# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------

S, T, H = 4.0, 0.2, 3.0          # grid size, wall thickness, wall height
h2, t2 = S / 2, T / 2
MATS = {'wood': ('wlbp_wood', 70), 'stone': ('wlbp_stone', 11), 'metal': ('wlbp_metal', 56)}

def wall_with_hole(hx0, hz0, hx1, hz1, height=H, width=S):
    w2 = width / 2
    parts = []
    if hx0 > -w2: parts.append(box(-w2, -t2, 0, hx0, t2, height))
    if hx1 < w2: parts.append(box(hx1, -t2, 0, w2, t2, height))
    if hz0 > 0: parts.append(box(hx0, -t2, 0, hx1, t2, hz0))
    if hz1 < height: parts.append(box(hx0, -t2, hz1, hx1, t2, height))
    return [face for p in parts for face in p]

def bars(x0, z0, x1, z1, thick, n):
    parts = [box(x0, -thick, z0, x1, thick, z0 + 0.06), box(x0, -thick, z1 - 0.06, x1, thick, z1)]
    step = (x1 - x0) / (n + 1)
    for i in range(1, n + 1):
        cx = x0 + step * i
        parts.append(box(cx - 0.025, -thick, z0, cx + 0.025, thick, z1))
    return [face for p in parts for face in p]

SHAPES = {
    'foundation': box(-h2, -h2, 0, h2, h2, 1.0),
    'wall': box(-h2, -t2, 0, h2, t2, H),
    'halfwall': box(-h2, -t2, 0, h2, t2, H / 2),
    'doorway': wall_with_hole(-0.6, 0, 0.6, 2.2),
    'windowframe': wall_with_hole(-0.6, 1.0, 0.6, 2.0),
    'ceiling': box(-h2, -h2, 0, h2, h2, T),
    'frame': wall_with_hole(-1.6, 0, 1.6, 2.6),
    'ramp': wedge(-h2, -h2, h2, h2, 1.0),
}

PIECES = []  # (model, faces, texture, material)
for shape, faces in SHAPES.items():
    for mat, (tex, mid) in MATS.items():
        PIECES.append((f'wl_bp_{shape}_{mat}', faces, tex, mid))
# doors: pivot on the hinge edge (x = 0)
PIECES += [
    ('wl_bp_door_wood', box(0, -0.04, 0.02, 1.16, 0.04, 2.17), 'wlbp_wood', 70),
    ('wl_bp_door_metal', box(0, -0.04, 0.02, 1.16, 0.04, 2.17), 'wlbp_darkmetal', 56),
    ('wl_bp_garage_wood', box(-1.58, -0.05, 0.02, 1.58, 0.05, 2.58), 'wlbp_wood', 70),
    ('wl_bp_windowbar_wood', bars(-0.58, 1.02, 0.58, 1.98, 0.03, 5), 'wlbp_wood', 70),
    ('wl_bp_windowbar_metal', bars(-0.58, 1.02, 0.58, 1.98, 0.02, 7), 'wlbp_darkmetal', 56),
    # gate: two posts and a beam (opening 4.6 x 4.0); the gate door is one leaf hinged on the left
    ('wl_bp_gate_frame', [fc for p in (box(-2.8, -0.25, 0, -2.3, 0.25, 4.5), box(2.3, -0.25, 0, 2.8, 0.25, 4.5),
                                        box(-2.8, -0.25, 4.0, 2.8, 0.25, 4.5)) for fc in p], 'wlbp_wood', 70),
    ('wl_bp_gate_door', [fc for p in (box(0, -0.06, 0.05, 4.56, 0.06, 3.95),) for fc in p], 'wlbp_metal', 56),
    ('wl_bp_toolcupboard', box(-0.5, -0.3, 0, 0.5, 0.3, 1.8), 'wlbp_darkmetal', 56),
]

def bounds_of(verts):
    xs = [v[0][0] for v in verts]; ys = [v[0][1] for v in verts]; zs = [v[0][2] for v in verts]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

def vec(tag, v, w=None):
    s = f'<{tag} x="{f(v[0])}" y="{f(v[1])}" z="{f(v[2])}"'
    return s + (f' w="{f(w)}" />' if w is not None else ' />')

archetypes = []
for model, faces, tex, mid in PIECES:
    verts, idx, tris = mesh(faces)
    mn, mx = bounds_of(verts)
    c = tuple((mn[i] + mx[i]) / 2 for i in range(3))
    r = math.dist(mn, mx) / 2
    rows = '\n'.join(f'       {f(p[0])} {f(p[1])} {f(p[2])}   {f(n[0])} {f(n[1])} {f(n[2])}   255 255 255 255   {f(t[0])} {f(t[1])}'
                     for p, n, t in verts)
    ids = '\n'.join('       ' + ' '.join(str(i) for i in idx[k:k + 24]) for k in range(0, len(idx), 24))
    # collision: the same triangles
    cverts, cindex = [], {}
    polys = []
    for tri in tris:
        vi = []
        for p in tri:
            if p not in cindex:
                cindex[p] = len(cverts); cverts.append(p)
            vi.append(cindex[p])
        polys.append(f'     <Triangle m="0" v1="{vi[0]}" v2="{vi[1]}" v3="{vi[2]}" f1="1" f2="1" f3="1" />')
    cv = '\n'.join(f'     {f(p[0])}, {f(p[1])}, {f(p[2])}' for p in cverts)
    vol = (mx[0] - mn[0]) * (mx[1] - mn[1]) * (mx[2] - mn[2])
    common = f'''{vec('BoxMin', mn)}
  {vec('BoxMax', mx)}
  {vec('BoxCenter', c)}
  {vec('SphereCenter', c)}
  <SphereRadius value="{f(r)}" />'''
    xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<Drawable>
 <Name>{model}</Name>
 {vec('BoundingSphereCenter', c)}
 <BoundingSphereRadius value="{f(r)}" />
 {vec('BoundingBoxMin', mn)}
 {vec('BoundingBoxMax', mx)}
 <LodDistHigh value="9998" />
 <LodDistMed value="9998" />
 <LodDistLow value="9998" />
 <LodDistVlow value="9998" />
 <FlagsHigh value="1" />
 <FlagsMed value="0" />
 <FlagsLow value="0" />
 <FlagsVlow value="0" />
 <ShaderGroup>
  <Shaders>
   <Item>
    <Name>default</Name>
    <FileName>default.sps</FileName>
    <RenderBucket value="0" />
    <Parameters>
     <Item name="DiffuseSampler" type="Texture">
      <Name>{tex}</Name>
     </Item>
     <Item name="matMaterialColorScale" type="Vector" x="1" y="0" z="0" w="1" />
     <Item name="HardAlphaBlend" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="useTessellation" type="Vector" x="0" y="0" z="0" w="0" />
     <Item name="wetnessMultiplier" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="globalAnimUV1" type="Vector" x="0" y="1" z="0" w="0" />
     <Item name="globalAnimUV0" type="Vector" x="1" y="0" z="0" w="0" />
    </Parameters>
   </Item>
  </Shaders>
 </ShaderGroup>
 <DrawableModelsHigh>
  <Item>
   <RenderMask value="255" />
   <Flags value="0" />
   <HasSkin value="0" />
   <BoneIndex value="0" />
   <Unknown1 value="0" />
   <Geometries>
    <Item>
     <ShaderIndex value="0" />
     {vec('BoundingBoxMin', mn, mn[0])}
     {vec('BoundingBoxMax', mx, mx[0])}
     <VertexBuffer>
      <Flags value="0" />
      <Layout type="GTAV1">
       <Position />
       <Normal />
       <Colour0 />
       <TexCoord0 />
      </Layout>
      <Data>
{rows}
      </Data>
     </VertexBuffer>
     <IndexBuffer>
      <Data>
{ids}
      </Data>
     </IndexBuffer>
    </Item>
   </Geometries>
  </Item>
 </DrawableModelsHigh>
 <Bounds type="Composite">
  {common}
  <Margin value="0" />
  <Volume value="{f(vol)}" />
  <Inertia x="1" y="1" z="1" />
  <MaterialIndex value="0" />
  <MaterialColourIndex value="0" />
  <ProceduralID value="0" />
  <RoomID value="0" />
  <PedDensity value="0" />
  <UnkFlags value="0" />
  <PolyFlags value="0" />
  <UnkType value="1" />
  <Children>
   <Item type="Geometry">
  {common}
    <Margin value="0.04" />
    <Volume value="{f(vol)}" />
    <Inertia x="1" y="1" z="1" />
    <MaterialIndex value="0" />
    <MaterialColourIndex value="0" />
    <ProceduralID value="0" />
    <RoomID value="0" />
    <PedDensity value="0" />
    <UnkFlags value="0" />
    <PolyFlags value="0" />
    <UnkType value="1" />
    <CompositeTransform>
     1 0 0 0
     0 1 0 0
     0 0 1 0
     0 0 0 1
    </CompositeTransform>
    <CompositeFlags1>MAP_WEAPON, MAP_DYNAMIC, MAP_ANIMAL, MAP_COVER, MAP_VEHICLE</CompositeFlags1>
    <CompositeFlags2>VEHICLE_NOT_BVH, VEHICLE_BVH, PED, RAGDOLL, ANIMAL, ANIMAL_RAGDOLL, OBJECT, PLANT, PROJECTILE, EXPLOSION, FORKLIFT_FORKS, TEST_WEAPON, TEST_CAMERA, TEST_AI, TEST_SCRIPT, TEST_VEHICLE_WHEEL, GLASS</CompositeFlags2>
    {vec('GeometryCenter', c)}
    <UnkFloat1 value="0" />
    <UnkFloat2 value="0.0025" />
    <Materials>
     <Item>
      <Type value="{mid}" />
      <ProceduralID value="0" />
      <RoomID value="0" />
      <PedDensity value="0" />
      <Flags>NONE</Flags>
      <MaterialColourIndex value="0" />
      <Unk value="0" />
     </Item>
    </Materials>
    <Vertices>
{cv}
    </Vertices>
    <Polygons>
{chr(10).join(polys)}
    </Polygons>
   </Item>
  </Children>
 </Bounds>
 <Lights />
</Drawable>
'''
    with open(os.path.join(OUT, model + '.ydr.xml'), 'w', encoding='utf-8') as fh:
        fh.write(xml)
    archetypes.append(f'''  <Item type="CBaseArchetypeDef">
   <lodDist value="200" />
   <flags value="537001984" />
   <specialAttribute value="0" />
   {vec('bbMin', mn)}
   {vec('bbMax', mx)}
   {vec('bsCentre', c)}
   <bsRadius value="{f(r)}" />
   <hdTextureDist value="30" />
   <name>{model}</name>
   <textureDictionary>{TXD}</textureDictionary>
   <clipDictionary />
   <drawableDictionary />
   <physicsDictionary />
   <assetType>ASSET_TYPE_DRAWABLE</assetType>
   <assetName>{model}</assetName>
   <extensions />
  </Item>''')

with open(os.path.join(OUT, 'wl_buildprops.ytyp.xml'), 'w', encoding='utf-8') as fh:
    fh.write('<?xml version="1.0" encoding="UTF-8"?>\n<CMapTypes>\n <extensions />\n <archetypes>\n' + '\n'.join(archetypes)
             + '\n </archetypes>\n <name>wl_buildprops</name>\n <dependencies />\n <compositeEntityTypes itemType="CCompositeEntityType" />\n</CMapTypes>\n')

print(len(PIECES), 'models,', len(TEXTURES), 'textures written to', OUT)
