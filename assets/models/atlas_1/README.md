# Atlas-1 slim decoupler

Based on the supplied reference's front, side, top, and main three-quarter views. The thick bottom-right cutaway is intentionally excluded.

A hollow ring with segmented ivory outer panels, titanium attachment flanges, upper/lower bolt seats, four clamp assemblies, inner yellow hazard stripes, an upward-pointing front triangle, exterior markings, and a rear dual connector panel.

## Dimensions and delivery

- Approximately 1.90 m body diameter, 1.376 m clear inner diameter.
- 0.20 m main body height; hardware stays within the existing 0.22 m attachment envelope.
- Origin at the center, Y up, upward triangle facing +Z.
- 25,907 triangles, eight material surfaces, one static mesh; Godot generates imported LODs.
- `atlas_1.glb` is a reusable glTF 2.0 asset. Materials and markings are included without external textures.
- UVs are basic planar coordinates, not an atlas prepared for texture painting.

The game uses this model for its existing decoupler in assembled vehicles, drag previews, and detached lower stages. It retains the existing separation mechanics. Individual clamps are static; the cutaway mechanism and animated clamp release are not modeled.

## Preview

Paste this command into a terminal:

```bash
/home/bo-ai/BlufftonGames/001/tools/run.sh res://scenes/atlas_1_preview.tscn
```

Drag to orbit, scroll to zoom, Space to rotate. `preview.png` is an actual Godot render.

To regenerate from the project root, run `python3 tools/build_atlas_1.py`. The generator uses the Python standard library and `tools/asset_geometry.py`.
