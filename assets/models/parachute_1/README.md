# Parachute–1

Original procedural 3D interpretation of the supplied parachute reference, following Explorer–1's ivory/ochre PBR palette, GLB delivery, reproducible Python authoring, and Godot preview workflow.

- `parachute_1.glb`: packed nose-cone assembly, 56,672 triangles, five named components. Short conical shell matching the capsule taper, two ochre bands, fasteners, four release latches and actuator rods, mounting ring, underside socket.
- `parachute_1_deployed.glb`: deployed canopy, 18,320 triangles, three named components. Twenty-four fabric gores, apex vent, reinforced seams and hems, 48 suspension lines, four harness straps, connector ring. Fabric materials are nonmetallic and double-sided.
- `preview.png`, `preview_capsule_fit.png`, and `preview_deployed.png`: actual Godot renders of the packed housing, capsule fit, and deployed canopy.
- `tools/build_parachute_1.py`: deterministic authoring source using the project's `asset_geometry.py` helpers and Python standard library.

## Inspect and regenerate

Both variants appear in the game's Asset laboratory (`./view-assets.sh`). Component visibility, isolation, exploded views, and orbit controls follow the existing assets.

The workshop Parts menu includes **Parachute–1 recovery module**. Place a capsule first, then drag the module onto its top mount. One module per capsule; it adds 18 kg and 250 cost. Placement, selection, return to inventory, and saved designs use the normal craft controls. Existing designs retain their built-in recovery parachute until an external module is added.

Standalone previews:

```sh
./tools/run.sh res://scenes/parachute_1_deployment_preview.tscn
./tools/run.sh res://scenes/parachute_1_preview.tscn
./tools/run.sh res://scenes/parachute_1_deployed_preview.tscn
python3 tools/build_parachute_1.py
```

In the deployment preview, press P to deploy and R to repack. Drag to orbit, scroll to zoom, Space to rotate. Reimport generated GLBs in Godot after regeneration.

## Coordinates and integration

Metres, Y up. Packed model origin is centered on its mounting base; approximately 1.26 m wide and 1.92 m high including the underside socket (24% shorter than the original housing). Deployed origin is the harness attachment, canopy skirt at Y=5 m, crown near Y=7.1 m, diameter approximately 8.2 m including inflated panels.

`scenes/parachute_1.tscn` and `scripts/parachute_1.gd` provide the reusable animated module. Its housing is scaled to 53% to fit the capsule top collar; its installed height is approximately 1.02 m. The straight shell uses the same 0.61 / 1.92 radial taper as Explorer–1, ending in a small rounded tip. The cap seam is at Y=0.85 m and the internal attachment eye at Y=0.64 m in asset coordinates; the full-size canopy deploys from that eye. Existing P / staging safety checks trigger a 2.6-second sequence: release the retained nose cap, draw out the canopy, inflate. A retention cord keeps the cap beside the open canister. The lower shell, mounting ring, latches, deployment well, and spool remain visible. Animation freezes with flight pause; returning to the workshop rebuilds the packed state. The 18 kg recovery module stays with the separated capsule.

`preview_open.png` shows the deployed module with the open housing. The packed and deployed GLBs remain independently reusable static meshes; animation is implemented by the Godot module rather than embedded glTF animation tracks.

The static GLBs contain no embedded animation, baked wear textures, or production UV atlas. The Godot module provides deployment and local cloth simulation; the nose cap stays attached by its retention cord. Seams, fasteners, bands, and fabric panel shaping are geometry. UV coordinates use the same basic planar convention as Explorer–1.

At touchdown the cloth loses inflation pressure and can fold under compression. `scripts/recovery_hull.gd` defines a capsule and open-canister collision profile in mounting coordinates. The cloth accounts for its attachment offset and orientation, slides along the hull, and settles on the ground. Contact triangles and slack cords are subdivided and projected around this profile so large faces cannot cut through the capsule between simulation points. Cutaway cloth remains on the ground when the craft leaves.

The cap retention cord uses 16 constrained segments stepped at 120 Hz. After the initial 0.65-second ejection, a two-point cap body responds to gravity, capsule acceleration, and atmosphere-relative airflow. The cord bends, goes slack, and limits cap travel to 1.4 m. An approximate capsule/housing collision envelope prevents penetration. Simulation runs in the module frame, independent of camera rebasing, and pauses with flight. This is local visual physics: its forces do not feed back into the main vehicle simulation. Long frame stalls limit catch-up work to 0.1 s.

Contact rendering refines only intersecting faces and cords, bisecting the longest triangle edge to limit narrow triangles. Projected vertices are cached per redraw. The cloth solver uses a 60 Hz step and four constraint iterations. Once grounded cloth stays within 5 mm for three successive quarter-second samples, it sleeps and reuses its mesh; hull movement, ground changes, wind, acceleration, repacking and cutaway wake it. Run `tests/benchmark_parachute.gd` headlessly to measure airborne, touchdown, settling and resting CPU update costs.

The cloth uses 24 circumferential simulation samples with 12 alternating panels and 24 suspension cords. Contact tests intersect hull frusta directly; chord length does not increase sampling work. Individual face and cord contact geometry is reused while its endpoints remain within 1 cm, below the collision clearance. Ground contact moves the particles without invalidating unrelated faces. Slow grounded contact updates are staggered over two frames; fast motion and large hull changes refresh immediately. Cosmetic cloth and cap physics receive real frame time separately from deployment/simulation time, so physical warp does not multiply their substeps; they continue settling in rail warp and freeze with pause.

`tests/benchmark_recovery.gd` measures the combined flight, world and UI recovery update at 1× and 4× physical warp. `tests/test_parachute_visual_clock.gd` verifies identical cosmetic stepping at normal, physical and rail warp rates. These headless CPU measurements exclude GPU rendering.

Hillside recovery uses the terrain triangle normal and signed plane distance from flight telemetry. Post-touchdown acceleration is refreshed from settling motion, and static friction prevents tiny downhill cloth drift. Render contacts use a conservative four-point hull envelope and share edge tests. `tests/benchmark_hillside_recovery.gd` exercises three sloped highland sites, checks the recovery plane, and reports flight/visual CPU costs separately.
