# Engine–1

Original geometric interpretation of the supplied engine reference, authored with the same procedural modeling workflow and ivory, ochre, titanium and dark PBR materials as Explorer–1 and Canister–1.

- `engine_1.glb`: self-contained glTF 2.0, eight named components, 48,208 triangles.
- `preview.png`: actual Godot render.
- Dimensions: approximately 1.97 m across the mounting hardware and 2.71 m tall. +Y up, nozzle exit at Y=0, attachment at the top. Dimensions are inferred from the picture.
- Rebuild: `python3 tools/build_engine_1.py`.
- Preview: `./tools/run.sh res://scenes/engine_1_preview.tscn`. Drag to orbit, scroll to zoom, Space to rotate.
- Also available as Engine–1 in `./view-assets.sh`, with component visibility, isolation and exploded inspection.

Features include a segmented mounting collar with orange band, dark top cover, perimeter latches and fasteners, ceramic combustion-chamber jacket, hollow ribbed bell with inner liner and recessed throat, four ivory suspension braces and angled gimbal actuators, curved feed and return pipes, and auxiliary reservoirs.

Static visual asset; actuators are modeled but not animated. No collision shapes, baked wear textures, production UV unwrap or changes to thrust, fuel use or staging. The Kestrel engine uses this asset in the assembled craft and drag/selection previews, fitted to its existing attachment envelope. Exhaust is aligned with the new nozzle exit.
