# Separator–1

Original procedural booster-separator model based on the supplied reference, with yellow hazard markings and mirrored release housings on both lateral sides. Uses the shared Explorer–1 material palette and geometric detailing workflow.

- `separator_1.glb`: self-contained glTF 2.0, seven named components, 13,416 triangles.
- `preview.png`: actual Godot render.
- Approximately 1.40 m tall, 0.65 m wide and 0.72 m deep including hardware. Dimensions inferred from the image. Centered origin, +Y up, front rail facing +Z, mounting feet extending toward -Z.
- Rebuild: `python3 tools/build_separator_1.py`.
- Preview: `./tools/run.sh res://scenes/separator_1_preview.tscn`.
- Available as Separator–1 in `./view-assets.sh`, with component visibility, isolation, and exploded inspection.

Includes chamfered metal frame, recessed warning channel with yellow diagonal stripes on front and rear, twin guide rods, locking ties, reinforced end clamps, rear mounting feet, two release housings with ivory indicator slots, and recessed hex fasteners.

Static mesh with no animated mechanism, dedicated collision mesh, baked wear textures, or production UV unwrap. Separation behavior is handled by the game. The workshop offers 12 kg Separator–1 mounts in Single/2/4/6/8 symmetry, placed continuously around a fuel tank. Booster–1 attaches to the separators; moving or removing separators moves or removes their booster descendants. Legacy paired-booster saves remain supported.
