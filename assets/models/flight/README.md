# Shared vehicle meshes

These resources batch the original rigid vehicle meshes by material and include
precomputed levels of detail. Full-resolution geometry, materials and attachment
bounds are preserved. A single-surface copy is stored as `preview_mesh` metadata
for placement ghosts and selection outlines.

The workshop and flight view use these shared resources for craft with 32 or more
parts. Gyro and Atlas rings retain their original geometry at every distance
because automatic LOD simplification can intersect their thin layered panels.
Original GLB scenes remain available for smaller craft and asset previews.

Regenerate after changing a source GLB using the Godot editor binary:

```sh
XDG_DATA_HOME=/tmp/aphelion-visual-bake tools/run.sh --headless --script res://tools/bake_vehicle_visuals.gd
```

Run `tests/test_vehicle_batching.gd` to verify source hashes, full-resolution
triangle counts, bounds, surface counts and preview isolation. LOD generation
runs only during this bake; exported games load the saved mesh resources.
