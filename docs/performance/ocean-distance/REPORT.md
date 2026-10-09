# Ocean distance benchmark — October 7, 2026

Godot 4.5.1, OpenGL Compatibility, Radeon RX 580; 1100 × 700, vsync and FPS cap disabled. Static flight scene over open ocean; fixed camera pitch 0.35 radians. Each mode measured for 80 frames in two opposite orders, with 15 warmup frames before each block. An initial five-mode run and the final six-mode run produced similar baseline times. Ocean patch activation was verified. Terrain, sky, and clouds are active; craft and launch structures are hidden. CPU flight integration is excluded.

Frame time is median wall time between rendered frames; FPS is 1000/frame time, an uncapped benchmark estimate rather than in-game HUD FPS. GPU time is recorded separately for the main viewport and the reduced-resolution cloud pass in the JSON/CSV files.

| View | Frame time | Approx. FPS | Without ocean | Without atmosphere | Without clouds | Without swell calculations |
|---|---:|---:|---:|---:|---:|---:|
| Close (25 m camera range) | 7.62 ms | 131 | 4.61 ms | 6.69 ms | 4.96 ms | 6.59 ms |
| Zoomed to 90 m | 7.86 ms | 127 | 4.66 ms | 6.98 ms | 5.26 ms | 6.79 ms |
| Zoomed to 500 m | 8.22 ms | 122 | 4.72 ms | 7.12 ms | 5.33 ms | 7.00 ms |
| 500 m flight altitude | 6.65 ms | 150 | 4.47 ms | 5.80 ms | 3.98 ms | 5.89 ms |
| 6 km flight altitude | 7.34 ms | 136 | 4.79 ms | 5.66 ms | 4.77 ms | 6.68 ms |
| 22 km flight altitude | 9.85 ms | 101 | 6.78 ms | 7.11 ms | 5.54 ms | 9.11 ms |

## Findings

Zooming out from 25 to 500 m modestly increases frame time. Camera pitch stays fixed, so zooming also raises the observer above the surface; this models normal game camera zoom rather than changing only viewing distance. Flight altitude is not a monotonic slowdown: the 500 m flight pose is faster than the close pose.

The ocean patch costs roughly 2–3.5 ms relative to fallback terrain water across these poses. This ablation removes both the mesh and its shader work, so it does not prove the mesh alone is the bottleneck. Disabling only the four swell octaves (vertex and fragment) saves approximately 0.7–1.2 ms. Their removal is a diagnostic shader variant, not a production change.

At 22 km the cloud pass costs about 3.84 ms, versus about 1.15 ms close to water. Removing clouds reduces frame time from about 9.85 to 5.54 ms. Atmospheric scattering also grows more expensive with altitude: disabling it saves about 2.74 ms at 22 km. Disabling only ocean scattering saves about 1.69 ms there. These savings are separate ablations and must not be added as if independent.

The strongest measured high-altitude optimization target is cloud rendering, followed by atmospheric integration. For ordinary zoom-out near water, ocean shader/geometry cost rises modestly. Selectively skipping unresolved swell work is a smaller but measurable opportunity. A geometry-only ablation would be needed to establish triangle-count savings.

## Reproduction

Run `tests/benchmark_ocean_distance.gd` with graphical Godot 4.5.1 and `--disable-vsync`. Raw results are written to `/tmp/aphelion-ocean-benchmark.json`. `no_ocean` restores terrain water instead of leaving the seabed exposed. `no_air` disables scattering in sky, terrain, and ocean, while `no_ocean_air` disables it only in ocean. `no_clouds` disables the cloud composite and its low-resolution pass. `no_swell` skips the two four-octave loops in a temporary in-memory shader; production shader files are untouched.

Desktop GPU load, location, weather, screen resolution and viewing angle can change timings. This benchmark explains this controlled scene; it does not establish the exact cause of every observed in-game FPS drop.
