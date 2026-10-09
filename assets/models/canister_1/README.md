# Canister–1

Original mesh reconstruction of the supplied cylindrical vessel reference. Ivory segmented shell, amber bands, machined collars, recessed top cover, bottom connector bore and radial ribs, twin service rails, clamps, latches and bolts.

- `canister_1.glb`: portable glTF 2.0 with nine named mesh components, 49,968 triangles, metallic–roughness materials. No external dependencies or textures.
- Dimensions: approximately 1.97 m overall diameter including hardware × 4.75 m tall; origin at center, +Y up. Dimensions are inferred from the image, not engineering measurements.
- Rebuild: `python3 tools/build_canister_1.py`.
- Inspect: `./view-assets.sh` from the project root. The library also contains Explorer–1 and Atlas–1. Checkboxes control visibility; select a component then enable isolation to inspect it. Drag to orbit, wheel to zoom. Explode separates the component groups vertically for inspection.
- `preview.png`: Godot render using the same turntable and lighting as Explorer-1.
- Preview: `./tools/run.sh res://scenes/canister_1_preview.tscn`.
- Uses Explorer-1’s procedural geometry workflow and shared ivory, ochre, titanium and dark seal PBR palette.

Instantiate the GLB directly in a Godot scene or import it into Blender. This is a detailed visual asset; it does not include collision shapes, LODs, UV texture baking, or new fuel/attachment behavior. The game uses this GLB for fuel tanks in installed assemblies and selection previews. The reference-proportioned asset is fitted vertically to the existing 2.15 m tank attachment envelope by `world_view.gd`; the standalone preview shows its original proportions. Existing capsule/decoupler models expose their current single-mesh component structure in the viewer.
