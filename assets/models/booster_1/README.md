# Booster–1

Original procedural interpretation of the supplied solid rocket booster reference. Uses the same shared ivory, ochre, titanium and dark PBR palette and geometric detailing workflow as Explorer–1, Canister–1 and Engine–1.

- `booster_1.glb`: self-contained glTF 2.0, nine named components, 52,784 triangles.
- `preview.png`: actual Godot render.
- Dimensions: approximately 1.31 m casing diameter × 5.28 m tall. +Y up, nozzle exits at Y=0. Dimensions inferred from the reference image.
- Rebuild: `python3 tools/build_booster_1.py`.
- Preview: `./tools/run.sh res://scenes/booster_1_preview.tscn`. Drag to orbit, scroll to zoom, Space to rotate.
- Asset library: `./view-assets.sh`, select Booster–1. Supports component visibility, isolation, exploded inspection, and top/bottom views.

Features: segmented motor jacket, three orange bands, sealed ivory top cover, metal end collars and latches, twin service rails with cable channels, rail clamps and fasteners, recessed aft plate with support ribs, and four individually modeled hollow nozzles with inner liners.

Static visual asset, ready for Godot or Blender. No baked wear textures, production UV unwrap, collision shapes, animation, or an animated mesh. The workshop offers Booster–1 in Single/2/4/6/8 symmetry, snapping onto free Separator–1 surface mounts. Each booster has four aligned exhaust effects; staging releases the boosters and leaves the separators on the core.
