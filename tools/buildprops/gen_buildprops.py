"""Wasteland building props generator.

Writes CodeWalker XML for every base-building piece (model, collision,
archetypes) plus original procedural textures and normal maps, ready for
`wlprops build`. Everything is made from scratch (shapes and code-painted
textures), so the result can be shared freely with Wasteland Core.

usage: python gen_buildprops.py <outDir>
"""
import io, math, os, random, struct, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
TXD = 'wl_buildprops'
TEX = 1024   # diffuse
NRM = 512    # normal maps

# ---------------------------------------------------------------------------
# Noise helpers (tileable: every layer is wrapped before blurring/resizing)
# ---------------------------------------------------------------------------

def value_noise(size, cells, seed, sx=1, sy=1):
    """Smooth tileable noise: random cells, wrapped, scaled up bicubic. sx/sy stretch."""
    rnd = random.Random(seed)
    cw, ch = max(2, cells // sx), max(2, cells // sy)
    small = Image.new('L', (cw, ch))
    small.putdata([rnd.randint(0, 255) for _ in range(cw * ch)])
    # wrap by tiling 3x3 and cropping the middle after resize
    big = Image.new('L', (cw * 3, ch * 3))
    for i in range(3):
        for j in range(3):
            big.paste(small, (i * cw, j * ch))
    up = big.resize((size * 3, size * 3), Image.BICUBIC)
    return up.crop((size, size, size * 2, size * 2))

def fbm(size, seed, base=4, octaves=5, sx=1, sy=1, falloff=0.55):
    """Fractal noise: octaves of value noise blended together, contrast stretched."""
    acc, total, amp = None, 0.0, 1.0
    for o in range(octaves):
        layer = value_noise(size, base * (2 ** o), seed + o * 101, sx, sy)
        if acc is None:
            acc, total = layer, amp
        else:
            acc = Image.blend(acc, layer, amp / (total + amp))
            total += amp
        amp *= falloff
    return ImageOps.autocontrast(acc)

def colorize(gray, dark, light):
    lut = []
    for c in range(3):
        lut += [max(0, min(255, int(dark[c] + (light[c] - dark[c]) * i / 255))) for i in range(256)]
    return Image.merge('RGB', (gray, gray, gray)).point(lut)

def mul(img, gray, strength):
    """Darken img where gray is dark (multiply), strength 0..1."""
    m = gray.point(lambda v: int(255 - (255 - v) * strength))
    return ImageChops.multiply(img, Image.merge('RGB', (m, m, m)))

def over(img, color_img, mask):
    return Image.composite(color_img, img, mask)

def desaturate(img, amount):
    g = ImageOps.grayscale(img).convert('RGB')
    return Image.blend(img, g, amount)

def tile_draw(size, fn):
    """Draw on a 3x3 canvas and fold it back, so marks near edges wrap."""
    big = Image.new('RGBA', (size * 3, size * 3), (0, 0, 0, 0))
    fn(ImageDraw.Draw(big), size)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    for i in range(3):
        for j in range(3):
            out.alpha_composite(big.crop((i * size, j * size, (i + 1) * size, (j + 1) * size)))
    return out

# ---------------------------------------------------------------------------
# Materials: diffuse + height (for the normal map)
# ---------------------------------------------------------------------------

def weathered_wood(seed, boards=8, palette=((62, 54, 44), (150, 136, 114))):
    rnd = random.Random(seed)
    S = TEX
    img = Image.new('RGB', (S, S))
    height = Image.new('L', (S, S), 200)
    hd = ImageDraw.Draw(height)
    bh = S // boards
    grain_all = fbm(S, seed, base=3, octaves=5, sx=1, sy=1)
    for i in range(boards):
        y0 = i * bh
        g = fbm(S, seed * 7 + i, base=2, octaves=5, sx=1, sy=1).resize((S * 6, bh), Image.BICUBIC)
        off = rnd.randint(0, S * 5)
        g = g.crop((off, 0, off + S, bh))
        fine = Image.effect_noise((S, bh), 40).resize((S // 4, bh), Image.BICUBIC).resize((S, bh), Image.BICUBIC)
        g = Image.blend(g, fine, 0.35)
        shift = rnd.randint(-14, 10)
        grey = rnd.random() < 0.35
        dark = tuple(c + shift for c in palette[0]); light = tuple(c + shift for c in palette[1])
        if grey:
            dark = (dark[0] - 4, dark[1], dark[2] + 4); light = (light[0] - 10, light[1] - 2, light[2] + 6)
        board = colorize(g, dark, light)
        # darker towards the board's lower edge (dirt sits there)
        grad = Image.linear_gradient('L').resize((S, bh)).point(lambda v: 255 - int(v * 0.35))
        board = mul(board, grad.point(lambda v: v), 0.6)
        img.paste(board, (0, y0))
        # knots
        for _ in range(rnd.randint(0, 2)):
            kx, ky = rnd.randint(30, S - 30), y0 + rnd.randint(bh // 4, 3 * bh // 4)
            kd = ImageDraw.Draw(img)
            for r in range(14, 2, -3):
                c = 40 + r * 3
                kd.ellipse((kx - r * 2, ky - r, kx + r * 2, ky + r), outline=(c, c - 8, c - 16), width=2)
        # gap between boards (deep in the height map)
        ImageDraw.Draw(img).rectangle((0, y0, S, y0 + 4), fill=(18, 15, 12))
        hd.rectangle((0, y0, S, y0 + 5), fill=40)
        hd.rectangle((0, y0 + 5, S, y0 + 10), fill=150)
        # nails with a rust run
        for nx in (rnd.randint(20, 60), rnd.randint(S // 2 - 30, S // 2 + 30), S - rnd.randint(20, 60)):
            ny = y0 + bh // 2 + rnd.randint(-8, 8)
            d = ImageDraw.Draw(img)
            d.ellipse((nx - 5, ny - 5, nx + 5, ny + 5), fill=(42, 36, 32))
            hd.ellipse((nx - 5, ny - 5, nx + 5, ny + 5), fill=230)
            run = Image.new('L', (S, S), 0)
            ImageDraw.Draw(run).line((nx, ny, nx + rnd.randint(-2, 2), ny + rnd.randint(30, 90)), fill=110, width=5)
            img = over(img, Image.new('RGB', (S, S), (92, 52, 28)), run.filter(ImageFilter.GaussianBlur(3)))
    # grain into the height map too
    height = ImageChops.multiply(height, grain_all.point(lambda v: 170 + v // 3))
    # large-scale dirt and water stains
    dirt = fbm(S, seed + 50, base=3, octaves=4)
    img = mul(img, dirt.point(lambda v: min(255, v + 60)), 0.55)
    mold = fbm(S, seed + 60, base=4, octaves=4).point(lambda v: max(0, v - 165) * 3)
    img = over(img, Image.new('RGB', (S, S), (58, 64, 40)), mold.point(lambda v: v // 3))
    return desaturate(img, 0.18), height

def corrugated(seed, ridges=12, base=((88, 92, 94), (162, 165, 164))):
    rnd = random.Random(seed)
    S = TEX
    ridge = Image.new('L', (S, 1))
    ridge.putdata([int(128 + 127 * math.sin(x / S * math.pi * 2 * ridges)) for x in range(S)])
    ridge = ridge.resize((S, S))
    zinc = fbm(S, seed, base=4, octaves=6)
    shade = Image.blend(zinc, ridge, 0.25)
    img = colorize(shade, base[0], base[1])
    # rust: patches (fbm threshold) with darker cores, and streaks running down from the top
    rust = fbm(S, seed + 9, base=3, octaves=6)
    patch = rust.point(lambda v: max(0, min(255, (v - 150) * 4)))
    core = rust.point(lambda v: max(0, min(255, (v - 185) * 5)))
    rust_col = colorize(fbm(S, seed + 3, base=16, octaves=3), (78, 40, 22), (142, 78, 40))
    img = over(img, rust_col, patch)
    img = over(img, colorize(fbm(S, seed + 4, base=16, octaves=3), (44, 24, 14), (82, 44, 24)), core)
    streaks = tile_draw(S, lambda d, s: [d.line((x, y, x + rnd.randint(-3, 3), y + rnd.randint(80, 320)),
                                                fill=(110, 56, 26, rnd.randint(40, 110)), width=rnd.randint(2, 7))
                                         for x, y in [(rnd.randint(s, 2 * s), s + rnd.randint(0, 60)) for _ in range(40)]])
    base_img = img.convert('RGBA'); base_img.alpha_composite(streaks.filter(ImageFilter.GaussianBlur(2)))
    img = base_img.convert('RGB')
    dirt = fbm(S, seed + 20, base=2, octaves=4)
    img = mul(img, dirt.point(lambda v: min(255, v + 80)), 0.5)
    height = ridge.point(lambda v: 60 + v * 0.6)
    return desaturate(img, 0.1), height.convert('L')

def blocks(seed):
    rnd = random.Random(seed)
    S = TEX
    rows = 8; rh = S // rows
    img = Image.new('RGB', (S, S), (74, 72, 68))
    height = Image.new('L', (S, S), 60)
    speck = fbm(S, seed, base=24, octaves=3)
    for r in range(rows):
        x = -rnd.randint(0, 120) if r % 2 else 0
        while x < S:
            bw = rnd.choice([S // 4, S // 4, S // 5])
            sh = rnd.randint(-12, 12)
            tone = colorize(speck, (96 + sh, 95 + sh, 91 + sh), (152 + sh, 150 + sh, 144 + sh)).crop((0, 0, S, S))
            box = (x + 4, r * rh + 4, x + bw - 4, r * rh + rh - 4)
            m = Image.new('L', (S, S), 0); ImageDraw.Draw(m).rectangle(box, fill=255)
            img = over(img, tone, m)
            ImageDraw.Draw(height).rectangle(box, fill=210)
            x += bw
    stains = tile_draw(S, lambda d, s: [d.line((x, y, x + rnd.randint(-4, 4), y + rnd.randint(100, 380)),
                                               fill=(40, 40, 34, rnd.randint(30, 80)), width=rnd.randint(6, 18))
                                        for x, y in [(rnd.randint(s, 2 * s), s + rnd.randint(0, s)) for _ in range(18)]])
    b = img.convert('RGBA'); b.alpha_composite(stains.filter(ImageFilter.GaussianBlur(5))); img = b.convert('RGB')
    dirt = fbm(S, seed + 5, base=3, octaves=4)
    img = mul(img, dirt.point(lambda v: min(255, v + 70)), 0.5)
    moss = fbm(S, seed + 7, base=5, octaves=4).point(lambda v: max(0, v - 175) * 3)
    img = over(img, colorize(speck, (40, 52, 30), (80, 96, 54)), moss.point(lambda v: v // 2))
    height = height.filter(ImageFilter.GaussianBlur(2))
    return desaturate(img, 0.15), height

def painted_steel(seed):
    rnd = random.Random(seed)
    S = TEX
    paint = colorize(fbm(S, seed, base=6, octaves=5), (40, 46, 42), (78, 86, 78))
    rust = fbm(S, seed + 2, base=4, octaves=6)
    chips = rust.point(lambda v: max(0, min(255, (v - 168) * 5)))
    img = over(paint, colorize(fbm(S, seed + 3, base=20, octaves=3), (70, 36, 18), (128, 70, 36)), chips)
    sc = tile_draw(S, lambda d, s: [d.line((x, y, x + rnd.randint(-120, 120), y + rnd.randint(-20, 20)),
                                           fill=(120, 124, 118, rnd.randint(40, 100)), width=1)
                                    for x, y in [(rnd.randint(s, 2 * s), rnd.randint(s, 2 * s)) for _ in range(120)]])
    b = img.convert('RGBA'); b.alpha_composite(sc); img = b.convert('RGB')
    for y in range(0, S, S // 4):  # panel seams
        ImageDraw.Draw(img).rectangle((0, y, S, y + 4), fill=(24, 26, 24))
    dirt = fbm(S, seed + 9, base=3, octaves=4)
    img = mul(img, dirt.point(lambda v: min(255, v + 80)), 0.5)
    height = Image.new('L', (S, S), 180)
    for y in range(0, S, S // 4):
        ImageDraw.Draw(height).rectangle((0, y, S, y + 5), fill=60)
    height = ImageChops.subtract(height, chips.point(lambda v: v // 4))
    return img, height

def beam_wood(seed):
    S = TEX
    g = fbm(S, seed, base=2, octaves=6).resize((S // 10, S), Image.BICUBIC).resize((S, S), Image.BICUBIC)
    g = Image.blend(g, fbm(S, seed + 1, base=6, octaves=4), 0.3)
    img = colorize(g, (30, 24, 18), (92, 78, 62))
    rnd = random.Random(seed)
    cracks = tile_draw(S, lambda d, s: [d.line((x, y, x + rnd.randint(-5, 5), y + rnd.randint(60, 260)),
                                               fill=(14, 11, 8, 200), width=rnd.randint(1, 3))
                                        for x, y in [(rnd.randint(s, 2 * s), rnd.randint(s, 2 * s)) for _ in range(30)]])
    b = img.convert('RGBA'); b.alpha_composite(cracks); img = b.convert('RGB')
    dirt = fbm(S, seed + 3, base=3, octaves=4)
    img = mul(img, dirt.point(lambda v: min(255, v + 70)), 0.5)
    height = g.point(lambda v: 120 + v // 3)
    return desaturate(img, 0.2), height

def grunge(img, seed, blood=1, spray=0):
    """Dried blood (dark, irregular, faded) and faded spray paint with overspray."""
    rnd = random.Random(seed)
    S = img.size[0]
    out = img.convert('RGBA')
    for _ in range(blood):
        cx, cy = rnd.randint(S // 6, 5 * S // 6), rnd.randint(S // 6, 5 * S // 6)
        n = fbm(S, rnd.randint(0, 99999), base=12, octaves=4)
        blob = Image.new('L', (S, S), 0)
        ImageDraw.Draw(blob).ellipse((cx - 90, cy - 60, cx + 90, cy + 70), fill=255)
        blob = blob.filter(ImageFilter.GaussianBlur(40))
        mask = ImageChops.multiply(blob, n.point(lambda v: 255 if v > 140 else 0)).point(lambda v: int(v * 0.55))
        for _ in range(4):  # runs
            x = cx + rnd.randint(-60, 60)
            ImageDraw.Draw(mask).line((x, cy, x + rnd.randint(-3, 3), cy + rnd.randint(60, 180)), fill=90, width=rnd.randint(3, 6))
        mask = mask.filter(ImageFilter.GaussianBlur(1.5))
        col = Image.new('RGBA', (S, S), (54, 16, 12, 255))
        out = Image.composite(col, out, mask)
    for _ in range(spray):
        col = rnd.choice([(128, 34, 28), (150, 140, 120)])
        cx, cy = rnd.randint(S // 4, 3 * S // 4), rnd.randint(S // 4, 3 * S // 4)
        s = rnd.randint(70, 110)
        m = Image.new('L', (S, S), 0)
        d = ImageDraw.Draw(m)
        d.line((cx - s, cy - s, cx + s, cy + s), fill=255, width=16)
        d.line((cx - s, cy + s, cx + s, cy - s), fill=255, width=16)
        for _ in range(5):
            x = cx + rnd.randint(-s, s)
            d.line((x, cy + rnd.randint(-s, s), x, cy + s + rnd.randint(20, 70)), fill=160, width=3)
        over_spray = m.filter(ImageFilter.GaussianBlur(6)).point(lambda v: v // 3)
        m = ImageChops.lighter(m.filter(ImageFilter.GaussianBlur(1)), over_spray)
        worn = fbm(S, rnd.randint(0, 9999), base=10, octaves=3).point(lambda v: 255 if v > 95 else 60)
        m = ImageChops.multiply(m, worn).point(lambda v: int(v * 0.5))
        out = Image.composite(Image.new('RGBA', (S, S), col + (255,)), out, m)
    return out.convert('RGB')

def normal_map(height, strength=3.0):
    h = height.resize((NRM, NRM), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8))
    px = h.load(); w = NRM
    out = Image.new('RGB', (w, w)); o = out.load()
    for y in range(w):
        for x in range(w):
            dx = (px[(x + 1) % w, y] - px[(x - 1) % w, y]) / 255.0 * strength
            dy = (px[x, (y + 1) % w] - px[x, (y - 1) % w]) / 255.0 * strength
            nx, ny, nz = -dx, dy, 1.0
            l = math.sqrt(nx * nx + ny * ny + nz * nz)
            o[x, y] = (int((nx / l * 0.5 + 0.5) * 255), int((ny / l * 0.5 + 0.5) * 255), int((nz / l * 0.5 + 0.5) * 255))
    return out

def write_dds(img, path):
    """Uncompressed BGRA8 DDS with a full mip chain."""
    img = img.convert('RGBA')
    mips = [img]
    while mips[-1].size[0] > 4:
        s = mips[-1].size[0] // 2
        mips.append(mips[-1].resize((s, s), Image.LANCZOS))
    w, h = img.size
    flags = 0x1 | 0x2 | 0x4 | 0x8 | 0x1000 | 0x20000
    pf = struct.pack('<IIIIIIII', 32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    caps = 0x1000 | 0x8 | 0x400000
    header = struct.pack('<4sIIIIIII', b'DDS ', 124, flags, h, w, w * 4, 0, len(mips)) + b'\0' * 44 + pf + struct.pack('<IIIII', caps, 0, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(header)
        for m in mips:
            r, g, b, a = m.split()
            f.write(Image.merge('RGBA', (b, g, r, a)).tobytes())
    return len(mips)

wood_d, wood_h = weathered_wood(11)
beam_d, beam_h = beam_wood(55)
metal_d, metal_h = corrugated(22)
stone_d, stone_h = blocks(33)
dark_d, dark_h = painted_steel(44)
TEXTURES = {
    'wlbp_wood': grunge(wood_d, 101, blood=1, spray=1),
    'wlbp_beam': beam_d,
    'wlbp_metal': grunge(metal_d, 202, blood=1, spray=0),
    'wlbp_stone': grunge(stone_d, 303, blood=1, spray=1),
    'wlbp_darkmetal': grunge(dark_d, 404, blood=1, spray=0),
}
HEIGHTS = {'wlbp_wood': wood_h, 'wlbp_beam': beam_h, 'wlbp_metal': metal_h, 'wlbp_stone': stone_h, 'wlbp_darkmetal': dark_h}
ALL_TEX = dict(TEXTURES)
for k, hgt in HEIGHTS.items():
    ALL_TEX[k + '_n'] = normal_map(hgt, 4.0 if k == 'wlbp_metal' else 3.0)

items = []
for name, img in ALL_TEX.items():
    levels = write_dds(img, os.path.join(OUT, name + '.dds'))
    if not name.endswith('_n'):
        img.resize((256, 256)).save(os.path.join(OUT, name + '_preview.png'))
    items.append(f'''  <Item>
   <Name>{name}</Name>
   <Unk32 value="128" />
   <Usage>{'NORMAL' if name.endswith('_n') else 'DIFFUSE'}</Usage>
   <UsageFlags>UNK24</UsageFlags>
   <ExtraFlags value="0" />
   <Width value="{img.size[0]}" />
   <Height value="{img.size[1]}" />
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
        out += box(bx, -0.097, bz, bx + rnd.uniform(0.25, 0.45), -0.085, bz + 0.22, STONE)
    # a footing along the bottom
    out += box(x0, -0.1, z0, x1, 0.1, z0 + 0.12, STONE)  # footing (main block is 0.085)
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
    out += box(hx0 - 0.08, -0.106, hz0, hx0, 0.106, hz1 + 0.08, tt)
    out += box(hx1, -0.106, hz0, hx1 + 0.08, 0.106, hz1 + 0.08, tt)
    out += box(hx0 - 0.084, -0.108, hz1, hx1 + 0.084, 0.108, hz1 + 0.1, tt)
    if hz0 > 0:  # a sill
        out += box(hx0 - 0.12, -0.11, hz0 - 0.06, hx1 + 0.12, 0.11, hz0, tt)
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
            out += box(i * 0.55 - 0.015, -h2 + 0.1, 1.0, i * 0.55 + 0.015, h2 - 0.1, 1.006, DARK)
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
        out += box(x0 - 0.008, -0.258, 3.2, x0 + 0.508, 0.258, 3.32, DARK)
        out += box(x0 - 0.008, -0.258, 0.6, x0 + 0.508, 0.258, 0.72, DARK)
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


def crate():
    """Small storage: a wooden crate, planks on beam corners."""
    rnd = random.Random(21)
    out = box(-0.47, -0.27, 0.03, 0.47, 0.27, 0.6, BEAM)
    for side in (-1, 1):
        z = 0.04
        while z < 0.6:
            bh = min(0.13, 0.62 - z)
            out += box(-0.46, side * 0.3 - (0.03 if side > 0 else 0), z, 0.46, side * 0.3 + (0.03 if side < 0 else 0), z + bh - 0.012, WOOD)
            z += bh
    for x0 in (-0.5, 0.44):
        out += box(x0, -0.3, 0.0, x0 + 0.06, 0.3, 0.62, BEAM)
    x = -0.46
    while x < 0.46:
        bw = min(0.16, 0.46 - x)
        out += box(x + 0.006, -0.28, 0.6, x + bw - 0.006, 0.28, 0.64 - rnd.uniform(0, 0.01), WOOD)
        x += bw
    out += box(-0.06, -0.31, 0.42, 0.06, -0.3, 0.52, DARK)  # latch
    return out

def container():
    """Large storage: a corrugated metal box with a lid, frame and handles."""
    out = box(-0.78, -0.33, 0.06, 0.78, 0.33, 1.08, DARK)
    for side in (-1, 1):
        out += box(-0.76, side * 0.35 - (0.02 if side > 0 else 0), 0.08, 0.76, side * 0.35 + (0.02 if side < 0 else 0), 1.06, METAL)
        out += box(side * 0.8 - (0.02 if side > 0 else 0), -0.33, 0.08, side * 0.8 + (0.02 if side < 0 else 0), 0.33, 1.06, METAL)
    for x0 in (-0.8, 0.74):
        for y0 in (-0.35, 0.29):
            out += box(x0, y0, 0, x0 + 0.06, y0 + 0.06, 1.12, DARK)
    out += box(-0.8, -0.35, 1.06, 0.8, 0.35, 1.14, DARK)  # lid
    out += box(-0.2, -0.37, 0.8, 0.2, -0.35, 0.86, DARK)  # handle
    out += box(-0.04, -0.37, 0.9, 0.04, -0.35, 1.0, METAL)  # padlock
    return out

def locker():
    """Weapon locker: a tall steel cabinet with two doors, vents and a padlock."""
    out = box(-0.38, -0.2, 0.04, 0.38, 0.22, 1.86, DARK)
    out += box(-0.4, -0.22, 1.82, 0.4, 0.24, 1.9, DARK)
    out += box(-0.4, -0.22, 0, 0.4, 0.24, 0.06, DARK)
    out += box(-0.37, -0.23, 0.08, -0.01, -0.21, 1.8, METAL)
    out += box(0.01, -0.23, 0.08, 0.37, -0.21, 1.8, METAL)
    for z in (1.5, 1.56, 1.62):  # vents
        out += box(-0.3, -0.24, z, -0.08, -0.23, z + 0.025, DARK)
        out += box(0.08, -0.24, z, 0.3, -0.23, z + 0.025, DARK)
    out += box(-0.05, -0.25, 0.9, -0.02, -0.21, 1.1, DARK)
    out += box(0.02, -0.25, 0.9, 0.05, -0.21, 1.1, DARK)
    out += box(-0.035, -0.26, 0.95, 0.035, -0.24, 1.03, METAL)
    return out


# ---------------------------------------------------------------------------
# Multiple floors: stairs and a ceiling with a ladder hatch
# Floor to floor = wall height + ceiling thickness = 3.2 m.
# ---------------------------------------------------------------------------

FLOOR = H + T  # 3.2

def slope_faces(x0, x1, y_lo, y_hi, z_lo, z_hi, thick, tex):
    """A sloped slab: its top rises from (y_lo, z_lo) to (y_hi, z_hi)."""
    def P(y, z): return y, z
    a = [(x0, y_lo, z_lo), (x1, y_lo, z_lo), (x1, y_hi, z_hi), (x0, y_hi, z_hi)]
    b = [(x, y, z - thick) for x, y, z in a]
    dy, dz = y_hi - y_lo, z_hi - z_lo
    l = math.hypot(dy, dz)
    sgn = 1 if dy > 0 else -1
    n_top = (0.0, -dz / l * sgn, abs(dy) / l)
    n_bot = (0.0, -n_top[1], -n_top[2])
    faces = []
    top = a if sgn > 0 else [a[1], a[0], a[3], a[2]]
    faces.append((n_top, top, tex))
    bot = [b[3], b[2], b[1], b[0]] if sgn > 0 else [b[2], b[3], b[0], b[1]]
    faces.append((n_bot, bot, tex))
    faces.append(((1, 0, 0), [b[1], b[2], a[2], a[1]] if sgn > 0 else [b[2], b[1], a[1], a[2]], tex))
    faces.append(((-1, 0, 0), [b[3], b[0], a[0], a[3]] if sgn > 0 else [b[0], b[3], a[3], a[0]], tex))
    return faces

def stairs(mat, seed):
    rnd = random.Random(seed)
    tread = {'wood': WOOD, 'stone': STONE, 'metal': DARK}[mat]
    side = {'wood': BEAM, 'stone': STONE, 'metal': DARK}[mat]
    out = []
    half = FLOOR / 2
    # flight A: left half, up towards +y; landing at the back; flight B: right half, up towards -y
    fa = (-1.75, -0.05, -1.55, 0.75, 0.0, half)
    fb = (0.05, 1.75, 0.75, -1.8, half, FLOOR)
    for (x0, x1, ylo, yhi, zlo, zhi) in (fa, fb):
        steps = 10
        run = (yhi - ylo) / steps
        rise = (zhi - zlo) / steps
        for i in range(steps):
            y0 = ylo + run * i
            z = zlo + rise * (i + 1)
            ya, yb = sorted((y0, y0 + run))
            out += box(x0 + 0.02, ya, z - 0.06, x1 - 0.02, yb + (0.02 if run > 0 else 0), z - rnd.uniform(0, 0.012), tread)
            out += box(x0 + 0.04, ya, zlo if mat == 'stone' else z - 0.24, x1 - 0.04, yb, z - 0.06, side if mat != 'stone' else STONE)
        # stringers (side beams) along the flight
        for sx in (x0, x1 - 0.08):
            ang = math.degrees(math.atan2(zhi - zlo, abs(yhi - ylo)))
            cy, cz = (ylo + yhi) / 2, (zlo + zhi) / 2 - 0.12
            out += rbox(sx + 0.04, cy, cz, 0.08, math.hypot(yhi - ylo, zhi - zlo), 0.22, side, rx=ang if yhi > ylo else -ang)
        # handrail on the outer side
        rx_ = x0 + 0.04 if x0 < 0 else x1 - 0.04
        ang = math.degrees(math.atan2(zhi - zlo, abs(yhi - ylo)))
        out += rbox(rx_, (ylo + yhi) / 2, (zlo + zhi) / 2 + 0.95, 0.06, math.hypot(yhi - ylo, zhi - zlo), 0.06, side, rx=ang if yhi > ylo else -ang)
        for t in (0.1, 0.5, 0.9):
            py = ylo + (yhi - ylo) * t; pz = zlo + (zhi - zlo) * t
            out += box(rx_ - 0.03, py - 0.03, pz, rx_ + 0.03, py + 0.03, pz + 0.95, side)
    # landing with posts
    out += box(-1.78, 0.75, half - 0.12, 1.78, 1.78, half, tread)
    for px in (-1.76, 1.68):
        for py in (0.78, 1.7):
            out += box(px, py, 0, px + 0.08, py + 0.08, half - 0.12, side)
    out += box(-1.78, 1.72, half, 1.78, 1.78, half + 0.95, side)  # back rail
    out += box(0.05, -2.0, FLOOR - 0.1, 1.75, -1.8, FLOOR, tread)    # top step onto the next floor
    return out

HOLE = (0.8, -1.8, 1.8, -0.8)   # x0, y0, x1, y1 of the hatch opening

def hatch(mat, seed):
    rnd = random.Random(seed)
    top = {'wood': WOOD, 'stone': STONE, 'metal': METAL}[mat]
    under = {'wood': BEAM, 'stone': STONE, 'metal': DARK}[mat]
    hx0, hy0, hx1, hy1 = HOLE
    out = []
    regions = [(-h2, -h2, hx0, h2), (hx1, -h2, h2, h2), (hx0, -h2, hx1, hy0), (hx0, hy1, hx1, h2)]
    for (x0, y0, x1, y1) in regions:
        if mat == 'wood':
            x = x0
            while x < x1 - 0.01:
                bw = min(rnd.uniform(0.22, 0.3), x1 - x)
                out += box(x + 0.01, y0, 0.1, x + bw - 0.01, y1, 0.2 - rnd.uniform(0, 0.02), top)
                x += bw
        else:
            out += box(x0, y0, 0.1 if mat == 'stone' else 0.14, x1, y1, 0.2, top)
    for y in (-h2 + 0.1, -0.6, 0.6, h2 - 0.1):
        if not (hy0 - 0.06 < y < hy1 + 0.06):
            out += box(-h2, y - 0.06, 0, h2, y + 0.06, 0.1, under)
        else:
            out += box(-h2, y - 0.06, 0, hx0, y + 0.06, 0.1, under)
            out += box(hx1, y - 0.06, 0, h2, y + 0.06, 0.1, under)
    # trim round the opening
    out += box(hx0 - 0.06, hy0 - 0.06, 0, hx0, hy1 + 0.06, 0.22, under)
    out += box(hx1, hy0 - 0.06, 0, hx1 + 0.06, hy1 + 0.06, 0.22, under)
    out += box(hx0, hy0 - 0.06, 0, hx1, hy0, 0.22, under)
    out += box(hx0, hy1, 0, hx1, hy1 + 0.06, 0.22, under)
    # the ladder, against the opening's -y side, down to the floor below
    ly = hy0 + 0.08
    for lx in (hx0 + 0.18, hx1 - 0.18):
        out += box(lx - 0.03, ly - 0.03, -H, lx + 0.03, ly + 0.03, 0.2, DARK if mat != 'wood' else BEAM)
    z = -H + 0.3
    while z < 0.1:
        out += box(hx0 + 0.15, ly - 0.02, z, hx1 - 0.15, ly + 0.02, z + 0.04, DARK if mat != 'wood' else BEAM)
        z += 0.3
    return out
# ---------------------------------------------------------------------------
# Collision: solid boxes (like GTA's own thin props: bullets and players hit
# them), a triangle mesh only for the ramp's slope. Sizes never change.
# ---------------------------------------------------------------------------

def cbox(x0, y0, z0, x1, y1, z1):
    return [('box', (x0, y0, z0, x1, y1, z1))]

def slope_box(x0, x1, y_lo, y_hi, z_lo, z_hi, thick):
    """A solid tilted slab whose top runs from (y_lo, z_lo) to (y_hi, z_hi):
    a box turned about x (GTA's own props use boxes like this)."""
    dy, dz = y_hi - y_lo, z_hi - z_lo
    length = math.hypot(dy, dz)
    a = math.atan2(dz, dy)                      # turn of the box's y axis towards z
    yax = (0.0, math.cos(a), math.sin(a))
    zax = (0.0, -math.sin(a), math.cos(a))
    if zax[2] < 0:                              # keep the top facing up (and the turn a true rotation)
        yax = (0.0, -yax[1], -yax[2])
        zax = (0.0, -zax[1], -zax[2])
    mid = ((x0 + x1) / 2, (y_lo + y_hi) / 2, (z_lo + z_hi) / 2)
    c = tuple(mid[i] - zax[i] * thick / 2 for i in range(3))
    return [('rbox', (c, ((x1 - x0) / 2, length / 2, thick / 2), yax, zax))]

def solid_wall(hole=None, height=H, width=S):
    w2 = width / 2
    if not hole:
        return cbox(-w2, -t2, 0, w2, t2, height)
    hx0, hz0, hx1, hz1 = hole
    parts = []
    if hx0 > -w2: parts += cbox(-w2, -t2, 0, hx0, t2, height)
    if hx1 < w2: parts += cbox(hx1, -t2, 0, w2, t2, height)
    if hz0 > 0: parts += cbox(hx0, -t2, 0, hx1, t2, hz0)
    if hz1 < height: parts += cbox(hx0, -t2, hz1, hx1, t2, height)
    return parts

HOLES = {'doorway': (-0.6, 0, 0.6, 2.2), 'windowframe': (-0.6, 1.0, 0.6, 2.0), 'frame': (-1.6, 0, 1.6, 2.6)}
MATID = {'wood': 70, 'stone': 11, 'metal': 56}

PIECES = []  # (model, look faces, collision parts, material id)
EXTENT = {}  # model -> (min, max) when the size the game sees is not the collision's
seed = 100
for mat in ('wood', 'stone', 'metal'):
    seed += 10
    PIECES.append((f'wl_bp_foundation_{mat}', foundation(mat, seed), cbox(-h2, -h2, 0, h2, h2, 1.0), MATID[mat]))
    PIECES.append((f'wl_bp_wall_{mat}', styled_wall(mat, seed + 1), solid_wall(), MATID[mat]))
    PIECES.append((f'wl_bp_halfwall_{mat}', styled_wall(mat, seed + 2, height=H / 2), solid_wall(height=H / 2), MATID[mat]))
    for name, hole in HOLES.items():
        PIECES.append((f'wl_bp_{name}_{mat}', styled_wall(mat, seed + len(name), hole), solid_wall(hole), MATID[mat]))
    PIECES.append((f'wl_bp_ceiling_{mat}', ceiling(mat, seed + 3), cbox(-h2, -h2, 0, h2, h2, T), MATID[mat]))
    PIECES.append((f'wl_bp_ramp_{mat}', ramp(mat, seed + 4), slope_box(-h2, h2, -h2, h2, 0.0, 1.0, 0.3), MATID[mat]))
    EXTENT[f'wl_bp_ramp_{mat}'] = ((-h2, -h2, 0.0), (h2, h2, 1.0))  # the size snapping knows (unchanged)
    half = FLOOR / 2
    PIECES.append((f'wl_bp_stairs_{mat}', stairs(mat, seed + 5),
        slope_box(-1.75, -0.05, -1.55, 0.75, 0.0, half, 0.3)
        + slope_box(0.05, 1.75, 0.75, -1.8, half, FLOOR, 0.3)
        + cbox(-1.78, 0.75, half - 0.12, 1.78, 1.78, half)
        + cbox(-1.78, 1.72, half, 1.78, 1.78, half + 0.95)
        + cbox(0.05, -2.0, FLOOR - 0.1, 1.75, -1.8, FLOOR), MATID[mat]))
    hx0, hy0, hx1, hy1 = HOLE
    PIECES.append((f'wl_bp_hatch_{mat}', hatch(mat, seed + 6),
        cbox(-h2, -h2, 0, hx0, h2, T) + cbox(hx1, -h2, 0, h2, h2, T) + cbox(hx0, -h2, 0, hx1, hy0, T) + cbox(hx0, hy1, 0, hx1, h2, T)
        + cbox(hx0 + 0.15, hy0 + 0.05, -H, hx0 + 0.21, hy0 + 0.11, 0.0) + cbox(hx1 - 0.21, hy0 + 0.05, -H, hx1 - 0.15, hy0 + 0.11, 0.0), MATID[mat]))
PIECES += [
    ('wl_bp_door_wood', door('wood'), cbox(0, -0.04, 0.02, 1.16, 0.04, 2.17), 70),
    ('wl_bp_door_metal', door('metal'), cbox(0, -0.04, 0.02, 1.16, 0.04, 2.17), 56),
    ('wl_bp_garage_wood', garage(), cbox(-1.58, -0.05, 0.02, 1.58, 0.05, 2.58), 70),
    ('wl_bp_windowbar_wood', windowbars('wood'), cbox(-0.58, -0.03, 1.02, 0.58, 0.03, 1.98), 70),
    ('wl_bp_windowbar_metal', windowbars('metal'), cbox(-0.58, -0.02, 1.02, 0.58, 0.02, 1.98), 56),
    ('wl_bp_gate_frame', gate_frame(), cbox(-2.8, -0.25, 0, -2.3, 0.25, 4.5) + cbox(2.3, -0.25, 0, 2.8, 0.25, 4.5) + cbox(-2.8, -0.25, 4.0, 2.8, 0.25, 4.5), 70),
    ('wl_bp_gate_door', gate_door(), cbox(0, -0.06, 0.05, 4.56, 0.06, 3.95), 56),
    ('wl_bp_toolcupboard', toolcupboard(), cbox(-0.5, -0.3, 0, 0.5, 0.3, 1.8), 56),
    ('wl_bp_stash_small', crate(), cbox(-0.5, -0.31, 0, 0.5, 0.31, 0.64), 70),
    ('wl_bp_stash_large', container(), cbox(-0.8, -0.37, 0, 0.8, 0.35, 1.14), 56),
    ('wl_bp_weaponlocker', locker(), cbox(-0.4, -0.26, 0, 0.4, 0.24, 1.9), 56),
]

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def extent_parts(parts):
    pts = []
    for kind, data in parts:
        if kind == 'box':
            x0, y0, z0, x1, y1, z1 = data
            pts += [(x0, y0, z0), (x1, y1, z1)]
        elif kind == 'rbox':
            c, (hx, hy, hz), yax, zax = data
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        pts.append(tuple(c[i] + (hx * sx if i == 0 else 0) + yax[i] * hy * sy + zax[i] * hz * sz for i in range(3)))
        else:
            pts += [p for item in data for p in item[1]]
    return (min(p[0] for p in pts), min(p[1] for p in pts), min(p[2] for p in pts)), \
           (max(p[0] for p in pts), max(p[1] for p in pts), max(p[2] for p in pts))

def vec(tag, v, w=None):
    s = f'<{tag} x="{f(v[0])}" y="{f(v[1])}" z="{f(v[2])}"'
    return s + (f' w="{f(w)}" />' if w is not None else ' />')

def tangent(n):
    ax = max(range(3), key=lambda i: abs(n[i]))
    return (0.0, 1.0, 0.0) if ax == 0 else (1.0, 0.0, 0.0)

COMMON_FLAGS = '''<MaterialColourIndex value="0" />
      <ProceduralID value="0" />
      <RoomID value="0" />
      <PedDensity value="0" />
      <UnkFlags value="0" />
      <PolyFlags value="0" />'''
CFLAGS = '''<CompositeFlags1>MAP_WEAPON, MAP_DYNAMIC, MAP_ANIMAL, MAP_COVER, MAP_VEHICLE</CompositeFlags1>
      <CompositeFlags2>VEHICLE_NOT_BVH, VEHICLE_BVH, PED, RAGDOLL, ANIMAL, ANIMAL_RAGDOLL, OBJECT, PLANT, PROJECTILE, EXPLOSION, FORKLIFT_FORKS, TEST_WEAPON, TEST_CAMERA, TEST_AI, TEST_SCRIPT, TEST_VEHICLE_WHEEL, GLASS</CompositeFlags2>'''

def box_child(b, mid, axes=None):
    if axes is None:
        x0, y0, z0, x1, y1, z1 = b
        c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        hx, hy, hz = (x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2
        yax, zax = (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)
    else:
        c, (hx, hy, hz) = b
        yax, zax = axes
    r = math.sqrt(hx * hx + hy * hy + hz * hz)
    vol = 8 * hx * hy * hz
    return f'''     <Item type="Box">
      {vec('BoxMin', (-hx, -hy, -hz))}
      {vec('BoxMax', (hx, hy, hz))}
      <BoxCenter x="0" y="0" z="0" />
      <SphereCenter x="0" y="0" z="0" />
      <SphereRadius value="{f(r)}" />
      <Margin value="0.0055" />
      <Volume value="{f(vol)}" />
      <Inertia x="1" y="1" z="1" />
      <MaterialIndex value="{mid}" />
      {COMMON_FLAGS}
      <UnkType value="2" />
      <CompositeTransform>
       1 0 0 0
       {f(yax[0])} {f(yax[1])} {f(yax[2])} 0
       {f(zax[0])} {f(zax[1])} {f(zax[2])} 0
       {f(c[0])} {f(c[1])} {f(c[2])} 1
      </CompositeTransform>
      {CFLAGS}
     </Item>'''

def mesh_child(faces, mid):
    cverts, cindex, polys = [], {}, []
    for item in faces:
        q = item[1]
        for a, b, cc in ((0, 1, 2), (0, 2, 3)):
            if len({q[a], q[b], q[cc]}) == 3:
                vi = []
                for p in (q[a], q[b], q[cc]):
                    if p not in cindex:
                        cindex[p] = len(cverts); cverts.append(p)
                    vi.append(cindex[p])
                polys.append(f'       <Triangle m="0" v1="{vi[0]}" v2="{vi[1]}" v3="{vi[2]}" f1="0" f2="0" f3="0" />')
    mn = tuple(min(p[i] for p in cverts) for i in range(3)); mx = tuple(max(p[i] for p in cverts) for i in range(3))
    c = tuple((mn[i] + mx[i]) / 2 for i in range(3))
    cv = '\n'.join(f'       {f(p[0])}, {f(p[1])}, {f(p[2])}' for p in cverts)
    return f'''     <Item type="Geometry">
      {vec('BoxMin', mn)}
      {vec('BoxMax', mx)}
      {vec('BoxCenter', c)}
      {vec('SphereCenter', c)}
      <SphereRadius value="{f(math.dist(mn, mx) / 2)}" />
      <Margin value="0.0055" />
      <Volume value="{f((mx[0] - mn[0]) * (mx[1] - mn[1]) * (mx[2] - mn[2]))}" />
      <Inertia x="1" y="1" z="1" />
      <MaterialIndex value="0" />
      {COMMON_FLAGS}
      <UnkType value="1" />
      <CompositeTransform>
       1 0 0 0
       0 1 0 0
       0 0 1 0
       0 0 0 1
      </CompositeTransform>
      {CFLAGS}
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
     </Item>'''

def shader(tex):
    return f'''   <Item>
    <Name>normal</Name>
    <FileName>normal.sps</FileName>
    <RenderBucket value="0" />
    <Parameters>
     <Item name="DiffuseSampler" type="Texture">
      <Name>{tex}</Name>
     </Item>
     <Item name="BumpSampler" type="Texture">
      <Name>{tex}_n</Name>
     </Item>
     <Item name="HardAlphaBlend" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="useTessellation" type="Vector" x="0" y="0" z="0" w="0" />
     <Item name="wetnessMultiplier" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="bumpiness" type="Vector" x="1.2" y="0" z="0" w="0" />
     <Item name="specularIntensityMult" type="Vector" x="{'0.25' if 'metal' in tex else '0.04'}" y="0" z="0" w="0" />
     <Item name="specularFalloffMult" type="Vector" x="{'40' if 'metal' in tex else '90'}" y="0" z="0" w="0" />
     <Item name="specularFresnel" type="Vector" x="0.9" y="0" z="0" w="0" />
     <Item name="globalAnimUV1" type="Vector" x="0" y="1" z="0" w="0" />
     <Item name="globalAnimUV0" type="Vector" x="1" y="0" z="0" w="0" />
    </Parameters>
   </Item>'''

# flags 32 and physicsDictionary = the model itself: the game then uses the
# collision inside the model file (without it, you walk through).
archetypes = []
for model, look, solid, mid in PIECES:
    mn, mx = EXTENT.get(model) or extent_parts(solid)   # the size the game sees (unchanged)
    c = tuple((mn[i] + mx[i]) / 2 for i in range(3))
    r = math.dist(mn, mx) / 2
    groups = {}
    for n, q, tex in look:
        groups.setdefault(tex, []).append((n, q))
    shaders, geoms = [], []
    for si, (tex, faces) in enumerate(groups.items()):
        shaders.append(shader(tex))
        verts, idx = [], []
        for n, q in faces:
            base = len(verts)
            for p in q:
                verts.append((p, n, uv(p, n), tangent(n)))
            for a, b, cc in ((0, 1, 2), (0, 2, 3)):
                if len({q[a], q[b], q[cc]}) == 3:
                    idx += [base + a, base + b, base + cc]
        gmn = tuple(min(v[0][i] for v in verts) for i in range(3)); gmx = tuple(max(v[0][i] for v in verts) for i in range(3))
        rows = '\n'.join(f'       {f(p[0])} {f(p[1])} {f(p[2])}   {f(nn[0])} {f(nn[1])} {f(nn[2])}   255 255 255 255   {f(t[0])} {f(t[1])}   {f(tg[0])} {f(tg[1])} {f(tg[2])} 1'
                         for p, nn, t, tg in verts)
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
       <Tangent />
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
    children = []
    for kind, data in solid:
        if kind == 'box':
            children.append(box_child(data, mid))
        elif kind == 'rbox':
            children.append(box_child((data[0], data[1]), mid, (data[2], data[3])))
        else:
            children.append(mesh_child(data, mid))
    vol = (mx[0] - mn[0]) * (mx[1] - mn[1]) * (mx[2] - mn[2])
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
  {vec('BoxMin', mn)}
  {vec('BoxMax', mx)}
  {vec('BoxCenter', c)}
  {vec('SphereCenter', c)}
  <SphereRadius value="{f(r)}" />
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
  <UnkType value="2" />
  <Children>
{chr(10).join(children)}
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
   <hdTextureDist value="60" />
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

print(len(PIECES), 'models,', len(ALL_TEX), 'textures written to', OUT)
