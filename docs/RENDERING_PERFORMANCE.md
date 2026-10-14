# Planetary rendering performance

Investigation and optimization of atmospheric scattering, terrain and planetary rendering, 13 October 2026. Branch `rendering-performance`.

## Summary

- **The game is GPU-bound in every outdoor scene.** Render CPU stays at or below 0.5 ms and draw calls at or below 800. Before this work the outdoor frame spent 13.7–16.5 ms on the GPU at 1080p on an RX 580. Three systems account for nearly all of it, in comparable shares: **atmospheric scattering** (2–7 ms), the **volumetric clouds** (4–8 ms) and, near sea level, the **ocean patch** (about 6.7 ms).
- **Scattering cost was dominated by its nested sunlight loop.** Every view-ray sample integrated a second ray toward the sun. A small precomputed table per body now replaces that loop, built with the loop's own quadrature. At the original sample budgets (**Ultra**) it reproduces the original captures within the run-to-run noise floor and removes 2.5–4.3 ms in flight and orbit.
- **Four quality presets.** Ultra keeps the original budgets and the original image. **High is the new default.** It also lowers view samples, takes longer steps on rays that end on a surface, and integrates the sky at half resolution. In the benchmark captures it differs from the original by about one display level or less on average.
- **Result with High (clouds on):** every outdoor scenario now runs at **68–130 FPS** at 1080p, where four of them were at 55–62 FPS. The upper atmosphere, the only scenario below 60 FPS, went from **55 to 73 FPS**, and high orbit from **65 to 111 FPS**. The workshop is unchanged at about 525 FPS.
- **No visual effect was removed or disabled.** The halo, horizon glow, sunset tint, night-side limb, eclipses and star fading are all still computed. Terrain detail, LOD, collision, landing and orbital physics are untouched.
- **The project already uses Forward+, not GL Compatibility.** `project.godot` and the performance lab both select `forward_plus` (the branch `renderer-forward-plus` was merged earlier). A measured Compatibility run of the same scenes is in [Renderer backends](#renderer-backends). Forward+ remains the right backend. The remaining bottlenecks are shader work that no backend switch would remove.

## Test setup

| Item | Value |
|---|---|
| GPU | AMD Radeon RX 580 8 GB (Polaris 10), Mesa 25.0.7 RADV, Vulkan 1.4.305 |
| Engine | Godot 4.5.1 double-precision custom build (`~/godot-double`), the project's engine (docs/FOUNDATION_REVIEW.md) |
| Renderer | Forward+ (project setting); Compatibility only for the comparison run |
| Resolution | 1920×1080 window, VSync off, uncapped, FXAA on (project setting), MSAA off |
| Fixture | `tests/benchmark_planet_rendering.gd`, eight fixed camera poses (below) |
| Sampling | 20 warm-up frames, then 90 measured frames per variant; two interleaved rounds with the variant order reversed; medians and 95th percentiles |
| Repeats | Reference and High were each run twice in an A/B/A/B order across the campaign; repeat medians agree within 0.05 ms GPU |

**Environment note:** this shell exports `GODOT_BIN=~/Downloads/Godot_v4.7.2-stable_linux.x86_64`, which `tools/run.sh` and `perf.sh` prefer over the 4.5.1 double build. The first exploratory runs silently used 4.7.2 and produced quite different numbers (for example 3.5 ms instead of 10.5 ms GPU at the surface without clouds, with fewer primitives). Every number in this report comes from the 4.5.1 double build, selected explicitly. Unset or change that variable before benchmarking.

### Scenarios

| Scenario | Pose |
|---|---|
| Workshop | Workshop mode, default craft, default camera |
| Surface, daylight | Craft at the flight origin (0 m, over open ocean), game camera, sun high |
| Surface, sunset | Same, camera facing a sun 1.7° above the horizon |
| Ascent | 12 km, engines on, game camera slightly above the craft |
| Upper atmosphere | 60 km, game camera |
| Low orbit | 150 km, game camera |
| High orbit | 1,600 km, camera aimed at the planet centre; the whole disc and terminator are visible |
| Night side | 300 km over the dark hemisphere, the horizon and backlit limb in frame |

The fixtures place the craft at the flight origin, which lies over ocean, not at the launch pad. The pad and launch complex are therefore off-screen. Their cost was measured separately as negligible: hiding the complex did not change GPU time or primitive counts in these poses.

### What is measured

- **Frame time:** the wall interval between completed draws. This includes CPU, GPU and scheduling. FPS is 1000 / median frame time.
- **GPU time:** `RenderingServer.viewport_get_measured_render_time_gpu()` for the main viewport plus the clouds' offscreen march and resolve viewports, as in `tests/benchmark_clouds.gd`.
- **Render CPU:** viewport render CPU plus renderer frame setup.
- **Draw calls, primitives, objects, video and texture memory:** `RenderingServer.get_rendering_info()`.
- **Attribution variants:** each scenario was also measured with the clouds hidden (`no_clouds`), with the clouds and ocean patch hidden (`no_ocean`), and with scattering forced to 2 view / 1 light samples (`air_min`), which approximates everything except scattering.

### Limitations

- **No per-pass GPU timings.** Outside the editor's visual profiler, Godot 4.5 records only per-viewport timestamps. Costs were attributed by hiding systems or changing shader inputs and measuring the difference. These differences are estimates, since passes overlap and hiding one changes what is drawn behind it.
- **Script time is not reported.** `Performance.TIME_PROCESS` returned implausible values (about 100 ms per frame) under this await-driven fixture. Main-loop CPU time is covered by the existing performance lab (`./perf.sh`), not by this fixture.
- **One machine.** These results come from one mid-range 2016-era GPU. Integrated GPUs, NVIDIA hardware and 4K were not measured.
- **The Compatibility comparison** used one round instead of two.
- **Static poses.** These are fixed camera poses, not a full mission replay. The existing performance lab covers launch, staging, re-entry and parachute events, and was not rerun for this report.

## Where the frame time went (before)

GPU ms, original code, clouds on unless noted. *Scattering* is `no_clouds` minus `air_min`. *Ocean* is `no_clouds` minus `no_ocean`.

| Scenario | Total | Clouds | Scattering | Ocean patch | Everything else |
|---|---|---|---|---|---|
| Surface, daylight | 14.52 | 4.0 | 2.3 | 6.8 | 1.4 |
| Ascent, 12 km | 14.86 | 6.9 | 2.3 | 3.6 | 2.1 |
| Upper atmosphere | 16.45 | 8.0 | 6.1 | — | 2.4 |
| Low orbit | 14.26 | 5.9 | 6.0 | — | 2.3 |
| High orbit | 13.75 | 4.7 | 7.4 | — | 1.7 |
| Night side | 8.58 | 4.0 | 2.8 | — | 1.8 |

With the original 64 view × 6 light samples forced everywhere (the `air_ultra` variant), surface GPU time rose from 10.5 to 24.9 ms with clouds hidden. This is why the code already had altitude bands (16/2 below 45 km, 32/3 up to 480 km, 64/6 beyond).

## Bottlenecks and evidence

| Area | Finding | Evidence |
|---|---|---|
| Nested raymarching | Each view sample ran a 2–6 step sunlight loop (`length`, two `exp`, a smoothstep and a sphere intersection per step), at up to 64 view samples per pixel. This was the largest single item in flight and orbit. | Replacing the loop with a table at identical budgets cut no-clouds GPU time from 9.07 to 4.76 ms in high orbit (−48%), and by 2.5–2.6 ms in the upper atmosphere and low orbit |
| Fragment work duplicated across systems | The sky, terrain, ocean (three integrations per vertex), clouds (one per cloud pixel) and moons each integrate the same atmosphere. The clouds use only 4/1 samples. | Scattering switched off in the sky only: the sky accounts for 1.0–1.8 ms; terrain and water haze for 2.2–2.5 ms in orbit at Ultra |
| Uniform step length | Rays that end on terrain or water integrate density that rises smoothly toward the ground, yet they used the same 3%-of-air-depth step cap as grazing limb rays | Twice the step length on those rays changed captures by ≤ 0.08 display levels and saved 0.4–0.9 ms in flight and orbit (0.1 ms on the night side) |
| Full-resolution sky | The sky's scattering ran for every background pixel at 1080p, although it varies smoothly | Forward+'s half-resolution sky pass saved 1.3 ms at the surface and at sunset |
| Ocean patch | 196k vertices and 393k triangles; three atmosphere integrations per vertex; about 30 texture reads and a four-sample mirrored cloud deck per water pixel | Hidden: −6.75 ms at the surface, −3.6 ms at 12 km. A quarter of the vertices: −1.45 ms, so about 2 ms is vertex work and about 4.8 ms is fragment work. Cloud-reflection mode 0 instead of 3: −1.4 ms |
| Volumetric clouds | 4–8 ms in every outdoor scene | `full` minus `no_clouds`. This is uncommitted work in progress (`clouds_volume.gdshaderinc`, `cloud_layer.gd`), so it was not modified |
| Terrain detail noise | The six procedural detail layers cost ≤ 0.1 ms in every scenario | All six replaced by constants: GPU time changed by 0.01–0.12 ms, within noise. They already fade out by pixel footprint, so they were left unchanged |
| Mesh LOD, draw calls, primitives | Not a bottleneck: ≤ 800 draw calls, ≤ 1.64M primitives (mostly the ocean), render CPU ≤ 0.5 ms. `_update_planet_lod()` never selects LODs 3 and 4 (it clamps to 1–2 to avoid distant speckles) | Table D; `world_view.gd` |
| Unnecessary updates | `_update_atmosphere()` runs once per flight tick and sets about 30 shader parameters. Its CPU cost is not measurable against GPU time. Workshop mode already uses a solid background, so the sky shader does not run there | Render CPU ≤ 0.5 ms; workshop GPU 1.67 ms in every variant |
| Shader compilation | Each preset uses the same shaders. Only the half-resolution sky is a second variant, compiled the first time a preset selects it. The sunlight tables are built once per body and light count when the planet loads or a preset changes: 13, 18 and 32 ms for the 2-, 3- and 6-sample tables, about 63 ms in total | `AtmosphereQuality.prepare()` |
| Lookup-texture candidates | The sunlight optical depth is 2D (height, sun angle), so a table is exact and small. Full single-scattering tables (3D/4D, Bruneton style) or aerial-perspective volumes would also replace the view loop, but they cost far more memory and implementation effort, and they cannot reproduce the art-tuned sunset tint and penumbra terms without reworking them | See [Lookup tables](#lookup-tables) |

## Optimizations implemented

1. **Sunlight optical-depth table** (`scripts/atmosphere_quality.gd`, `assets/shaders/atmosphere.gdshaderinc`).
   - A 256×64 RG half-float texture per body and light-sample count stores the Rayleigh and Mie optical depth from each height and sun angle to the top of the air, at density 1. It is built on the CPU with the shader loop's own quadrature (13–32 ms per table) and is cached. Density is applied in the shader, so editing a planet's density does not need a rebuild.
   - Bilinear interpolation stays within 0.002 transmittance of the loop (mean 0.0001). That is below one 8-bit display step.
   - The shader uses the table only when the call's body radii and light count match it. Every other call keeps the loop and is unchanged: the clouds' haze, the map, the planet editor, the ocean's mirrored sky and the moons' own (airless) bodies. Moons use the home body's table for their foreground haze.
   - Building one table per light count matters. A single six-sample table brightened the lower-atmosphere sky by about 2 luma levels (mean difference 7 levels), because the original renders that band with two sunlight samples.
2. **Quality presets** (`AtmosphereQuality.PRESETS`). The view-sample limit per altitude band, the step length for surface-ending rays, and the sky resolution. These are applied by `WorldView.set_atmosphere_quality()`, saved in the profile, and cycled from the pause menu (**Atmosphere: High**). Changes take effect on the next frame with no restart.
3. **Surface-ray step length** (`atmosphere_surface_step`). Rays ending before the top of the air use a configurable step cap; limb and sky rays keep 3%.
4. **Half-resolution sky** (`sky.gdshader`, `SKY_HALF_RES`). `world_view.gd` derives a second shader from the sky's own code with `render_mode use_half_res_pass`. The half-resolution pass stores the scattered light and the luminance of the transmission. Within 0.4 radians of the sun, the full-resolution pass recomputes the scattering, so the sun's halo keeps its reddened transmission. Stars, galaxies and the distant limb glow are still drawn at full resolution. Under Compatibility the code falls back to the full-resolution path.
5. **Benchmark and tests.** `tests/benchmark_planet_rendering.gd` covers the eight scenarios with attribution variants and captures. `tests/test_atmosphere_quality.gd` (146 checks, part of `tools/check.sh`) covers preset limits, band boundaries, table values against the loop, caching, airless bodies, runtime switching on the live materials, sky-variant selection and profile sanitizing.

### Presets

View samples per observer band: the lower half of the air (below 45 km on Verdant), up to 0.8 body radii (480 km), and beyond.

| Preset | View samples | Sunlight samples (table) | Surface-ray step | Sky | Intent |
|---|---|---|---|---|---|
| Low | 8 / 12 / 16 | 2 / 3 / 6 | 12% | half resolution | Performance |
| Medium | 10 / 20 / 32 | 2 / 3 / 6 | 9% | half resolution | Balanced |
| **High** (default) | 12 / 24 / 48 | 2 / 3 / 6 | 6% | half resolution | Visually equivalent to Ultra |
| Ultra | 16 / 32 / 64 | 2 / 3 / 6 | 3% | full resolution | The original image |
| *reference* | 16 / 32 / 64 | loop | 3% | full resolution | The original code path, for A/B tests only (not in the menu) |

Every preset keeps Ultra's sunlight quadrature, so the colour of sunlight never changes between presets. Six view samples in the lower air produced a faint diagonal band in the ascent sky, so Low stops at eight.

## Before and after

"Original" is the pre-change commit `18a3ef2` (with the working tree's cloud work in progress). The *reference* preset of the new code matched it within 0.1 ms in every scenario.

### A. Full frame (clouds on): median FPS / frame ms / p95 frame ms

| Scenario | Original | Ultra | **High (default)** | Medium | Low |
|---|---|---|---|---|---|
| Workshop, stationary rocket | 529 / 1.89 / 3.16 | 526 / 1.90 / 3.42 | **525 / 1.91 / 3.52** | 525 / 1.91 / 3.63 | 528 / 1.89 / 3.71 |
| Surface, daylight | 62 / 16.07 / 18.12 | 67 / 14.96 / 16.87 | **74 / 13.48 / 15.53** | 74 / 13.47 / 15.46 | 74 / 13.43 / 15.50 |
| Surface, sunset | 62 / 16.10 / 18.43 | 65 / 15.36 / 17.23 | **72 / 13.87 / 15.86** | 72 / 13.82 / 15.71 | 73 / 13.75 / 15.71 |
| Ascent, 12 km, engines on | 61 / 16.39 / 18.29 | 65 / 15.48 / 17.16 | **68 / 14.62 / 16.47** | 70 / 14.36 / 16.42 | 71 / 14.16 / 15.96 |
| Upper atmosphere, 60 km | 55 / 18.07 / 20.03 | 66 / 15.24 / 17.19 | **73 / 13.79 / 15.75** | 76 / 13.13 / 15.06 | 80 / 12.50 / 14.49 |
| Low orbit, 150 km | 62 / 16.01 / 17.92 | 75 / 13.26 / 15.00 | **84 / 11.93 / 13.98** | 88 / 11.36 / 13.04 | 94 / 10.63 / 11.90 |
| High orbit, 1,600 km, whole planet | 65 / 15.41 / 17.44 | 96 / 10.43 / 13.04 | **111 / 8.99 / 11.46** | 115 / 8.67 / 10.50 | 120 / 8.36 / 9.42 |
| Night side, 300 km, lit limb | 104 / 9.59 / 11.83 | 125 / 7.98 / 10.55 | **130 / 7.72 / 9.90** | 130 / 7.67 / 8.85 | 145 / 6.90 / 8.48 |

With High, every outdoor scenario's 95th-percentile frame is at or under 16.5 ms. Under the original code, all six atmospheric scenarios had a 95th percentile above 17.4 ms.

### B. GPU time, median ms (clouds on)

| Scenario | Original | Ultra | High | High (repeat) | Medium | Low | High vs original |
|---|---|---|---|---|---|---|---|
| Workshop, stationary rocket | 1.67 | 1.67 | 1.67 | 1.67 | 1.67 | 1.67 | +0% |
| Surface, daylight | 14.52 | 13.68 | 12.27 | 12.27 | 12.23 | 12.17 | −15% |
| Surface, sunset | 14.84 | 14.01 | 12.61 | 12.60 | 12.55 | 12.49 | −15% |
| Ascent, 12 km, engines on | 14.86 | 14.10 | 13.22 | 13.25 | 12.94 | 12.83 | −11% |
| Upper atmosphere, 60 km | 16.45 | 13.94 | 12.53 | 12.50 | 11.90 | 11.35 | −24% |
| Low orbit, 150 km | 14.26 | 11.80 | 10.48 | 10.50 | 9.94 | 9.25 | −27% |
| High orbit, 1,600 km, whole planet | 13.75 | 9.48 | 8.17 | 8.15 | 7.51 | 7.01 | −41% |
| Night side, 300 km, lit limb | 8.58 | 7.27 | 6.60 | 6.63 | 6.41 | 6.14 | −23% |

### C. GPU time, median ms, clouds hidden (planetary rendering alone)

| Scenario | Original | Ultra | High | Medium | Low | High vs original |
|---|---|---|---|---|---|---|
| Surface, daylight | 10.51 | 9.65 | 8.25 | 8.20 | 8.14 | −21% |
| Surface, sunset | 11.07 | 10.21 | 8.79 | 8.75 | 8.69 | −21% |
| Ascent, 12 km, engines on | 8.01 | 7.25 | 6.40 | 6.16 | 6.02 | −20% |
| Upper atmosphere, 60 km | 8.44 | 5.88 | 4.48 | 3.90 | 3.31 | −47% |
| Low orbit, 150 km | 8.36 | 5.81 | 4.53 | 3.97 | 3.29 | −46% |
| High orbit, 1,600 km, whole planet | 9.05 | 4.76 | 3.47 | 2.83 | 2.33 | −62% |
| Night side, 300 km, lit limb | 4.59 | 3.38 | 2.67 | 2.47 | 2.15 | −42% |

Near the surface the presets converge, because what remains there is the ocean patch and clouds, not scattering.

### D. Scene statistics (High, clouds on)

| Scenario | Render CPU ms | Draw calls | Primitives | Objects | Video memory MB (original → High) |
|---|---|---|---|---|---|
| Workshop, stationary rocket | 0.45 | 777 | 579,725 | 815 | 345.0 → 345.2 |
| Surface, daylight | 0.47 | 368 | 1,641,791 | 446 | 370.2 → 374.5 |
| Surface, sunset | 0.44 | 282 | 1,450,752 | 358 | 370.2 → 374.5 |
| Ascent, 12 km, engines on | 0.46 | 300 | 1,452,290 | 360 | 370.2 → 374.5 |
| Upper atmosphere, 60 km | 0.46 | 352 | 971,327 | 445 | 370.2 → 374.5 |
| Low orbit, 150 km | 0.44 | 286 | 780,297 | 359 | 395.4 → 399.6 |
| High orbit, 1,600 km, whole planet | 0.32 | 39 | 81,077 | 81 | 395.4 → 399.6 |
| Night side, 300 km, lit limb | 0.28 | 8 | 286,661 | 8 | 395.4 → 399.6 |

The 4.2 MB increase is the half-resolution sky buffer (960×540 RGBA16F). The sunlight tables add 4 × 64 KB.

## Visual comparison

Captures were taken with the clouds hidden and compared per pixel against the reference preset. Differences are in 8-bit display levels: mean, 99th percentile, and the share of pixels differing by more than 2 levels. Rendering is deterministic except for animated content (ocean waves, cloud-reflection drift and star twinkle), whose phase depends on how fast a run is. The reference-versus-reference row is the noise floor.

| Scenario | Reference repeat | Ultra | High | Medium | Low |
|---|---|---|---|---|---|
| Surface, daylight | 0.41 / 4 / 1.9% | 0.49 / 4 / 2.6% | 1.07 / 10 / 9.2% | 0.96 / 8 / 7.2% | 1.04 / 9 / 7.7% |
| Surface, sunset | 0.18 / 1 / 0.3% | 0.47 / 4 / 1.9% | 0.86 / 6 / 5.1% | 0.88 / 6 / 4.8% | 0.95 / 6 / 4.9% |
| Ascent, 12 km | 0.05 / 1 / 0.2% | 0.23 / 2 / 0.8% | 0.56 / 5 / 2.9% | 0.69 / 5 / 3.0% | 0.91 / 5 / 8.5% |
| Upper atmosphere | 0.00 / 0 / 0.0% | 0.01 / 0 / 0.0% | 0.07 / 1 / 0.0% | 0.09 / 1 / 0.0% | 0.18 / 1 / 0.0% |
| Low orbit | 0.00 / 0 / 0.0% | 0.01 / 0 / 0.1% | 0.16 / 2 / 0.9% | 0.18 / 2 / 0.9% | 0.26 / 2 / 0.9% |
| High orbit | 0.00 / 0 / 0.0% | 0.02 / 0 / 0.2% | 0.04 / 1 / 0.2% | 0.05 / 1 / 0.2% | 0.06 / 1 / 0.2% |
| Night side | 0.00 / 0 / 0.0% | 0.03 / 0 / 0.3% | 0.08 / 1 / 0.3% | 0.09 / 1 / 0.3% | 0.13 / 1 / 0.2% |

The surface differences are mostly water. Split by region in the daylight surface view, High differs from the reference by a mean of 0.18 levels (max 1) in the top 10% of the image (sky) and 1.35 in the lower 60% (water). At sunset, High's sky differs by 0.47 (max 5). Side by side, the water at the horizon is indistinguishable apart from wave and reflection phase.

Checked specifically:

- **Orbital halo and limb, night-side limb:** within 0.1 levels in every preset. Contrast-stretched crops of the backlit night limb at Low show no banding.
- **Sunrise and sunset:** the sun's halo keeps its full-resolution colour. `test_atmosphere.gd`'s sunset-warmth, night-dimming and eclipse assertions pass.
- **Ascent transitions:** the band boundaries at 45 km and 480 km are unchanged from the original. Each preset keeps the original sunlight quadrature, so crossing a band changes only view samples, as before.
- **Terrain colour:** the terrain shader's surface colour, coast, biome and detail code is unchanged. Only its haze integration is affected.

Side-by-side captures with clouds on (original | High | Low): [surface, daylight](screenshots/atmosphere-quality/surface-day.jpg), [surface, sunset](screenshots/atmosphere-quality/surface-sunset.jpg), [ascent](screenshots/atmosphere-quality/ascent.jpg), [upper atmosphere](screenshots/atmosphere-quality/upper-atmosphere.jpg), [low orbit](screenshots/atmosphere-quality/low-orbit.jpg), [high orbit](screenshots/atmosphere-quality/high-orbit.jpg), [night side](screenshots/atmosphere-quality/night-side.jpg). The concentric bands visible in the clouds at 60 km appear identically in the original. They come from the cloud renderer, not these changes.

**Trade-offs introduced:**

- Ultra: none measurable.
- High: about one display level of difference near the surface, mostly in distant water haze. It is not visible side by side.
- Low: a slightly larger difference during ascent (8.5% of pixels by more than 2 levels, still about 1 level on average).
- High, Medium and Low: stars and the Milky Way are dimmed by the luminance of the atmosphere's transmission instead of its colour. This is visible only near the horizon at night, as slightly less reddening. They also use 4 MB more video memory.

## Lookup tables

| Option | Memory | Accuracy against the current look | Effort | Verdict |
|---|---|---|---|---|
| Sunlight optical depth, 2D (implemented) | 64 KB per body and light count | Exact quadrature; ≤ 0.002 interpolation error | Small | Removes the nested loop; done |
| Precomputed sky-view table (Hillaire 2020), per frame | About 200 KB | Changes the art terms (penumbra, sunset tint, exposure) unless they are ported | Needs a per-frame render pass | Not needed now: the half-resolution sky already captures most of the sky saving |
| Aerial-perspective volume (froxels) for terrain haze | 1–4 MB | Good for terrain; limb accuracy depends on depth slices | Needs a compute or multi-pass setup | The best next step for orbital terrain haze, if needed (below) |
| Full 4D single-scattering table (Bruneton) | Several MB per body | Physically based, but a different look | Large | Not justified: it would replace the art-tuned model rather than optimize it |

## Renderer backends

The project already uses **Forward+** (`project.godot`: `renderer/rendering_method="forward_plus"`). The brief's assumption of GL Compatibility predates the merge of `renderer-forward-plus`. Two documents still described Compatibility; `ATMOSPHERE.md` and `PERFORMANCE_LAB.md` are now corrected.

The same scenes and High preset under Compatibility (one round; Compatibility cannot use the half-resolution sky, so it computes the sky at full resolution):

| Scenario | Forward+ GPU ms | Compatibility GPU ms | Forward+ frame ms | Compatibility frame ms |
|---|---|---|---|---|
| Workshop, stationary rocket | 1.67 | 0.99 | 1.91 | 1.16 |
| Surface, daylight | 12.27 | 11.69 | 13.48 | 12.87 |
| Surface, sunset | 12.61 | 12.15 | 13.87 | 13.34 |
| Ascent, 12 km, engines on | 13.22 | 14.32 | 14.62 | 15.53 |
| Upper atmosphere, 60 km | 12.53 | 11.82 | 13.79 | 12.97 |
| Low orbit, 150 km | 10.48 | 10.11 | 11.93 | 11.10 |
| High orbit, 1,600 km, whole planet | 8.17 | 8.07 | 8.99 | 8.59 |
| Night side, 300 km, lit limb | 6.60 | 6.06 | 7.72 | 6.53 |

The planetary cost is fragment arithmetic in custom shaders, which costs the same under any backend. Compatibility saves 0.1–0.7 ms in most scenes by doing less: it has no screen-space AA (the project's FXAA setting reports an error and is skipped, and the globe's limb is visibly aliased), a simpler pipeline and no clustered lighting. It is slower during the ascent.

| | Forward+ (current) | Compatibility | Mobile |
|---|---|---|---|
| Atmosphere | Half-resolution and quarter-resolution sky passes (used now) | Full resolution only | Half-resolution sky pass |
| Compute shaders | Yes (RenderingDevice; the clouds already have compute prototypes) | No | Yes |
| Future volumetric clouds | Compute-based marching and temporal reconstruction | Fragment-only | Possible, with fewer passes |
| Lighting | Clustered lights, SDFGI, VoxelGI, SSAO, SSR, volumetric fog | Basic forward lighting | A subset |
| Hardware reach | Vulkan, D3D12 or Metal; excludes very old or web targets | Widest, including web | Vulkan; aimed at mobile and low-end GPUs |
| Code impact | None | The `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` depth paths already exist; the half-resolution sky falls back automatically | A test pass would be needed |

**Recommendation:** stay on Forward+. Switching backends would not fix the remaining costs, which are cloud, ocean and haze shader arithmetic. Forward+ is what makes the half-resolution sky and future compute-based clouds or aerial-perspective volumes possible. Keep the existing Compatibility fallbacks so a low-end or web build stays possible, and treat **Mobile** as the candidate for minimum-spec hardware if it is ever needed.

## Remaining bottlenecks

At High, about 12–13 ms of GPU time per outdoor frame at 1080p on the RX 580:

1. **Volumetric clouds: 4–8 ms.** This is now the largest item outside the ocean. The cloud renderer is uncommitted work in progress, so it was deliberately left alone.
2. **Ocean patch: about 6.7 ms at the surface, 3.6 ms at 12 km.** About 4.8 ms is fragment work (four `untiled` normal layers with three reads each, sixteen swell-gradient reads plus eight sea-state reads, the four-sample mirrored cloud deck, and screen and depth reads). About 2 ms is vertex work (196k vertices, each with three atmosphere integrations, two of them on the light loop).
3. **Terrain and water haze from orbit: about 1–2 ms at High.** This is per-pixel integration over the whole disc.

## Engine 4.7.2

On 2026-10-13 the project moved from Godot 4.5.1 to 4.7.2, both double-precision source builds ([FOUNDATION_REVIEW.md](FOUNDATION_REVIEW.md), entry 1). All other numbers in this report are from 4.5.1. The same benchmark with the High preset, clouds on, one run per engine:

| Scenario | 4.5.1 FPS / GPU ms | 4.7.2 FPS / GPU ms | Draw calls 4.5.1 → 4.7.2 |
|---|---|---|---|
| Workshop, stationary rocket | 525 / 1.67 | 574 / 1.52 | 777 → 697 |
| Surface, daylight | 74 / 12.27 | 75 / 12.11 | 368 → 144 |
| Surface, sunset | 72 / 12.61 | 72 / 12.60 | 282 → 282 |
| Ascent, 12 km, engines on | 68 / 13.22 | 69 / 13.09 | 300 → 146 |
| Upper atmosphere, 60 km | 73 / 12.53 | 75 / 12.14 | 352 → 145 |
| Low orbit, 150 km | 84 / 10.48 | 89 / 10.25 | 286 → 156 |
| High orbit, 1,600 km, whole planet | 111 / 8.17 | 112 / 8.13 | 39 → 39 |
| Night side, 300 km, lit limb | 130 / 6.60 | 139 / 6.55 | 8 → 8 |

`test_packaged_rendering.gd` passes on a 4.7.2 release export, run through the test-only template. Captures match 4.5.1 within the noise floor (mean difference ≤ 0.5 display levels; the largest value is the animated ocean). The fewer draw calls in 4.7.2 come from the launch complex, which lies outside these views but was still drawn by 4.5.1. The planetary bottlenecks described above are shader work and are unchanged by the engine version.

## Recommended next steps

1. **Ocean (largest planetary item at sea level, about 4–6 ms available):**
   - Compute the per-vertex mirrored-sky haze once per vertex ring, or from the sunlight table.
   - Decide whether the mirrored cloud deck (mode 3, chosen 2026-10-09) should become preset-dependent: mode 0 measured −1.4 ms at the surface.
   - Consider fewer patch rings beyond the 85 m displacement radius.
   - Each of these is an art decision for the ocean's owner, so none was made here.
2. **Clouds:** once the current cloud work lands, give it the same attribution treatment. The benchmark's `full` vs `no_clouds` variants already isolate it. The compute-shader prototypes are a Forward+ path to lower cost.
3. **Orbital terrain haze:** if more orbital headroom is needed, an aerial-perspective volume (froxel) pass would replace per-pixel terrain haze integration. Under High it is no longer the limiting factor.
4. **Wider hardware coverage:** run `tests/benchmark_planet_rendering.gd` on an integrated GPU and an NVIDIA card, and at 1440p and 4K, before choosing the shipped default for slower machines. Also rerun the performance lab (`./perf.sh`) for the in-mission checkpoints.
5. **Benchmark environment:** unset `GODOT_BIN`, or point it at the double build (now 4.7.2 in `~/godot-double/src-4.7`), in shells used for performance work. The official downloads are single precision.

## Reproducing

Run in a graphical session with nothing else using the GPU:

```bash
export GODOT_BIN=$HOME/godot-double/src-4.7/bin/godot.linuxbsd.editor.double.x86_64   # 4.7.2 double
# One run per preset. Captures and results.json go to BENCH_OUT.
for q in reference ultra high medium low; do
  BENCH_QUALITY=$q BENCH_VARIANTS=full,no_clouds BENCH_OUT=/tmp/planet-bench/$q \
    XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) XDG_CACHE_HOME=$(mktemp -d) \
    ./tools/run.sh --disable-vsync --resolution 1920x1080 --audio-driver Dummy \
    --script res://tests/benchmark_planet_rendering.gd
done
# Attribution: BENCH_VARIANTS=no_clouds,no_ocean,air_min,air_ultra
# Compatibility: add --rendering-method gl_compatibility
```

Other options are documented at the top of the benchmark script: `BENCH_SCENARIOS`, `BENCH_FRAMES`, `BENCH_ROUNDS` and `BENCH_OCEAN_SHADING`. Compare captures from runs with the **same scenario and variant lists**; otherwise animated content differs in phase.

Validation:

```bash
./tools/check.sh                                                     # includes atmosphere_quality
./tools/run.sh --script res://tests/test_rendering.gd                # graphical
./tools/run.sh --script res://tests/test_atmosphere.gd               # graphical
./tools/run.sh --script res://tests/test_planet_preview.gd           # graphical captures
```

### Test results on this branch

| Check | Result |
|---|---|
| `tools/check.sh` (90 headless checks, including `atmosphere_quality`, `profile`, `planet_detail`, `planet_editor`, `terrain_landings`, `gameplay` and flight) | All pass |
| `test_rendering.gd` (graphical terrain continuity, 28 captures) | Pass |
| `test_planet_preview.gd` (graphical) | Pass |
| `test_atmosphere.gd` (graphical) | Four failures, **identical on the original commit `18a3ef2`**: the fixture expects a 17.5 km atmosphere where Verdant has 90 km, plus a launch-structure basis check. Its sunset, night, eclipse and workshop assertions pass |
| `test_packaged_rendering.gd` | Pass, on a release export of this branch (Linux, 4.5.1 double templates) to a scratch directory, with the default High preset; this also confirms the runtime-derived half-resolution sky shader compiles in an exported build. Its captures match the previously shipped 0.3.26 build at the pad and at 12 km |
