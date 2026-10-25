# PNG -> DXT1 DDS with a full mip chain (Pillow writes one level; stitch them).
import io, struct, sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
levels, header = [], None
w, h = im.size
while True:
    b = io.BytesIO()
    im.resize((w, h), Image.LANCZOS).save(b, format='DDS', pixel_format='DXT1')
    data = b.getvalue()
    if header is None: header = bytearray(data[:128])
    levels.append(data[128:])
    if w == 4 and h == 4: break
    w, h = max(4, w // 2), max(4, h // 2)
flags = struct.unpack_from('<I', header, 8)[0] | 0x20000          # DDSD_MIPMAPCOUNT
struct.pack_into('<I', header, 8, flags)
struct.pack_into('<I', header, 28, len(levels))                    # mip count
caps = struct.unpack_from('<I', header, 108)[0] | 0x400008 | 0x1000  # COMPLEX | MIPMAP | TEXTURE
struct.pack_into('<I', header, 108, caps)
open(dst, 'wb').write(bytes(header) + b''.join(levels))
print('mips', len(levels))
