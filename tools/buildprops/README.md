# Building props generator

Makes the `wasteland_buildprops` resource: every base-building piece (foundations,
walls, doorways, window frames, half walls, ceilings, garage frames and ramps in
wood, stone and metal, plus doors, a garage door, gate, window bars and the tool
cupboard), with collision and four textures painted by code.

Everything is original (simple shapes and generated textures), so it can be
shared freely with Wasteland Core. You do not need Blender or GTA V.

**Rebuild:** install Python 3 (`pip install pillow`), the .NET 8 SDK and git, then run

    powershell -ExecutionPolicy Bypass -File tools\buildprops\build.ps1

* `gen_buildprops.py`: shapes, sizes, textures and collision materials (edit this).
* `preview.py`: renders `props_sheet.png` / `props_base.png` previews (rough: the game draws them properly).
* `converter/`: a small tool on top of CodeWalker.Core (MIT, downloaded by the
  script) that turns the generated XML into GTA files (.ydr, .ytd, .ytyp).

Looks and collision are separate: the planks, braces, sheets and bolts are only for the eye; each piece keeps a simple solid collision, and its size (what snapping measures) comes from that collision.

Sizes: grid 4 m, walls 0.2 m thick and 3 m tall, foundations 1 m tall. Doors pivot
on their hinge edge. Snapping reads the real model sizes in game, so changing a
size here is enough.
