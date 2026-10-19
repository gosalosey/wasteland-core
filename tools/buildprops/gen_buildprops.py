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

def beam(seed=5):
    """Dark, rough timber for studs, braces and frames."""
    g = noise(TEX, 5, seed, 45).resize((TEX // 8, TEX), Image.BICUBIC).resize((TEX, TEX), Image.BICUBIC)
    g = Image.blend(g, Image.effect_noise((TEX, TEX), 25).filter(ImageFilter.GaussianBlur(1)), 0.3)
    img = tint(g, (34, 24, 15), (98, 72, 46))
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)
    for _ in range(14):  # cracks along the grain
        x = rnd.randint(0, TEX); y = rnd.randint(0, TEX)
        d.line((x, y, x + rnd.randint(-4, 4), y + rnd.randint(30, 120)), fill=(20, 14, 9), width=1)
    return img

def decals(img, seed, blood=3, spray=1):
    """Old blood splatters and spray-paint marks (survivors' signs)."""
    rnd = random.Random(seed)
    img = img.copy()
    over = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for _ in range(blood):
        cx, cy = rnd.randint(40, TEX - 40), rnd.randint(40, TEX - 40)
        for _ in range(40):
            r = rnd.randint(2, 14); dx, dy = rnd.gauss(0, 22), rnd.gauss(0, 18)
            d.ellipse((cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r), fill=(70, 8, 6, rnd.randint(90, 170)))
        for _ in range(5):  # drips
            x = cx + rnd.randint(-25, 25)
            d.line((x, cy, x + rnd.randint(-2, 2), cy + rnd.randint(30, 110)), fill=(60, 6, 5, 140), width=rnd.randint(2, 4))
    for _ in range(spray):  # a spray-painted X or arrow
        col = rnd.choice([(190, 40, 30), (220, 200, 60), (230, 230, 225)])
        cx, cy = rnd.randint(110, TEX - 110), rnd.randint(110, TEX - 110)
        s = rnd.randint(50, 80)
        if rnd.random() < 0.5:
            d.line((cx - s, cy - s, cx + s, cy + s), fill=col + (170,), width=12)
            d.line((cx - s, cy + s, cx + s, cy - s), fill=col + (170,), width=12)
        else:
            d.line((cx - s, cy, cx + s, cy), fill=col + (170,), width=11)
            d.line((cx + s, cy, cx + s - 30, cy - 26), fill=col + (170,), width=11)
            d.line((cx + s, cy, cx + s - 30, cy + 26), fill=col + (170,), width=11)
    over = over.filter(ImageFilter.GaussianBlur(1.2))
    base = img.convert('RGBA')
    base.alpha_composite(over)
    return base.convert('RGB')

TEXTURES = {
    'wlbp_wood': decals(wood(11), 101, blood=2, spray=1),
    'wlbp_beam': beam(55),
    'wlbp_metal': decals(metal(22), 202, blood=1, spray=1),
    'wlbp_stone': decals(stone(33), 303, blood=1, spray=1),
    'wlbp_darkmetal': decals(dark_metal(44), 404, blood=1, spray=0),
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
# Geometry: boxes, rotated boxes and a wedge, in metres. Every face carries
# its texture. Looks (detail) and collision (simple solid shapes) are kept
# apart: the details are only for the eye, the collision stays the same
# size as always, so snapping and existing bases are not affected.
# ---------------------------------------------------------------------------

UV_SCALE = 0.5  # one texture repeat per 2 m
WOOD, BEAM, METAL, DARK, STONE = 'wlbp_wood', 'wlbp_beam', 'wlbp_metal', 'wlbp_darkmetal', 'wlbp_stone'

def box(x0, y0, z0, x1, y1, z1, tex=None):
    return [
        ((0, 0, 1), [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], tex),
        ((0, 0, -1), [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)], tex),
        ((0, -1, 0), [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], tex),
        ((0, 1, 0), [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)], tex),
        ((1, 0, 0), [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], tex),
        ((-1, 0, 0), [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], tex),
    ]

def rot(p, rx, ry, rz):
    x, y, z = p
    if rx:
        c, s = math.cos(rx), math.sin(rx); y, z = y * c - z * s, y * s + z * c
    if ry:
        c, s = math.cos(ry), math.sin(ry); x, z = x * c + z * s, -x * s + z * c
    if rz:
        c, s = math.cos(rz), math.sin(rz); x, y = x * c - y * s, x * s + y * c
    return (x, y, z)

def rbox(cx, cy, cz, sx, sy, sz, tex, rx=0.0, ry=0.0, rz=0.0):
    """A box of size sx, sy, sz centred on cx, cy, cz, turned (degrees) about x, then y, then z."""
    rx, ry, rz = math.radians(rx), math.radians(ry), math.radians(rz)
    out = []
    for n, q, _ in box(-sx / 2, -sy / 2, -sz / 2, sx / 2, sy / 2, sz / 2):
        rq = [rot(p, rx, ry, rz) for p in q]
        out.append((rot(n, rx, ry, rz), [(p[0] + cx, p[1] + cy, p[2] + cz) for p in rq], tex))
    return out

def wedge(x0, y0, x1, y1, h, tex=None):
    l = math.hypot(y1 - y0, h)
    n = (0, -h / l, (y1 - y0) / l)
    return [
        (n, [(x0, y0, 0), (x1, y0, 0), (x1, y1, h), (x0, y1, h)], tex),
        ((0, 0, -1), [(x0, y1, 0), (x1, y1, 0), (x1, y0, 0), (x0, y0, 0)], tex),
        ((0, 1, 0), [(x1, y1, 0), (x0, y1, 0), (x0, y1, h), (x1, y1, h)], tex),
        ((1, 0, 0), [(x1, y0, 0), (x1, y1, 0), (x1, y1, h), (x1, y1, h)], tex),
        ((-1, 0, 0), [(x0, y1, 0), (x0, y0, 0), (x0, y1, h), (x0, y1, h)], tex),
    ]

def uv(p, n):
    ax = max(range(3), key=lambda i: abs(n[i]))
    if ax == 2: u, v = p[0], p[1]
    elif ax == 1: u, v = p[0], p[2]
    else: u, v = p[1], p[2]
    return u * UV_SCALE, -v * UV_SCALE

def f(v): return ('%.6f' % v).rstrip('0').rstrip('.') if abs(v) > 1e-9 else '0'

# ---------------------------------------------------------------------------
# Styles: how a flat rectangle of a wall looks in wood, metal or stone.
# A wall lies in x (width) and z (height), thickness in y (-0.1 .. 0.1).
# ---------------------------------------------------------------------------

S, T, H = 4.0, 0.2, 3.0
h2, t2 = S / 2, T / 2

def wood_panel(x0, z0, x1, z1, rnd, back=True):
    out = []
    # backing sheet
    out += box(x0, -0.03, z0, x1, 0.03, z1, BEAM)
    # front: horizontal boards, uneven ends and a slight tilt, some gaps
    z = z0
    while z < z1 - 0.05:
        bh = min(rnd.uniform(0.2, 0.28), z1 - z)
        if rnd.random() > 0.08:  # now and then a board is missing
            e0 = x0 + rnd.uniform(0.0, 0.06); e1 = x1 - rnd.uniform(0.0, 0.06)
            tilt = rnd.uniform(-1.2, 1.2) * (0.5 if (e1 - e0) > 2 else 1)
            out += rbox((e0 + e1) / 2, -0.065, z + bh / 2, e1 - e0, 0.05, bh - 0.025, WOOD, ry=tilt)
        z += bh
    if back and x1 - x0 > 0.8:
        # back: studs and a diagonal brace
        n = max(2, int((x1 - x0) / 1.3) + 1)
        for i in range(n):
            sx = x0 + 0.06 + (x1 - x0 - 0.12) * i / (n - 1)
            out += box(sx - 0.05, 0.03, z0, sx + 0.05, 0.1, z1, BEAM)
        if z1 - z0 > 1.2:
            ang = math.degrees(math.atan2(z1 - z0 - 0.2, x1 - x0 - 0.2))
            ln = math.hypot(x1 - x0 - 0.2, z1 - z0 - 0.2)
            out += rbox((x0 + x1) / 2, 0.065, (z0 + z1) / 2, ln, 0.06, 0.12, BEAM, ry=-ang)
    return out

def metal_panel(x0, z0, x1, z1, rnd, back=True):
    out = []
    # frame behind
    out += box(x0, 0.04, z0, x1, 0.1, z0 + 0.08, DARK)
    out += box(x0, 0.04, z1 - 0.08, x1, 0.1, z1, DARK)
    n = max(2, int((x1 - x0) / 1.4) + 1)
    for i in range(n):
        sx = x0 + 0.04 + (x1 - x0 - 0.08) * i / (n - 1)
        out += box(sx - 0.04, 0.04, z0, sx + 0.04, 0.1, z1, DARK)
    # front: corrugated sheets that overlap, each a little crooked
    w = x1 - x0
    sheets = max(1, round(w / 1.25))
    sw = w / sheets
    for i in range(sheets):
        cx = x0 + sw * (i + 0.5)
        width = sw + (0.08 if i < sheets - 1 else 0.0)
        out += rbox(cx, -0.06 + 0.012 * (i % 2), (z0 + z1) / 2, min(width, w), 0.03, (z1 - z0) - 0.02, METAL,
                    ry=rnd.uniform(-0.8, 0.8))
        # bolts down each sheet
        for bz in (z0 + 0.15, (z0 + z1) / 2, z1 - 0.15):
            if z1 - z0 > 0.4:
                out += box(cx - sw / 2 + 0.06, -0.1, bz - 0.025, cx - sw / 2 + 0.11, -0.075, bz + 0.025, DARK)
    # a patch plate somewhere
    if w > 1.5 and z1 - z0 > 1.5:
        px = rnd.uniform(x0 + 0.4, x1 - 0.9); pz = rnd.uniform(z0 + 0.3, z1 - 0.9)
        out += rbox(px + 0.25, -0.09, pz + 0.25, 0.5, 0.02, 0.45, DARK, ry=rnd.uniform(-8, 8))
    return out

def stone_panel(x0, z0, x1, z1, rnd, back=True):
    out = []
    out += box(x0, -0.085, z0, x1, 0.085, z1, STONE)
    # a heavier cap along the top, made of blocks of uneven height (chipped)
    x = x0
    while x < x1 - 0.01:
        bw = min(rnd.uniform(0.35, 0.6), x1 - x)
        top = z1 - rnd.uniform(0.0, 0.05)
        out += box(x + 0.005, -0.1, z1 - 0.16, x + bw - 0.005, 0.1, top, STONE)
        x += bw
    # a few blocks sticking out a little
    for _ in range(int((x1 - x0) * (z1 - z0) * 0.8)):
        bx = rnd.uniform(x0 + 0.1, x1 - 0.5); bz = rnd.uniform(z0 + 0.1, z1 - 0.4)
        out += box(bx, -0.1, bz, bx + rnd.uniform(0.25, 0.45), -0.085, bz + 0.22, STONE)
    # a footing along the bottom
    out += box(x0, -0.1, z0, x1, 0.1, z0 + 0.12, STONE)
    return out

STYLES = {'wood': wood_panel, 'metal': metal_panel, 'stone': stone_panel}
TRIM = {'wood': BEAM, 'metal': DARK, 'stone': STONE}

def styled_wall(mat, seed, hole=None, height=H, width=S):
    """A wall (optionally with a hole x0, z0, x1, z1) in a style, plus trim round the hole."""
    rnd = random.Random(seed)
    panel = STYLES[mat]
    w2 = width / 2
    out = []
    if not hole:
        return panel(-w2, 0, w2, height, rnd)
    hx0, hz0, hx1, hz1 = hole
    out += panel(-w2, 0, hx0, height, rnd)
    out += panel(hx1, 0, w2, height, rnd)
    if hz0 > 0: out += panel(hx0, 0, hx1, hz0, rnd, back=False)
    if hz1 < height: out += panel(hx0, hz1, hx1, height, rnd, back=False)
    # trim posts round the opening (inside the wall's thickness)
    tt = TRIM[mat]
    out += box(hx0 - 0.08, -0.1, hz0, hx0, 0.1, hz1 + 0.08, tt)
    out += box(hx1, -0.1, hz0, hx1 + 0.08, 0.1, hz1 + 0.08, tt)
    out += box(hx0 - 0.08, -0.1, hz1, hx1 + 0.08, 0.1, hz1 + 0.1, tt)
    if hz0 > 0:  # a sill
        out += box(hx0 - 0.12, -0.1, hz0 - 0.06, hx1 + 0.12, 0.1, hz0, tt)
    return out

def foundation(mat, seed):
    rnd = random.Random(seed)
    out = []
    if mat == 'wood':
        out += box(-h2 + 0.05, -h2 + 0.05, 0, h2 - 0.05, h2 - 0.05, 0.88, BEAM)
        # deck boards across the top
        x = -h2
        while x < h2 - 0.01:
            bw = min(rnd.uniform(0.22, 0.3), h2 - x)
            out += rbox(x + bw / 2, 0, 0.94, bw - 0.02, S - rnd.uniform(0, 0.06), 0.12, WOOD, rx=rnd.uniform(-0.4, 0.4))
            x += bw
        # skirting boards round the sides and corner posts
        for sgn in (-1, 1):
            out += box(-h2, sgn * h2 - (0.05 if sgn > 0 else 0), 0.05, h2, sgn * h2 + (0.05 if sgn < 0 else 0), 0.85, WOOD)
            out += box(sgn * h2 - (0.05 if sgn > 0 else 0), -h2, 0.05, sgn * h2 + (0.05 if sgn < 0 else 0), h2, 0.85, WOOD)
        for cx in (-h2, h2 - 0.18):
            for cy in (-h2, h2 - 0.18):
                out += box(cx, cy, 0, cx + 0.18, cy + 0.18, 0.9, BEAM)
    elif mat == 'metal':
        out += box(-h2 + 0.06, -h2 + 0.06, 0, h2 - 0.06, h2 - 0.06, 0.92, DARK)
        out += box(-h2, -h2, 0.92, h2, h2, 1.0, DARK)  # floor plate
        for sgn in (-1, 1):
            out += box(-h2, sgn * h2 - (0.06 if sgn > 0 else 0), 0.06, h2, sgn * h2 + (0.06 if sgn < 0 else 0), 0.9, METAL)
            out += box(sgn * h2 - (0.06 if sgn > 0 else 0), -h2, 0.06, sgn * h2 + (0.06 if sgn < 0 else 0), h2, 0.9, METAL)
        for cx in (-h2, h2 - 0.14):
            for cy in (-h2, h2 - 0.14):
                out += box(cx, cy, 0, cx + 0.14, cy + 0.14, 1.0, DARK)
        for i in range(-3, 4):  # welded seams on the plate
            out += box(i * 0.55 - 0.015, -h2 + 0.1, 1.0, i * 0.55 + 0.015, h2 - 0.1, 1.0, DARK)
    else:
        out += box(-h2 + 0.04, -h2 + 0.04, 0, h2 - 0.04, h2 - 0.04, 0.9, STONE)
        for ix in range(4):  # paving slabs, slightly uneven
            for iy in range(4):
                x0 = -h2 + ix; y0 = -h2 + iy
                out += box(x0 + 0.01, y0 + 0.01, 0.9, x0 + 0.99, y0 + 0.99, 1.0 - rnd.uniform(0, 0.025), STONE)
        for sgn in (-1, 1):
            out += box(-h2, sgn * h2 - (0.04 if sgn > 0 else 0), 0, h2, sgn * h2 + (0.04 if sgn < 0 else 0), 0.9, STONE)
            out += box(sgn * h2 - (0.04 if sgn > 0 else 0), -h2, 0, sgn * h2 + (0.04 if sgn < 0 else 0), h2, 0.9, STONE)
    return out

def ceiling(mat, seed):
    rnd = random.Random(seed)
    out = []
    if mat == 'wood':
        x = -h2
        while x < h2 - 0.01:
            bw = min(rnd.uniform(0.22, 0.3), h2 - x)
            out += box(x + 0.01, -h2, 0.1, x + bw - 0.01, h2, 0.2 - rnd.uniform(0, 0.02), WOOD)
            x += bw
        for y in (-h2 + 0.1, -0.6, 0.6, h2 - 0.1):  # joists underneath
            out += box(-h2, y - 0.06, 0, h2, y + 0.06, 0.1, BEAM)
    elif mat == 'metal':
        out += box(-h2, -h2, 0.14, h2, h2, 0.2, METAL)
        for y in (-h2 + 0.05, -0.65, 0.65, h2 - 0.05):
            out += box(-h2, y - 0.05, 0, h2, y + 0.05, 0.14, DARK)
    else:
        out += box(-h2, -h2, 0.06, h2, h2, 0.2, STONE)
        for y in (-h2 + 0.1, 0, h2 - 0.1):
            out += box(-h2, y - 0.1, 0, h2, y + 0.1, 0.06, STONE)
    return out

def ramp(mat, seed):
    rnd = random.Random(seed)
    tex = {'wood': BEAM, 'metal': DARK, 'stone': STONE}[mat]
    top = {'wood': WOOD, 'metal': METAL, 'stone': STONE}[mat]
    out = wedge(-h2, -h2, h2, h2 - 0.02, 0.96, tex)
    # treads across the slope
    ang = math.degrees(math.atan2(1.0, S))
    n = 12
    for i in range(n):
        t = (i + 0.5) / n
        y = -h2 + S * t
        z = 1.0 * t - 0.015
        out += rbox(rnd.uniform(-0.02, 0.02), y, z, S - rnd.uniform(0, 0.08), S / n - 0.03, 0.05, top, rx=ang)
    out += box(-h2, h2 - 0.05, 0, h2, h2, 1.0, tex)
    return out

def door(mat):
    out = []
    if mat == 'wood':
        # vertical planks, a Z brace and iron hinge straps
        x = 0.0
        rnd = random.Random(7)
        while x < 1.16 - 0.01:
            bw = min(0.19, 1.16 - x)
            out += box(x + 0.005, -0.02, 0.02, x + bw - 0.005, 0.02, 2.17 - rnd.uniform(0, 0.03), WOOD)
            x += bw
        for z in (0.35, 1.85):
            out += box(0.06, -0.04, z, 1.1, -0.02, z + 0.14, BEAM)
        ang = math.degrees(math.atan2(1.36, 0.95))
        out += rbox(0.58, -0.03, 1.1, 1.62, 0.02, 0.13, BEAM, ry=-ang)
        for z in (0.38, 1.88):  # hinges and a handle
            out += box(0.0, -0.045, z + 0.02, 0.4, -0.035, z + 0.1, DARK)
        out += box(1.0, -0.04, 1.0, 1.06, 0.04, 1.2, DARK)
    else:
        out += box(0, -0.02, 0.02, 1.16, 0.02, 2.17, DARK)
        # frame border
        for (a, b, c, d) in ((0, 0.02, 1.16, 0.1), (0, 2.09, 1.16, 2.17), (0, 0.02, 0.08, 2.17), (1.08, 0.02, 1.16, 2.17), (0, 1.05, 1.16, 1.12)):
            out += box(a, -0.04, b, c, 0.04, d, DARK)
        # a barred peep window and bolts
        out += box(0.33, -0.045, 1.55, 0.83, -0.04, 1.85, METAL)
        for i in range(5):
            bx = 0.38 + i * 0.1
            out += box(bx, -0.04, 1.55, bx + 0.025, 0.04, 1.85, DARK)
        for bx in (0.12, 1.04):
            for bz in (0.15, 0.6, 1.5, 2.0):
                out += box(bx - 0.02, -0.04, bz - 0.02, bx + 0.02, -0.035, bz + 0.02, METAL)
        out += box(0.98, -0.04, 1.0, 1.04, 0.04, 1.18, METAL)
    return out

def garage():
    rnd = random.Random(9)
    out = []
    z = 0.02
    while z < 2.58 - 0.01:
        bh = min(0.22, 2.58 - z)
        out += rbox(rnd.uniform(-0.02, 0.02), 0, z + bh / 2, 3.16 - rnd.uniform(0, 0.05), 0.06, bh - 0.02, WOOD, ry=rnd.uniform(-0.4, 0.4))
        z += bh
    for x in (-1.2, 0, 1.2):  # iron straps
        out += box(x - 0.05, -0.05, 0.02, x + 0.05, -0.03, 2.58, DARK)
    out += box(-1.58, -0.05, 0.02, 1.58, 0.05, 0.12, DARK)
    return out

def windowbars(mat):
    out = []
    if mat == 'wood':
        out += box(-0.58, -0.03, 1.02, 0.58, 0.03, 1.1, BEAM)
        out += box(-0.58, -0.03, 1.9, 0.58, 0.03, 1.98, BEAM)
        ang = math.degrees(math.atan2(0.96, 1.16))
        out += rbox(0, -0.015, 1.5, 1.45, 0.03, 0.12, WOOD, ry=-ang)
        out += rbox(0, 0.015, 1.5, 1.45, 0.03, 0.12, WOOD, ry=ang)
        out += box(-0.04, -0.03, 1.02, 0.04, 0.03, 1.98, BEAM)
    else:
        out += box(-0.58, -0.02, 1.02, 0.58, 0.02, 1.08, DARK)
        out += box(-0.58, -0.02, 1.92, 0.58, 0.02, 1.98, DARK)
        out += box(-0.58, -0.02, 1.47, 0.58, 0.02, 1.52, DARK)
        for i in range(8):
            bx = -0.5 + i * (1.0 / 7)
            out += box(bx - 0.016, -0.02, 1.02, bx + 0.016, 0.02, 1.98, DARK)
    return out

def gate_frame():
    out = []
    for x0 in (-2.8, 2.3):  # thick posts with braces
        out += box(x0, -0.25, 0, x0 + 0.5, 0.25, 4.5, BEAM)
        out += box(x0 - 0.0, -0.25, 3.2, x0 + 0.5, 0.25, 3.32, DARK)
        out += box(x0 - 0.0, -0.25, 0.6, x0 + 0.5, 0.25, 0.72, DARK)
    out += box(-2.8, -0.25, 4.0, 2.8, 0.25, 4.5, BEAM)
    out += box(-2.8, -0.26, 4.15, 2.8, -0.24, 4.35, DARK)
    for x, sgn in ((-2.3, 1), (2.3, -1)):  # corner braces under the beam
        out += rbox(x + sgn * 0.35, 0, 3.7, 0.9, 0.2, 0.16, BEAM, ry=sgn * 45)
    for i in range(10):  # spikes along the top (inside the beam's height)
        x = -2.5 + i * (5.0 / 9)
        out += rbox(x, 0, 4.36, 0.07, 0.07, 0.28, DARK, ry=12 * (1 if i % 2 else -1))
    return out

def gate_door():
    out = []
    out += box(0.02, -0.03, 0.05, 4.54, 0.03, 3.95, METAL)
    for (a, b, c, d) in ((0, 0.05, 4.56, 0.2), (0, 3.8, 4.56, 3.95), (0, 0.05, 0.16, 3.95), (4.4, 0.05, 4.56, 3.95), (0, 1.95, 4.56, 2.07)):
        out += box(a, -0.06, b, c, -0.03, d, BEAM)
    for zc in (1.0, 2.95):
        ang = math.degrees(math.atan2(1.6, 4.2))
        out += rbox(2.28, -0.045, zc, 4.4, 0.03, 0.14, BEAM, ry=-ang)
    for zc in (0.4, 3.5):
        out += box(0.0, -0.065, zc, 0.6, -0.055, zc + 0.12, DARK)
    return out

def toolcupboard():
    out = []
    out += box(-0.48, -0.28, 0.08, 0.48, 0.3, 1.78, DARK)
    out += box(-0.5, -0.3, 1.74, 0.5, 0.3, 1.8, DARK)
    for x in (-0.46, 0.4):
        for y in (-0.26, 0.2):
            out += box(x, y, 0, x + 0.06, y + 0.06, 0.1, DARK)
    out += box(-0.47, -0.3, 0.12, -0.01, -0.28, 1.7, METAL)
    out += box(0.01, -0.3, 0.12, 0.47, -0.28, 1.7, METAL)
    out += box(-0.06, -0.3, 0.85, -0.02, -0.26, 1.05, DARK)
    out += box(0.02, -0.3, 0.85, 0.06, -0.26, 1.05, DARK)
    out += box(-0.04, -0.3, 0.88, 0.04, -0.27, 0.96, METAL)  # padlock
    return out

# Collision: the simple solid shapes (unchanged sizes).
def solid_wall(hole=None, height=H, width=S):
    w2 = width / 2
    if not hole:
        return box(-w2, -t2, 0, w2, t2, height)
    hx0, hz0, hx1, hz1 = hole
    parts = []
    if hx0 > -w2: parts += box(-w2, -t2, 0, hx0, t2, height)
    if hx1 < w2: parts += box(hx1, -t2, 0, w2, t2, height)
    if hz0 > 0: parts += box(hx0, -t2, 0, hx1, t2, hz0)
    if hz1 < height: parts += box(hx0, -t2, hz1, hx1, t2, height)
    return parts

def solid_bars(x0, z0, x1, z1, thick):
    return box(x0, -thick, z0, x1, thick, z1)

HOLES = {'doorway': (-0.6, 0, 0.6, 2.2), 'windowframe': (-0.6, 1.0, 0.6, 2.0), 'frame': (-1.6, 0, 1.6, 2.6)}
MATID = {'wood': 70, 'stone': 11, 'metal': 56}

PIECES = []  # (model, look faces, collision faces, material id)
seed = 100
for mat in ('wood', 'stone', 'metal'):
    seed += 10
    PIECES.append((f'wl_bp_foundation_{mat}', foundation(mat, seed), box(-h2, -h2, 0, h2, h2, 1.0), MATID[mat]))
    PIECES.append((f'wl_bp_wall_{mat}', styled_wall(mat, seed + 1), solid_wall(), MATID[mat]))
    PIECES.append((f'wl_bp_halfwall_{mat}', styled_wall(mat, seed + 2, height=H / 2), solid_wall(height=H / 2), MATID[mat]))
    for name, hole in HOLES.items():
        PIECES.append((f'wl_bp_{name}_{mat}', styled_wall(mat, seed + len(name), hole), solid_wall(hole), MATID[mat]))
    PIECES.append((f'wl_bp_ceiling_{mat}', ceiling(mat, seed + 3), box(-h2, -h2, 0, h2, h2, T), MATID[mat]))
    PIECES.append((f'wl_bp_ramp_{mat}', ramp(mat, seed + 4), wedge(-h2, -h2, h2, h2, 1.0), MATID[mat]))
PIECES += [
    ('wl_bp_door_wood', door('wood'), box(0, -0.04, 0.02, 1.16, 0.04, 2.17), 70),
    ('wl_bp_door_metal', door('metal'), box(0, -0.04, 0.02, 1.16, 0.04, 2.17), 56),
    ('wl_bp_garage_wood', garage(), box(-1.58, -0.05, 0.02, 1.58, 0.05, 2.58), 70),
    ('wl_bp_windowbar_wood', windowbars('wood'), solid_bars(-0.58, 1.02, 0.58, 1.98, 0.03), 70),
    ('wl_bp_windowbar_metal', windowbars('metal'), solid_bars(-0.58, 1.02, 0.58, 1.98, 0.02), 56),
    ('wl_bp_gate_frame', gate_frame(), box(-2.8, -0.25, 0, -2.3, 0.25, 4.5) + box(2.3, -0.25, 0, 2.8, 0.25, 4.5) + box(-2.8, -0.25, 4.0, 2.8, 0.25, 4.5), 70),
    ('wl_bp_gate_door', gate_door(), box(0, -0.06, 0.05, 4.56, 0.06, 3.95), 56),
    ('wl_bp_toolcupboard', toolcupboard(), box(-0.5, -0.3, 0, 0.5, 0.3, 1.8), 56),
]

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def tris_of(faces):
    out = []
    for item in faces:
        q = item[1]
        for a, b, c in ((0, 1, 2), (0, 2, 3)):
            if len({q[a], q[b], q[c]}) == 3:
                out.append((q[a], q[b], q[c]))
    return out

def extent(faces):
    pts = [p for item in faces for p in item[1]]
    return (min(p[0] for p in pts), min(p[1] for p in pts), min(p[2] for p in pts)), \
           (max(p[0] for p in pts), max(p[1] for p in pts), max(p[2] for p in pts))

def vec(tag, v, w=None):
    s = f'<{tag} x="{f(v[0])}" y="{f(v[1])}" z="{f(v[2])}"'
    return s + (f' w="{f(w)}" />' if w is not None else ' />')

SHADER_PARAMS = '''     <Item name="matMaterialColorScale" type="Vector" x="1" y="0" z="0" w="1" />
     <Item name="HardAlphaBlend" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="useTessellation" type="Vector" x="0" y="0" z="0" w="0" />
     <Item name="wetnessMultiplier" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="globalAnimUV1" type="Vector" x="0" y="1" z="0" w="0" />
     <Item name="globalAnimUV0" type="Vector" x="1" y="0" z="0" w="0" />'''

# flags 32 and physicsDictionary = the model itself: the game then uses the
# collision inside the model file (without it, you walk through).
archetypes = []
for model, look, solid, mid in PIECES:
    # the size the game sees is the collision's (unchanged), whatever the details
    mn, mx = extent(solid)
    c = tuple((mn[i] + mx[i]) / 2 for i in range(3))
    r = math.dist(mn, mx) / 2
    groups = {}
    for n, q, tex in look:
        groups.setdefault(tex, []).append((n, q))
    shaders, geoms = [], []
    for si, (tex, faces) in enumerate(groups.items()):
        shaders.append(f'''   <Item>
    <Name>default</Name>
    <FileName>default.sps</FileName>
    <RenderBucket value="0" />
    <Parameters>
     <Item name="DiffuseSampler" type="Texture">
      <Name>{tex}</Name>
     </Item>
{SHADER_PARAMS}
    </Parameters>
   </Item>''')
        verts, idx = [], []
        for n, q in faces:
            base = len(verts)
            for p in q:
                verts.append((p, n, uv(p, n)))
            for a, b, cc in ((0, 1, 2), (0, 2, 3)):
                if len({q[a], q[b], q[cc]}) == 3:
                    idx += [base + a, base + b, base + cc]
        gmn = tuple(min(v[0][i] for v in verts) for i in range(3)); gmx = tuple(max(v[0][i] for v in verts) for i in range(3))
        rows = '\n'.join(f'       {f(p[0])} {f(p[1])} {f(p[2])}   {f(nn[0])} {f(nn[1])} {f(nn[2])}   255 255 255 255   {f(t[0])} {f(t[1])}'
                         for p, nn, t in verts)
        ids = '\n'.join('       ' + ' '.join(str(i) for i in idx[k:k + 24]) for k in range(0, len(idx), 24))
        geoms.append(f'''    <Item>
     <ShaderIndex value="{si}" />
     {vec('BoundingBoxMin', gmn, gmn[0])}
     {vec('BoundingBoxMax', gmx, gmx[0])}
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
    </Item>''')
    # collision triangles
    cverts, cindex, polys = [], {}, []
    for tri in tris_of(solid):
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
    flags = '''  <MaterialIndex value="0" />
  <MaterialColourIndex value="0" />
  <ProceduralID value="0" />
  <RoomID value="0" />
  <PedDensity value="0" />
  <UnkFlags value="0" />
  <PolyFlags value="0" />
  <UnkType value="1" />'''
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
 <FlagsHigh value="{len(groups)}" />
 <FlagsMed value="0" />
 <FlagsLow value="0" />
 <FlagsVlow value="0" />
 <ShaderGroup>
  <Shaders>
{chr(10).join(shaders)}
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
{chr(10).join(geoms)}
   </Geometries>
  </Item>
 </DrawableModelsHigh>
 <Bounds type="Composite">
  {common}
  <Margin value="0" />
  <Volume value="{f(vol)}" />
  <Inertia x="1" y="1" z="1" />
{flags}
  <Children>
   <Item type="Geometry">
  {common}
    <Margin value="0.04" />
    <Volume value="{f(vol)}" />
    <Inertia x="1" y="1" z="1" />
{flags}
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
   <flags value="32" />
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
   <physicsDictionary>{model}</physicsDictionary>
   <assetType>ASSET_TYPE_DRAWABLE</assetType>
   <assetName>{model}</assetName>
   <extensions />
  </Item>''')

with open(os.path.join(OUT, 'wl_buildprops.ytyp.xml'), 'w', encoding='utf-8') as fh:
    fh.write('<?xml version="1.0" encoding="UTF-8"?>\n<CMapTypes>\n <extensions />\n <archetypes>\n' + '\n'.join(archetypes)
             + '\n </archetypes>\n <name>wl_buildprops</name>\n <dependencies />\n <compositeEntityTypes itemType="CCompositeEntityType" />\n</CMapTypes>\n')

print(len(PIECES), 'models,', len(TEXTURES), 'textures written to', OUT)
