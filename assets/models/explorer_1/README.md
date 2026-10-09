# Explorer-1 exterior

Original procedural interpretation of the capsule reference supplied in this task.

- `explorer_1.glb`: reusable glTF 2.0 mesh with PBR materials; Godot and Blender compatible.
- `preview.png`: actual Godot render.
- Authoring source: `tools/build_explorer_1.py` (Python standard library only).
- Inspection scene: `scenes/explorer_1_preview.tscn`.

## Inspect and regenerate

Run `./tools/run.sh res://scenes/explorer_1_preview.tscn` from the project root. Drag to orbit, scroll to zoom, and press Space for automatic rotation. The camera can orbit underneath to inspect the shield.

Run `python3 tools/build_explorer_1.py` to regenerate the GLB, then let Godot reimport it.

## Asset specification

Y up, front hatch facing +Z, origin centered at the bottom of the heat shield. Approximately 1.90 m diameter and 2.735 m tall including the antenna. 39,112 triangles, 12 material surfaces, one static mesh. Geometry is batched by material; tiny fittings do not create individual scene nodes. Godot's import settings generate mesh LODs. Materials use metallic/roughness shading with opaque glass and geometric markings. UVs are basic planar coordinates, not a production unwrap or texture atlas.

Details include ceramic hull panels, seams and fasteners, six trapezoidal windows, closed hatch with handle and hinges, four quad-nozzle RCS bays with tapered nozzles pointing 15 degrees downward, bronze nozzle lips and recessed throats, cooling louvers, rescue stripes, 01 marking, recessed docking collar with locking dogs, antenna, and segmented heat shield with underside tiles.

The game uses this asset for the existing command capsule in the assembled vehicle and drag/selection previews. Its placement matches the existing bottom attachment; flight physics, part identity, and staging continue to use the existing capsule model.

## Scope

Exterior visual asset only. The reference's cutaway interior, working hatch, transparent cockpit, docking/RCS gameplay, collision mesh, baked wear textures, and animation rig are not included. The hull has a continuous shell behind the closed hatch and windows. This is a geometric interpretation, not an exact reconstruction. The game's existing flight/contact systems handle the capsule's physics.
