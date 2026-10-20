"""Preview renders of the generated building props (textured, shaded, orthographic)."""
import math, os, runpy, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
sys.argv = ['gen', tempfile.mkdtemp()]
g = runpy.run_path(os.path.join(here, 'gen_buildprops.py'))
TEX = {k: v.convert('RGB') for k, v in g['TEXTURES'].items()}
PIECES = g['PIECES']
uvf = g['uv']
byname = {p[0]: p for p in PIECES}

YAW, PITCH = math.radians(35), math.radians(28)
LIGHT = (0.45, -0.55, 0.7)
_l = math.sqrt(sum(c * c for c in LIGHT)); LIGHT = tuple(c / _l for c in LIGHT)
_tiles = {}

def cam(p):
    x, y, z = p
    cx = x * math.cos(YAW) - y * math.sin(YAW)
    cy = x * math.sin(YAW) + y * math.cos(YAW)
    return cx, -(z * math.cos(PITCH) - cy * math.sin(PITCH)), cy * math.cos(PITCH) + z * math.sin(PITCH)

def tiled(tex, nx, ny):
    key = (id(tex), nx, ny)
    if key not in _tiles:
        tw, th = tex.size
        big = Image.new('RGB', (tw * nx, th * ny))
        for i in range(nx):
            for j in range(ny):
                big.paste(tex, (i * tw, j * th))
        _tiles[key] = big
    return _tiles[key]

def split(items, step=0.3):
    out = []
    for n, q, tex, *_ in items:
        if len(set(q)) < 4:
            out.append((n, q, tex)); continue
        a, b, c, d = q
        la = math.dist(a, b); lb = math.dist(a, d)
        nu = max(1, int(la / step)); nv = max(1, int(lb / step))
        def P(u, v):
            return tuple(a[i] + (b[i] - a[i]) * u + (d[i] - a[i]) * v + (a[i] - b[i] + c[i] - d[i]) * u * v for i in range(3))
        for i in range(nu):
            for j in range(nv):
                u0, u1, v0, v1 = i / nu, (i + 1) / nu, j / nv, (j + 1) / nv
                out.append((n, [P(u0, v0), P(u1, v0), P(u1, v1), P(u0, v1)], tex))
    return out

def draw(img, items, scale, ox, oy):
    size = img.size[0]
    items = split(items)
    order = sorted(items, key=lambda it: sum(cam(p)[2] for p in it[1]) / len(it[1]))
    for n, q, texname in order:
        ny = n[0] * math.sin(YAW) + n[1] * math.cos(YAW)
        if -ny * math.cos(PITCH) + n[2] * math.sin(PITCH) <= 0.01:
            continue
        shade = 0.42 + 0.58 * max(0.0, sum(n[i] * LIGHT[i] for i in range(3)))
        scr = [(cam(p)[0] * scale + ox, cam(p)[1] * scale + oy) for p in q]
        tex = TEX[texname]; tw, th = tex.size
        uvs = [(u * tw, v * th) for u, v in (uvf(p, n) for p in q)]
        umin = math.floor(min(u for u, _ in uvs) / tw) * tw
        vmin = math.floor(min(v for _, v in uvs) / th) * th
        uvs = [(u - umin, v - vmin) for u, v in uvs]
        nxt = int(math.ceil(max(u for u, _ in uvs) / tw)) + 1
        nyt = int(math.ceil(max(v for _, v in uvs) / th)) + 1
        (x0, y0), (x1, y1), (x2, y2) = scr[0], scr[1], scr[2]
        (u0, v0), (u1, v1), (u2, v2) = uvs[0], uvs[1], uvs[2]
        det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(det) < 1e-6:
            continue
        a = ((u1 - u0) * (y2 - y0) - (u2 - u0) * (y1 - y0)) / det
        b = ((u2 - u0) * (x1 - x0) - (u1 - u0) * (x2 - x0)) / det
        c = u0 - a * x0 - b * y0
        d_ = ((v1 - v0) * (y2 - y0) - (v2 - v0) * (y1 - y0)) / det
        e = ((v2 - v0) * (x1 - x0) - (v1 - v0) * (x2 - x0)) / det
        f = v0 - d_ * x0 - e * y0
        bx0 = max(0, int(min(p[0] for p in scr)) - 1); by0 = max(0, int(min(p[1] for p in scr)) - 1)
        bx1 = min(size, int(max(p[0] for p in scr)) + 2); by1 = min(size, int(max(p[1] for p in scr)) + 2)
        if bx1 <= bx0 or by1 <= by0:
            continue
        w_, h_ = bx1 - bx0, by1 - by0
        warped = tiled(tex, nxt, nyt).transform((w_, h_), Image.AFFINE, (a, b, c + a * bx0 + b * by0, d_, e, f + d_ * bx0 + e * by0), resample=Image.BILINEAR)
        warped = warped.point(lambda v, s=shade: int(v * s))
        mask = Image.new('L', (w_, h_), 0)
        ImageDraw.Draw(mask).polygon([(x - bx0, y - by0) for x, y in scr], fill=255)
        img.paste(warped, (bx0, by0), mask)

def frame(items, size, fill=0.8, bg=(52, 58, 48)):
    pts = [cam(p) for _, q, _ in items for p in q]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    span = max(max(xs) - min(xs), max(ys) - min(ys), 1.0)
    scale = size * fill / span
    ox = size / 2 - (max(xs) + min(xs)) / 2 * scale
    oy = size / 2 - (max(ys) + min(ys)) / 2 * scale
    img = Image.new('RGB', (size, size), bg)
    draw(img, items, scale, ox, oy)
    return img

def items_of(nm, dx=0.0, dy=0.0, dz=0.0, rot=0.0):
    _, look, _, _ = byname[nm]
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    return [((n[0] * c - n[1] * s, n[0] * s + n[1] * c, n[2]),
             [(p[0] * c - p[1] * s + dx, p[0] * s + p[1] * c + dy, p[2] + dz) for p in q], tex) for n, q, tex, *_ in look]

show = ['wl_bp_foundation_wood', 'wl_bp_wall_wood', 'wl_bp_doorway_wood', 'wl_bp_windowframe_wood',
        'wl_bp_wall_metal', 'wl_bp_wall_stone', 'wl_bp_frame_metal', 'wl_bp_ramp_wood',
        'wl_bp_door_wood', 'wl_bp_door_metal', 'wl_bp_garage_wood', 'wl_bp_windowbar_metal',
        'wl_bp_gate_frame', 'wl_bp_gate_door', 'wl_bp_foundation_metal', 'wl_bp_toolcupboard']
cell = 300
sheet = Image.new('RGB', (cell * 4, (cell + 26) * 4), (24, 24, 22))
try:
    font = ImageFont.truetype('segoeui.ttf', 17)
except Exception:
    font = ImageFont.load_default()
for i, nm in enumerate(show):
    x, y = (i % 4) * cell, (i // 4) * (cell + 26)
    sheet.paste(frame(items_of(nm, rot=180), cell, 0.72), (x, y))
    ImageDraw.Draw(sheet).text((x + 10, y + cell + 3), nm.replace('wl_bp_', '').replace('_', ' '), fill=(230, 220, 200), font=font)
sheet.save(os.path.join(here, 'props_sheet.png'))

# a small base: stone foundations, walls, doorway with a metal door, window with bars, ramp
base = []
for fx in (0, 4):
    for fy in (0, 4):
        base += items_of('wl_bp_foundation_stone', fx, fy, 0)
base += items_of('wl_bp_wall_wood', 0, -1.9, 1.0)
base += items_of('wl_bp_doorway_wood', 4, -1.9, 1.0)
base += items_of('wl_bp_door_metal', 4 - 0.58, -1.95, 1.0)
base += items_of('wl_bp_wall_metal', -1.9, 0, 1.0, 90)
base += items_of('wl_bp_windowframe_wood', -1.9, 4, 1.0, 90)
base += items_of('wl_bp_windowbar_metal', -1.95, 4, 1.0, 90)
base += items_of('wl_bp_ramp_wood', 4, -4, 0, 180)
frame(base, 800, 0.85, (60, 66, 52)).save(os.path.join(here, 'props_base.png'))
print('ok')
