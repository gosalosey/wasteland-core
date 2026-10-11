"""Import an item image pack into wasteland_images.

    python tools/import_images.py "F:/FIVEM SHIT/items-images-main"

Every PNG in the pack (any sub-folder) is copied to
resources/[wasteland]/wasteland_images/html/images/<name>.webp, where <name>
is the file name in lower case with anything but a-z 0-9 _ - replaced by _.
Names that appear twice keep the first (by path); later ones get the folder
name appended. Images bigger than MAX_BYTES or MAX_SIDE pixels are scaled
down to fit MAX_SIDE, and everything is saved as WebP (about a quarter of
the size of PNG; players download every image once). The pack itself is
never changed. Empty transparent borders are trimmed. index.txt lists
every image name, one per line.
"""
import os
import re
import sys

from PIL import Image

MAX_SIDE = 256
MAX_BYTES = 100 * 1024

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'resources', '[wasteland]', 'wasteland_images', 'html', 'images')


def clean(name):
    return re.sub(r'[^a-z0-9_-]', '_', name.lower())


def main(pack):
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    paths = []
    for root, _, files in os.walk(pack):
        for f in files:
            if f.lower().endswith('.png'):
                paths.append(os.path.join(root, f))
    paths.sort(key=lambda p: p.lower())
    names, resized, before, after = {}, 0, 0, 0
    for p in paths:
        base = clean(os.path.splitext(os.path.basename(p))[0])
        name = base
        if name in names:
            folder = clean(os.path.basename(os.path.dirname(p)))
            name = f'{base}__{folder}'
            n = 2
            while name in names:
                name = f'{base}__{folder}{n}'
                n += 1
        names[name] = p
        dest = os.path.join(OUT, name + '.webp')
        size = os.path.getsize(p)
        before += size
        try:
            img = Image.open(p)
            if img.mode not in ('RGBA', 'RGB'):
                img = img.convert('RGBA')
            if img.mode == 'RGBA':
                # Trim the empty transparent border so long items (rifles)
                # fill their tile; keep a small margin.
                box = img.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
                if box:
                    pad = max(2, round(max(box[2] - box[0], box[3] - box[1]) * 0.04))
                    img = img.crop((max(0, box[0] - pad), max(0, box[1] - pad),
                                    min(img.width, box[2] + pad), min(img.height, box[3] + pad)))
            if size > MAX_BYTES or max(img.size) > MAX_SIDE:
                img.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
                resized += 1
            img.save(dest, 'WEBP', quality=90, method=4)
        except Exception as e:  # unreadable file: skip it
            print(f'skipped {p}: {e}')
            del names[name]
            continue
        after += os.path.getsize(dest)
    with open(os.path.join(os.path.dirname(OUT), 'index.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(sorted(names)) + '\n')
    print(f'{len(names)} images, {resized} scaled down, {before / 2**20:.1f} MB -> {after / 2**20:.1f} MB')


if __name__ == '__main__':
    main(sys.argv[1])
