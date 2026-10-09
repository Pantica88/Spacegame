# Cloud rendering optimization — 2026-10-06

Implemented against the existing, uncommitted working tree. No physics, controls, camera response, authored weather pixels, brush generation, sample budget, resolution, texture filtering, density threshold, opacity threshold, lighting or compositing settings were changed.

## Results

Godot 4.5.1, OpenGL Compatibility, RX 580 / Mesa 25.0.7, i5-9600K, 1280×720, VSync off, dummy audio. Values below are median **total viewport GPU time** and independently measured **frame wall time** in milliseconds. They are synthetic rendering measurements with the craft and launch structures hidden; they do not establish full-game FPS.

Each altitude/setting/version has 200 samples across four alternating reference/candidate rounds, with 30 warmup frames before each 50-sample batch. Family order and version order reverse each round. Only one GPU workload ran at a time. Both versions share the same generated noise texture and camera/sun/weather. Regular-only removes alpha; storm-only removes RGB without renormalization. Alpha includes both mushrooms and other storm formations. The extra sparse fixture contains a mushroom and a nearby stratocumulus stamp.

| Altitude | Weather | GPU before | GPU after | Frame before | Frame after |
|---:|---|---:|---:|---:|---:|
| 30 m | Both families | 8.570 | 8.576 | 9.019 | 9.007 |
| 30 m | Regular only | 6.997 | 6.388 | 7.410 | 6.772 |
| 30 m | Mushroom/storm only | 7.706 | 7.706 | 8.064 | 8.101 |
| 30 m | Empty authored weather | 4.469 | 1.801 | 4.683 | 1.949 |
| 30 m | Renderer disabled | 1.800 | 1.800 | 1.936 | 1.963 |
| 30 m | Sparse stamps | 8.298 | 8.117 | 8.688 | 8.543 |
| 3,850 m | Both families | 8.693 | 8.693 | 9.114 | 9.157 |
| 3,850 m | Regular only | 7.087 | 6.445 | 7.435 | 6.771 |
| 3,850 m | Mushroom/storm only | 7.803 | 7.805 | 8.233 | 8.245 |
| 3,850 m | Empty authored weather | 4.560 | 1.800 | 4.767 | 1.939 |
| 3,850 m | Renderer disabled | 1.801 | 1.802 | 1.959 | 1.952 |
| 3,850 m | Sparse stamps | 8.000 | 7.982 | 8.399 | 8.395 |
| 100,000 m | Both families | 11.087 | 11.070 | 11.482 | 11.505 |
| 100,000 m | Regular only | 9.716 | 8.773 | 10.172 | 9.233 |
| 100,000 m | Mushroom/storm only | 10.438 | 10.447 | 10.848 | 10.823 |
| 100,000 m | Empty authored weather | 7.291 | 4.158 | 7.604 | 4.383 |
| 100,000 m | Renderer disabled | 4.157 | 4.159 | 4.386 | 4.368 |
| 100,000 m | Sparse stamps | 7.334 | 4.438 | 7.672 | 4.658 |

Regular-only total GPU time decreases by 8.7–9.7%. Empty weather saves 2.67–3.13 ms and matches the disabled pass. Sparse weather at 100 km saves 2.90 ms (39.5%); its near-ground/interior benefit is small (0.02–0.18 ms). Dense mixed and storm-only weather remain effectively unchanged. Frame-time p95 values and every individual batch’s GPU/frame medians are retained in [the paired log](/tmp/aphelion-cloud-opt-20261006/paired-final.log).

Before any production edits, the original family probe was rerun. GPU medians for both / regular / storm / empty / disabled were 8.559 / 6.993 / 7.704 / 4.362 / 1.800 ms at 30 m; 8.674 / 7.081 / 7.801 / 4.450 / 1.801 ms at 3,850 m; and 11.000 / 9.669 / 10.375 / 7.235 / 4.150 ms at 100,000 m. See [fresh baseline](/tmp/aphelion-cloud-opt-20261006/fresh-baseline.log). The main table uses the later alternating comparisons to control drift.

## Implementation and conservatism

- `cloud_weather_map.gd` caches exact nonzero occupancy separately for RGB and alpha, with conservative local direction bounds. A filtered texel can contribute one whole texel-center spacing in either direction. Bounds include that footprint, longitude wrap, clamped polar rows, and sine/cosine extrema inside each angular interval. Even the smallest nonzero storm weight counts, preserving its faint background as well as its stem/cap.
- Image assignment, loading, restoration, initialization and clearing invalidate the derived cache. Painting and erasing invalidate only affected latitude rows; queued edits union their dirty spans. Cache data is not exported or saved. Ordinary unchanged frames use cached values and never scan images or read the GPU.
- `cloud_layer.gd` hides the entire pass for empty authored weather and restores visibility after an edit/restore. Missing authored weather retains procedural clouds. The layer extrudes each family’s direction bounds over its full radial shell, adds outward rounding padding, and supplies planet-local bounds.
- The shader intersects rays with the two family boxes and an outward-padded low-cloud sphere. It discards proven-empty rays and skips density/lighting for original sample midpoints outside both occupied intervals. It still performs the original cursor additions, step sizes, loop count and clear-air-gap crossing. Both near and far banks survive. No integration endpoints or density/opacity cutoffs move. A sample’s radius is reused for its height and lighting.
- Broad bounds added approximately 0.17–0.24 ms in an initial experiment. That version was rejected. A shared preprocessed shader variant now includes the bounds code only for regular-only maps or compact bounds occupying less than half the unit cube. Broad mixed/storm maps use the original traversal with bounds code compiled out. At observer distances beyond four body radii, the original traversal is also used to avoid distant floating-point intersection uncertainty.

The cache’s measured first build for the bundled 512×256 map is 41.154 ms, once after load/replacement. Ten thousand unchanged `has_clouds()` plus bounds queries average 1.093 µs per pair. Rebuilds after 0.025 / 0.1 / 0.35 rad brush strokes take median 1.585 / 3.570 / 10.234 ms respectively; only dirty rows are rescanned. These are incremental cache costs, not total brush or gameplay frame times. See [cache measurements](/tmp/aphelion-cloud-opt-20261006/cache-cost.log).

## Validation

All **59 paired images matched exactly**: maximum RGB delta 0, zero changed pixels in every 1280×720 frame.

The deterministic comparison harness freezes sky/water animation, shares noise, and captures the original shader independently of the new visibility/bounds path. It records maximum/mean RGB differences and cloud contribution against a hidden pass, so empty views can be identified. Ground, cloud interiors, horizon gaps, orbit, sunset, mushrooms, towers, overlaps, rotated off-pole stamps, seam filtering and both poles are included. Very distant orbit also exercises the conservative fallback.

See the [interactive before/after gallery](/tmp/aphelion-cloud-opt-20261006/comparison.html), [pixel metrics](/tmp/aphelion-cloud-opt-20261006/images/comparison.json), and [capture log](/tmp/aphelion-cloud-opt-20261006/visual-final.log). Representative silhouettes, overlapping banks, seam views and far-bank sunset captures were inspected visually. All original PNGs are retained in the gallery’s links.

Focused checks cover occupancy cache lifecycle, all four channels (including tiny float weights), 49,129 support directions, radial envelopes, rotated planets, global/distant fallback, painting, editor undo/redo, tile capture, PCK saves, repeated saves, moon weather and fresh-process restart. Graphical checks cover cloud formations, mushrooms, far-bank traversal, distant clouds, sunset lighting, shell crossings, flames/depth ordering and editor visibility. The existing 30-case shader comparison also passes with zero RGB differences.

Two pre-existing test problems were investigated and repaired without changing production rendering:

1. `test_atmosphere.gd` referenced removed `World.PLANET_ROTATION_SECONDS`, preventing inherited cloud tests from parsing. It now reads the planet definition’s rotation period. The same test repair was applied in the saved baseline project.
2. `test_clouds.gd` raised its reference near plane to 1 km while the screen triangle’s culling margin was only 100 m. That culled the cloud pass entirely. The baseline’s mean RGB difference was 0.048194; enlarging the culling margin only within that test reduced it to 0.000003. The candidate reproduced the same original failure. The corrected fixture is tested on both versions.

The horizon/distance fixtures inject artificial density, so they now bind fully occupied storm weather to keep camera/shell uniforms current and explicitly bypass occupancy for their diagnostic shader. They pass on both baseline and candidate with the same repaired fixtures.

## Reproduction and limits

Save both original `scripts/cloud_layer.gd` and `assets/shaders/clouds.gdshader` into a reference directory before editing. Use isolated `XDG_DATA_HOME` paths, then run these sequentially:

```bash
./tools/run.sh --resolution 1280x720 --disable-vsync --audio-driver Dummy \
  --script res://tests/benchmark_cloud_occupancy.gd -- /tmp/reference-directory
./tools/run.sh --resolution 1280x720 --disable-vsync --audio-driver Dummy \
  --script res://tests/compare_cloud_occupancy.gd -- /tmp/reference-directory/clouds.gdshader /tmp/cloud-images
./tools/run.sh --headless --script res://tests/test_cloud_occupancy.gd
```

This is a conservative two-box accelerator, not a spatial hierarchy. Disconnected empty gaps inside a family’s overall box still use the original march. Dense weather and cloud-filled interiors can see little or no speedup. The shader-selection heuristic is based on this RX 580 validation; other GPUs and views may have different tradeoffs. First-use shader compilation and initial cache building are outside warm steady-state timings. The full gameplay FPS and other rendering backends/hardware were not benchmarked. Raw logs, baseline source copies, original images, and temporary save directories are under `/tmp/aphelion-cloud-opt-20261006`; those artifacts are local and may be cleared by the operating system.
