# Scrap barricade building props (Blender)

Optional new look for base building pieces: mismatched weathered planks,
rusty corrugated patches, spray paint, grime. Output goes to
`resources/[wasteland]/wasteland_buildprops_scrap/stream/` (same model names as
wasteland_buildprops, so they replace them while that resource runs).

## Needs
- Blender 4.2 or newer (built with 5.2.3), with the Sollumz add-on (2.9.0) and its
  dependencies installed (Sollumz preferences: Install dependencies).
- Python with Pillow 12+ (for `dds_mips.py`).
- Textures from ambientCG (CC0), 1K-JPG, unzipped into `tex/<Id>/`:
  Planks012, Wood049, Rust004 (https://ambientcg.com/get?file=<Id>_1K-JPG.zip).

## Build
```
blender -b --python build_wall.py      # model + bake -> out/wall_wood.blend, out/wl_bp_wall_wood_d.png, previews
python dds_mips.py out/wl_bp_wall_wood_d.png out/wlbp_scrapwall_d.dds
blender -b --python export_wall.py     # -> out/export/wl_bp_wall_wood.ydr (keeps the current wall's collision)
```
Run from a folder that holds the scripts and `tex/`.
