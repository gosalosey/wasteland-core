# wasteland_images

Item pictures for Wasteland Core, imported from the community **MK-Items** pack
(McKleans-Scripts and contributors: JixelPatterns, Project Boosted, Project
Sloth and others; see that pack's README for credits). The pack asks that
paid content is not redistributed without permission; these pictures are for
use on this server.

* `html/images/<name>.webp`: every PNG of the pack, file names in lower case
  (anything but a-z 0-9 _ - becomes _), pictures over 100 KB or 256 px scaled
  down, all saved as WebP. Names that appeared twice keep the first; the
  others get `__<folder>` appended.
* `html/index.txt`: every picture name; the inventory reads it.

An item shows the picture named in its `image` field in `inventory.lua`, else
the one named like the item, else its colour. To re-import (for example a
newer pack):

    python tools/import_images.py "F:/FIVEM SHIT/items-images-main"

(needs Python with Pillow: `python -m pip install pillow`). To add your own
picture, drop a `.webp` into `html/images` and add its name to `index.txt`.
