# Full gameplay and additional cloud performance tests

Standard gameplay lab: 1280×720, Godot 4.5.1, OpenGL Compatibility, Radeon RX 580, uncapped rendering, native 60 Hz physics, 2 s warmup and 8 simulation seconds per checkpoint, three repeats. All 24 trials passed fixture and timing validation; source fingerprints were unchanged during capture. The 17 Python performance-runner/report tests also passed.

Full traces, screenshots and interactive report: `build/performance/20261007T103925367969Z-water-cloud-perf/report.html`.

Comparison: `20261007T074557469177Z-cloud-single-callsite`, matching hardware, engine, fixture and configuration. Source changes between runs include water/physics changes and the cloud compositor. This is a combined regression comparison, not a water-only A/B test.

| Checkpoint | Median frame | p95 frame | Median GPU | Median change | Regression flag |
|---|---:|---:|---:|---:|---|
| launch | 10.84 ms | 12.18 ms | 10.30 ms | +0.17 ms | No |
| dense_clouds | 13.46 ms | 13.99 ms | 12.89 ms | -0.26 ms | No |
| staging | 12.85 ms | 14.11 ms | 12.35 ms | -0.02 ms | No |
| orbit | 19.48 ms | 20.18 ms | 18.84 ms | +3.43 ms | Yes |
| map | 9.09 ms | 10.06 ms | 7.22 ms | +1.37 ms | No |
| reentry | 11.08 ms | 12.89 ms | 10.48 ms | -0.18 ms | No |
| parachute | 14.49 ms | 15.19 ms | 13.95 ms | +0.03 ms | No |
| landing | 14.73 ms | 17.46 ms | 10.73 ms | +0.50 ms | Yes |

Orbit misses the 16.67 ms frame budget on 99.9% of measured frames. Landing misses on 7.9%; its p95 worsens by about 1.22 ms. Launch, dense clouds, staging, map, reentry and parachute do not trigger the suite's regression rule. The map median increases by about 1.37 ms, but its p95 and GPU median do not exceed the rule together; inspect traces rather than treating an unflagged median as proof of no change.

## Added tests

- `tests/benchmark_cloud_horizon.gd`: 22 and 100 km, horizon and downward views; current clouds, disabled clouds, 37.5% and 25% cloud resolution; 80 measured frames per case in reversed mode orders. Fixed seeded home planet. Static rendering only; complements the live gameplay lab.
- `tests/benchmark_cloud_composite.gd`: same horizon scenes, current versus hash-matched previous compositor, at 50% and 25% resolution. Set `CLOUD_REFERENCE_SHADER` to `docs/performance/ocean-distance/cloud-altitude/reference-clouds.gdshader.txt`. The test loads shader source text directly and uses the existing density/low-resolution shader for both variants.

Reference shader SHA256: `40061689ae2086540d6f9ddba9f354a5b217480b1f129d3cbc5faec03322a34f`, exactly matching the saved comparison run's fingerprint. The cloud density shader content hash matches both the saved and current runs. The difference in the compositor is an additional four-texel opacity-range check that falls back to full-resolution volume integration when the range is 0.6 or greater.

## Isolated compositor comparison

| View | Current (50%) | Previous (50%) | Current (25%) | Previous (25%) |
|---|---:|---:|---:|---:|
| 22km_horizon | 13.16 ms | 11.85 ms | 12.24 ms | 8.99 ms |
| 100km_horizon | 14.83 ms | 10.61 ms | 13.92 ms | 8.35 ms |

At 100 km with 50% cloud resolution, the added fallback costs about 4.22 ms per frame. The offscreen cloud pass remains about 4.25–4.29 ms between shader variants, while main-viewport GPU time rises from about 5.85 to 9.94 ms. This isolates the repeatable difference to compositing/full-resolution retracing rather than additional work in the shared low-resolution cloud pass. At 25% resolution, retracing is more costly: smaller viewport texels encompass larger opacity changes, so more pixels meet the fallback threshold.

## Optimization conclusion

The prior recommendation to lower cloud resolution is incomplete for horizon views. In the added test, 22 km horizon rendering takes 12.96 ms at 50%, 11.54 ms at 37.5%, and 12.08 ms at 25%; the coarser pass lowers its own cost but increases full-resolution fallback work. Downward views benefit much more: 100 km drops from 8.29 to 5.67 ms at 25%.

First restrict or replace the opacity-range fallback so ordinary distant cloud banks continue to use the low-resolution result. Preserve silhouette smoothing, foreground craft occlusion and in-cloud intersections; do not simply remove all full-resolution tracing. Then re-evaluate adaptive resolution with horizon, downward, sunset and moving-camera image checks. The paired previous-shader measurement is diagnostic evidence, not a recommendation to restore its older silhouette artifacts blindly.

Landing tails are a separate issue and need cloth/physics profiling; the cloud tests do not establish their cause.

Production cloud settings and shaders were not altered by these tests. Raw data: `horizon-results.json`, `composite-results.json`, plus the full lab report. Static tests use 1100×700 and fixed views; their times must not be compared directly to the live 1280×720 checkpoint as if they were the same workload.
