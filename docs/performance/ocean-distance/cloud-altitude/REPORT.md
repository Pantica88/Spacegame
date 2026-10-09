# High-altitude cloud tests — October 7, 2026

Godot 4.5.1, OpenGL Compatibility, Radeon RX 580, 1100×700, uncapped FPS, vsync disabled. Same static open-ocean flight scene and fixed camera pitch as the earlier ocean benchmark. Eighty measured frames per case in two reversed mode orders. Full-resolution comparison images are included; the contact sheet is `resolution-comparison.png`.

| Altitude | Cloud resolution (each axis) | Cloud pass GPU | Frame time | Approx. FPS |
|---|---:|---:|---:|---:|
| 22km | 50% | 3.81 ms | 9.67 ms | 103 |
| 22km | 37.5% | 2.53 ms | 8.33 ms | 120 |
| 22km | 25% | 1.40 ms | 7.21 ms | 139 |
| 100km | 50% | 2.71 ms | 8.00 ms | 125 |
| 100km | 37.5% | 1.76 ms | 7.12 ms | 141 |
| 100km | 25% | 1.06 ms | 6.54 ms | 153 |

## Causality and the water change

At 100 km the near-water OceanPatch is disabled. Hiding it explicitly changes frame time from 7.997 to 7.994 ms—effectively no difference. It therefore cannot directly cause an ocean-patch GPU regression at that altitude. At 22 km, hiding the patch reduces frame time from 9.668 to 6.729 ms, so water still contributes materially there. Cloud-pass time remains 3.8 ms with and without water at 22 km, and 2.7 ms at 100 km. These tests do not support attributing additional cloud-pass work to the new water renderer.

No production cloud code was changed during the water work. These results measure current cost and possible improvements, not a proved before/after cloud regression. An exact previous build matched to the same pose, weather, renderer and settings would be needed for that attribution. The older `/tmp/aphelion-cloud-opt-20261006` snapshot predates other cloud changes and is not a valid immediate-before-water baseline.

At 100 km, disabling all sky/terrain/ocean atmospheric scattering reduces frame time to 5.323 ms. Disabling clouds reduces it to 3.862 ms. The cloud-off saving includes the offscreen volume pass and full-resolution compositing; it is larger than the cloud-pass GPU time alone. Ablation savings must not be added as independent costs.

## Optimization candidates

1. **Distance-dependent cloud resolution:** retain 50% near/inside clouds; transition toward 37.5% when well above the highest cloud shell and toward 25% at orbital distance. At 100 km, 25% reduces the cloud pass by 61% and frame time by 18% (125→153 FPS). At 22 km it reduces frame time by 25% (103→139 FPS). The compared scenes retain broad cloud layout and lighting; lower resolution softens finer wisps and can coarsen silhouettes. 37.5% is the conservative intermediate setting. Resolution transitions need hysteresis or quantized steps to prevent viewport reallocation on every camera movement.
2. **Cloud composite fast path:** `clouds.gdshader` reconstructs four scene-depth neighbours and four neighbouring cloud rays per output pixel, then can integrate clouds again at full resolution. Above the cloud shell, most rays hit terrain behind all cloud segments and only need the low-resolution result. A conservative fast path could skip redundant neighbourhood work, preserving special handling for nearby craft, terrain intersections and shell silhouettes. Not benchmarked or implemented here.
3. **Orbital march LOD:** distant clouds still use the volume marcher (up to 320 loop iterations, low-deck path divided into 96 steps). Reduce the effective integration budget based on projected cloud features while preserving optical depth, storm tops and grazing paths. Do not simply truncate the march, which can lose part of the cloud deck. This needs separate quality tests and is not yet measured.

Cloud density already disables fine detail beyond 150 km ray distance, blends coarser noise before that, and stops integrating when transmittance falls below 0.025. Those optimizations are already present.

Production cloud settings remain unchanged. Resolution candidates were applied only by the benchmark. `results.json` holds raw timing rows. `benchmark_cloud_altitude.gd` is the self-contained diagnostic harness; run with this repository as Godot's project path. The general `tests/benchmark_ocean_distance.gd` now includes 100 km and preserves the ocean's expected disabled state there.
