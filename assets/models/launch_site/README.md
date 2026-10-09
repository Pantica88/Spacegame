# Launch complex

Original, reusable metre-scale GLB assets authored by `tools/build_launch_site.py`.
Regenerate with `python3 tools/build_launch_site.py`. No external dependencies.

`launch_complex.tscn` assembles eight material-batched asset types: a 120 m
concrete foundation with refractory deck and flush exhaust grilles, a 44 m service
tower, control building, bunded utility tank, floodlight mast, 60 m access road,
tracking dish, and blast barrier. Ivory, teal, steel and amber match the vehicles.

The scene origin is the rocket contact point. The central 24 × 24 m ignition
zone is free of props; the tower and its parked booms are outside that zone.
All assets fit inside the terrain's 150 m graded footprint. Foundations extend
below grade; surface finishes sit 15–45 mm above the contact datum to avoid
z-fighting. There are no stacked coplanar pad discs. The road ends at 120 m.
The complex inherits the existing planet rotation and floating-origin transform.
Near the facility, the terrain shader projects offsets from the launch datum
using its camera-space position. This preserves the thin deck clearance instead
of losing it when planet-sized coordinates cancel in the GPU transform.
Run `tools/run.sh --script res://tests/test_launch_deck_rendering.gd` on a
graphical display to check deck occlusion at three camera angles and rotations.

Terrain grading uses a tangent plane at the north pole and the same triangles
for physics and rendering. The changed bake signature invalidates old terrain
bakes. Surrounding terrain is blended within the existing 3 km island footprint.
Facility buildings are visual scenery, like the previous launch props; vessel
and debris contact uses the terrain, not building collision bodies. Lamps use
lens geometry and do not add shadow-casting local lights.
