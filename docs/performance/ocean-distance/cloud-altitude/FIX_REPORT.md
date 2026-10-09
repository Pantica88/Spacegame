# Cloud compositor performance fix

Removed the opacity-range fallback from `assets/shaders/clouds.gdshader`. Cloud-bank edges now use the existing opacity-weighted bilinear reconstruction instead of repeating volume integration in the full-resolution compositor. Terrain intersections and outer cloud-shell silhouettes retain their geometric full-resolution checks. Cloud density, lighting, and production resolution are unchanged.

Paired fixed-seed rendering benchmark, Godot 4.5.1, RX 580, Compatibility renderer, 1100×700, two reversed-order passes with 80 frames per case:

| Horizon view | Before | Fixed | Frame-time reduction |
| --- | ---: | ---: | ---: |
| 22 km | 13.109 ms | 11.638 ms | 11.2% |
| 100 km | 14.643 ms | 10.473 ms | 28.5% |

Raw results: `fixed-composite-results.json`. `baseline` denotes the fixed compositor; `previous_composite` denotes the saved pre-fix shader. Quarter-resolution rows are diagnostics only; production resolution was not reduced.

Visual captures in `fix-captures/` compare the fixed shader (`baseline`), pre-fix shader (`previous_composite`), and full-resolution reference. Clouds remain present and retain the same layout. Reduced-resolution reconstruction can still show fine steps at the distant deck edge; this fix restores the earlier performance/quality behavior rather than introducing a new antialiasing solution.

Validation limits: 17 performance-harness Python tests passed. The standard gameplay capture `20261007T105944628571Z-cloud-composite-fixed` was invalidated by concurrent edits to `scripts/main.gd` and a temporarily missing `prepare_impact_pool` method; do not use it as a clean performance comparison. The older `test_clouds.gd` failed its below/above visibility assertions with no cloud/clear image difference in that fixture; the fixed-seed benchmark and captures do contain clouds. Landing tail latency remains unverified by this compositor fix.
