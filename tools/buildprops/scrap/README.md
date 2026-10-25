# Scrap barricade building props (Blender)

Optional new look for every base building piece: scrap planks (wood), cinder
blocks and concrete (stone), rusty corrugated sheet on angle iron (metal), with
spray paint, blood, grime and mud. Output goes to
`resources/[wasteland]/wasteland_buildprops_scrap/stream/` with the same model names
as wasteland_buildprops, so they replace them while that resource runs. Each
model keeps the collision of the original (it is put into the original .ydr).
Stairs, ramps, hatches and the tool cupboard keep their shape with a new texture.

## Needs
- Blender 4.2 or newer (built with 5.2.3), with Sollumz 2.9.0 and its dependencies
  (Sollumz preferences: Install dependencies).
- Python with Pillow 12+ (`dds_mips.py`, `sheet.py`).
- ambientCG textures (CC0), 1K-JPG, unzipped into `tex/<Id>/`
  (https://ambientcg.com/get?file=<Id>_1K-JPG.zip): Planks012, Wood049, Rust004,
  Bricks066, Concrete034, CorrugatedSteel001, CorrugatedSteel002, CorrugatedSteel003,
  PaintedMetal004, PaintedMetal009, DiamondPlate001, Metal046A.

## Build (from a folder holding these scripts and `tex/`)
```
blender -b --python probe_all.py      # sizes and collision of the originals -> pieces.json (already here)
blender -b --python build_all.py      # every piece -> out/pieces/<name>.blend, _d.png; out/previews/<name>.png
                                      # (or: -- wl_bp_wall_wood wl_bp_door_wood ... for some)
for f in out/pieces/*_d.png; do python dds_mips.py "$f" "${f%.png}.dds"; done
blender -b --python export_all.py     # -> out/export/<name>.ydr
blender -b --python verify_all.py     # re-imports each: collision equals the original, texture embedded
```
