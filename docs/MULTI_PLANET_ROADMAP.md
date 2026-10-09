# Multi-planet roadmap

Goal: many planets and moons that the player can fly to, orbit and land on. This plan records the technical path from today's single-planet prototype. It was agreed on **2026-10-09**.

[STEAM_ROADMAP.md](STEAM_ROADMAP.md) advises proving one planet before adding destinations. This roadmap does not override that product gate. It removes technical limits early, while the codebase is small, so that adding planets later stays cheap.

## Resume here

Update this checklist as work lands. A new session should read this section first.

- [x] **1. Double-precision Godot build** — done 2026-10-09 (see [step 1 progress](#step-1-progress)). Open follow-ups there: saved clouds vs bundled, orphan bake cleanup, optional LTO, upstream bug report.
- [ ] **Prerequisite for 2 and 3:** the full `tools/check.sh` suite passes. Codex started fixing the 19 baseline failures on 2026-10-09 and stopped at its usage limit. Its unverified partial work is on branch `codex/baseline-fixes-wip` (`2eca4f0`): 19 test files, 7 scripts, the `check.sh` hang watchdog, and new `tests/flight_fixture.gd` / `tests/terrain_fixture.gd`. Review it before merging; check that tests were not loosened. Steps 2 and 3 refactor `flight_model.gd`, so they need the suite as a safety net and must not run in parallel with that fix.
- [ ] **2. Per-body definitions and body registry instead of hardcoded radius** — not started
- [ ] **3. Spheres of influence and per-vessel reference frames (multiplayer-ready)** — not started

Order: 1 → passing suite → 2 → 3, before visiting other planets. Designing planets in the editor can continue meanwhile; their `.tres` and bake format does not change.
- [ ] **4. Distant-body rendering** — not started
- [x] **5. Bake storage at many-body scale** — reference-aware cleanup and dry-run tool complete
- [ ] **Open decision:** Mun size (see below)

## Starting point (2026-10-09)

- Engine: official **Godot 4.5.1 Standard**, single precision. `Vector3` and `Transform3D` are float32; GDScript `float` is 64-bit. [PHYSICS.md](PHYSICS.md) describes scalar double-precision radius math as a workaround at the pad.
- Verdant: radius 600 km, surface gravity 9.81 m/s², 6 h day, 90 km atmosphere. This is about 1/10.6 of Earth's radius, the same scale as KSP's Kerbin.
- Mun: radius 16 km, orbit 12,000 km from Verdant's center, 1.61 day period. It spans about 0.16° from the surface. The real Moon spans 0.52°.
- Sun: placed 13.6 million km away (`SolarBody.DISTANCE`), radius 900 km.
- The craft feels only Verdant's gravity. Moon positions are used for debris and for the map's "moon encounter" cutoff.

## Why double precision

float32 position accuracy depends on distance from the origin:

| Distance from origin | float32 step | double step |
| --- | --- | --- |
| 600 km (Verdant) | 6 cm | ~1e-10 m |
| 13.6 million km (current sun) | ~1 km | ~2e-6 m |
| 1 AU | ~16 km | ~3e-5 m |

Interplanetary flight is not possible in float32 world coordinates. Each new float32 workaround is code that must be removed later.

## 1. Double-precision Godot build

Official Godot downloads are single precision only. Build the editor and every export template from source with `precision=double`, and rebuild them for each engine upgrade. Keep the build outside the repository and outside session scratch space.

```bash
mkdir -p ~/godot-double && cd ~/godot-double
git clone --depth 1 --branch 4.5.1-stable https://github.com/godotengine/godot.git src
python3 -m venv venv && venv/bin/pip install scons
# Linux build dependencies (needs sudo):
# sudo apt install build-essential pkg-config libx11-dev libxcursor-dev libxinerama-dev \
#   libgl1-mesa-dev libglu1-mesa-dev libasound2-dev libpulse-dev libudev-dev libxi-dev \
#   libxrandr-dev libwayland-dev
cd src
../venv/bin/scons platform=linuxbsd target=editor precision=double -j6
../venv/bin/scons platform=linuxbsd target=template_release precision=double -j6
# Windows templates cross-compile with mingw-w64:
# ../venv/bin/scons platform=windows use_mingw=yes target=template_release precision=double -j6
```

Results appear in `src/bin/`, for example `godot.linuxbsd.editor.double.x86_64`. Point `export_presets.cfg` custom templates at the double templates, and point `GODOT_BIN` at the double editor for `tools/run.sh`, `tools/check.sh` and `perf.sh`.

**Done when:** the full test suite passes on the double build, the performance lab baseline is re-recorded, and the Linux and Windows exports launch. Run tests with `XDG_*` directories in scratch space so real saves are not overwritten.

Shaders stay 32-bit on the GPU. The atmosphere, terrain and ocean shaders already work in camera-relative kilometres. Confirm they still render correctly after the switch.

### Step 1 progress

Everything for this step lives in `~/godot-double/`:

| Path | Contents |
| --- | --- |
| `src/` | Godot 4.5.1-stable source (`f62fdbd`) |
| `venv/` | Python venv with scons |
| `build-editor.log` | Editor build log; ends with `exit=<code>` |
| `run-suite.sh` | Runs every `tools/check.sh` check with fresh XDG folders and keeps going after failures. Usage: `run-suite.sh <project> <godot> <out_dir>` |
| `proj-single/`, `proj-double/` | Copies of the project (no `build/`, `.git`, `.godot`) so test reimports and writes never touch the working tree |
| `results-single/`, `results-double/` | Per-check logs and `summary.tsv` |
| `patches/` | Engine patches applied to `src/`, plus `*.ISSUE.md` drafts for reporting them upstream (not posted) |
| `build-templates.sh` | Applies `patches/` (idempotent), then builds Linux and Windows release and debug templates |

- [x] Source cloned and scons installed. The system has no X11, audio or Wayland dev packages. Godot 4.5 bundles those headers and loads the libraries at runtime, so the editor configures without them.
- [x] Editor build (2026-10-09, 20 min on 6 cores): `scons platform=linuxbsd target=editor precision=double production=yes lto=none -j6` → `src/bin/godot.linuxbsd.editor.double.x86_64`, version `4.5.1.stable.double.custom_build.f62fdbde1`. Verified: adding 1 mm to a vector at 600 km keeps 0.001 m (the official build gives 0), and adding 1 cm at 1 AU keeps 0.010 m (the official build is off by 6 km). This build had Wayland disabled; rebuild with Wayland now that `libwayland-bin` is installed. Wayland is disabled because `wayland-scanner` is missing; X11 is used instead. Shipping templates should include Wayland: `sudo apt install libwayland-bin`.
- Finding: `PlanetTerrain.bake_signature()` hashes `Engine.get_version_info().string`. That is `4.5.1-stable (official)` for downloads and `4.5.1-stable (custom_build)` for a source build, so every bake signature changes under the double build. Expect a one-time re-bake of every planet and moon in the double editor, and bake-matching test failures until then.
- Finding: `test_launch_complex` fails on the **official single-precision build**: "Graded terrain must share the deck datum" (tolerance 0.065 m, right at float32's 6 cm step at 600 km). Check whether the double build passes it.
- Finding: a failed `assert` in a `SceneTree` test skips `quit()`, so Godot idles forever and `tools/check.sh` hangs instead of failing. `run-suite.sh` stops a test 15 s after its first error. `check.sh` needs the same fix.
- [x] Single-precision baseline suite (`/tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64` on `proj-single`): **61 / 82 passed** while the editor compile loaded the CPU. Failed: launch_complex, maneuver_math, maneuver_map, orbit_interaction, orbit_mouse, orbital_map, sun, flight, distant_debris, detached_physics, body_collisions, game_loop, parachute, vessel_settling, hillside_recovery, cap_tether, radial_mass, builder, rollout, planet_bake, terrain_landings. These come from the working tree on the official build, not from double precision.
- [x] Re-ran the 21 baseline failures on an idle machine: all 21 still fail, so they are real failures in the working tree, not load effects. `launch_complex` is a real terrain bug: graded terrain sits 378 m off the deck datum for seed 73129 on both builds, so it has nothing to do with precision.
- [x] Double-precision suite on `proj-double`: **61 / 82 passed**. Compared with the baseline, `parachute` and `radial_mass` newly pass; `eight_boosters` and `planet` newly fail. The other 19 baseline failures fail on both builds.
  - `planet`: the test expected 0 mm terrain height on the flat pad, but a flat deck rises √(R² + d²) − R above the sphere (6.5 mm at 88 m). Float32 rounded that to zero. Fixed in `tests/test_planet_surface.gd` by checking against the real rise with 1 cm tolerance; passes on the official build.
  - `eight_boosters`: **Godot engine bug in double builds.** `SurfaceTool::VertexHasher` hashes raw `Vertex` bytes, and with 8-byte-aligned `Vector3` there are 4 uninitialized padding bytes after `Color`. Identical vertices hash randomly, so `index()` merges only some of them (plume: 900 vertices on the official build, 1,493–1,663 on double, varying per run). This affects every `SurfaceTool.index()` call. Still unfixed in upstream `master` (checked 2026-10-09). Patched: `patches/0001-surface-tool-double-padding.patch` adds an explicit zeroed `padding` field under `REAL_T_IS_DOUBLE`. Reapply the patch on every engine upgrade until upstream fixes it; it is worth reporting upstream.
- [x] Rebuilt the editor with the patch and Wayland (2026-10-09, 20 min). `eight_boosters` and `planet` pass; the plume mesh merges to exactly 900 vertices on three consecutive runs, matching the official build.
- [x] Full double suite on the patched editor (`results-double-patched/`): **63 / 82 passed, no regressions.** The 19 failures are a subset of the 21 baseline failures. `parachute` and `radial_mass` fail on the official build in every run and pass on double: they were float32 failures. 17 of the 19 fail with identical errors on both builds. The other two:
  - `game_loop`: the official build fails "Altitude plus recovery completes the contract" and "Hard impact ends the retry"; double fails only the second.
  - `planet_bake`: double passes the visible-contact check that the official build fails, then stops at line 50 (contact radius at the pad within 0.1 m of 600 km). Measured on both builds: the contact radius is 10.85 m low, and `elevation(UP)` on a default `PlanetDefinition` is **−375.8 m**. This is likely the same root cause as `launch_complex`'s 378 m deck offset.
- [x] Fix failures that come from double precision: `planet` test tolerance and the `SurfaceTool` engine patch. No others found.
- [ ] Linux and Windows export templates via `build-templates.sh`. `libwayland-bin` and `mingw-w64` are installed (2026-10-09). Godot 4.5 **requires the posix-thread mingw** and refuses the Mint default `win32` variant. Instead of `update-alternatives` (system-wide, needs sudo), `mingw-posix/` holds symlinks to `x86_64-w64-mingw32-{gcc,g++}-posix`, and the script puts it first on `PATH`.
  - [x] Linux `template_release` (12 min), Windows `template_release` (16 min), Linux and Windows `template_debug`
- [x] `tools/run.sh` (so `check.sh`, `hover.sh`, `test-plasma.sh` and `view-assets.sh`) and `tools/perf_lab.py` prefer the double editor in `~/godot-double` after `GODOT_BIN`. README and PERFORMANCE_LAB updated. `play.sh` runs the exported build, so it switches only after exporting with the double templates.
- [x] Re-baked bundled Verdant (with the Mun) and Ochre on the double build (`6034f27`, 36 s headless via `PlanetBaker._save_planet`, which skips the automatic bake cleanup so no old bakes were deleted). The player's saved overrides in `user://planets/` had already been re-baked on the double build at 12:23 through the planet editor. Saved and bundled planets have identical terrain settings; only painted clouds differ. The saved Verdant was baked while Codex's unfinished terrain changes were in the working tree, so its launch-area shape may differ from the bundled bake.
- [ ] Decide whether the player's saved clouds (Verdant repainted; Ochre and Mun gained cloud maps) should become the bundled versions
- [ ] Delete orphaned bakes (~880 MB, untracked; 3 old ones are tracked from the initial commit) with `tools/cleanup_planet_bakes.gd -- --delete`, after approval
- Perf comparison at 1280×720, standard preset, idle machine: official (`A-official-2`) vs double with stale bakes (`B-double`). Double adds ~1–2% render CPU and 0.3–0.8 ms frame p95; all scenarios stay well under 16.7 ms. B's lower GPU time and +3 s startup came from runtime-generated terrain; `C-double-rebaked` repeats B with fresh bakes.
- [x] Like-for-like result, `A-official-2` vs `C-double-rebaked` (same code, fresh bakes, valid, 1280×720): **GPU unchanged (±1%)**, render CPU +1–4%, physics CPU +6–16% (≤0.23 ms), frame mean +0.2–7.2% (about +3.5%), frame p95 +3–8% (0.4–1.0 ms), startup +0.6 s (9.3 s vs 8.7 s). The worst scenario (staging p95 14.1 ms) stays under 16.7 ms. Part of the CPU cost may be the missing LTO (`lto=none`) rather than double precision; official builds use LTO. Optional: test `lto=full` for shipping templates.
- Game settings (2026-10-09): removed the 120 FPS cap and enabled VSync (Godot default). The perf lab and benchmarks disable VSync themselves.
- [x] Install templates with `~/godot-double/install-templates.sh` into `~/.local/share/godot/export_templates/4.5.1.stable.double/`, where the double editor finds them by default. `export_presets.cfg` keeps empty `custom_template` paths, so no machine-specific paths get committed. (No templates were installed before this; earlier exports used templates that are no longer present.)
- [x] Test-export Linux and Windows to a scratch folder and launch the Linux build. Do not overwrite `build/0.3.26/`, which `play.sh` runs; a version bump and `tools/package_builds.py` are a separate release decision.
  - Result: exported `multi-planet` (`git archive` plus the 3 referenced bakes) to `~/godot-double/export-test/out/`. Linux and Windows exports succeed; the `.pck` is 191 MB (the 0.3.26 package was 1 GB because it included every orphan bake). The exported Linux build reports `4.5.1.stable.double.custom_build` and passes `--smoke-test` ("PASS: workshop, assembly, rollout, ignition, ascent, map, pause, return") in 2.7 s with isolated saves. The Windows export was not run (no Windows machine or Wine here).
- [x] Debug templates: Linux 8.5 min, Windows 19 min. All six templates include the `SurfaceTool` patch.
- [x] Performance lab baseline on the double build: `C-double-rebaked` set explicitly with `./perf.sh baseline C-double-rebaked` (B, with stale bakes, had become the automatic baseline)

## 2. Per-body definitions

Verdant's radius is a separate constant in several places. Changing `verdant.tres` alone breaks things.

- `scripts/planet_surface.gd` — `RADIUS`
- `scripts/physics_math.gd` — `PLANET_RADIUS`
- `scripts/world_view.gd` — `PLANET_RADIUS`
- `scripts/solar_body.gd` — `POSITION` and `moon_offset`
- `assets/shaders/ocean.gdshader` — `planet_radius` default
- `scripts/planet_editor.gd` — fallback radius

Most code reaches the planet through `PlanetSurface.home()`. Radius, gravity, atmosphere and rotation should come from each body's `PlanetDefinition`. Tests that assume 600 km values should derive them from the definition.

Add a body registry: every planet and moon has a stable id, and code can look up its definition, terrain and current position by id. Step 3's per-vessel `body` field refers to these ids.

**Done when:** changing Verdant's radius in its `.tres` file is the only edit needed for a working build, and a test proves it at two radii.

## 3. Spheres of influence and per-vessel reference frames

Use patched conics: a vessel orbits the body whose sphere of influence contains it.

**Each vessel has its own frame.** A vessel stores `body` plus position and velocity relative to that body's centre, for example `{body: "Mun", position: (0, 16200, 0)}`. There is no single world origin that follows the player's craft (a floating origin). Today the launch pad is the origin and `PLANET_CENTER` / `PlanetSurface.home()` assume one planet. Those go away.

- Physics for a vessel uses only its own body's gravity, terrain and atmosphere, so numbers stay small and precise wherever the vessel is.
- Crossing a sphere-of-influence boundary converts the state into the new body's frame and changes `body`.
- Rendering is a view: the camera follows one vessel, and everything else is converted to camera-relative positions only for drawing. Simulation state never depends on where the camera is.
- Debris, detached stages and parachutes carry their own `body` and frame too.

**Why:** this keeps multiple vessels at different bodies valid at once, which is what multiplayer (a server simulating every player's ship) and many-vessel single-player both need. Doing it before more systems assume one origin is far cheaper than retrofitting it. Multiplayer itself is not planned yet; see [STEAM_ROADMAP.md](STEAM_ROADMAP.md). Shared time warp is its main open design question.

- The vessel feels the current body's gravity, including moons.
- The orbital map predicts encounters and transitions. It currently stops with "encounter prediction is not available."
- Time warp keeps craft on rails within a sphere of influence.
- Landing, terrain collision and atmosphere work on any body, not only the home planet.

**Done when:** a craft can fly from Verdant orbit to a Mun landing and back, with the map predicting each transition, and a test simulates two vessels at different bodies in the same run.

## 4. Distant-body rendering

Even with double positions, the GPU depth buffer is 32-bit. Bodies millions of kilometres away need a separate approach instead of an ever-larger `camera.far`: scaled stand-in models, a separate far-scene camera layer, or both. Planet LOD tables (`RENDER_LODS`) should scale with body radius.

## 5. Bake storage

Each body's terrain bake is 17–30 MB. Twenty bodies would exceed 500 MB before textures. Superseded bakes in `assets/planets/baked/` and `assets/planets/moons/baked/` currently pile up untracked.

- Delete superseded bakes automatically when a planet is re-baked.
- Consider bake resolution by body size and importance.

Implemented: after a successful planet-and-moons save, delete only that system's unreferenced `<body-name>-<64 hex>.res` bakes. Cleanup waits for the parent save and checks every `.tres` ext_resource path under `assets/planets/` and `user://planets/`, preserving shared and legacy bakes. Failed saves or incomplete reference scans leave bakes intact. `tests/test_planet_bake_storage.gd` is registered in `tools/check.sh`.

One-off cleanup for all bundled bodies (dry run by default; deletion requires `--delete`):

```bash
tools/run.sh --headless --script res://tools/cleanup_planet_bakes.gd
tools/run.sh --headless --script res://tools/cleanup_planet_bakes.gd -- --delete
```

Dry run on 2026-10-09 found **32 orphaned bakes, 885.52 MiB**: 27 Verdant, 2 Ochre and 3 Verdant moon bakes. No existing asset bakes were deleted. Bake resolution remains a separate follow-up.

## Open decision: Mun size

Mesh and bake resolution are fixed, so a bigger Mun costs almost nothing to render. Vertex spacing at the equator grows with radius: about 200 m at 16 km and about 660 m at 54 km. Surface gravity stays fixed, so mass grows with radius squared unless `surface_gravity` is lowered. Scale `relief` with radius to keep a similar look.

| Option | Apparent size from Verdant |
| --- | --- |
| Keep 16 km at 12,000 km | 0.16° |
| 54 km at 12,000 km | 0.52° (real Moon) |
| 160 km at 12,000 km | ~1.6° (Earth–Moon radius ratio) |
| 200 km at 12,000 km | ~2° (KSP Mun) |

## Planet scale

Verdant stays at 600 km for now. At Earth size, the delta-v to reach orbit would rise from about 3.4 km/s to about 9.4 km/s. That would force very large multi-stage rockets with the current 190–255 s Isp engines, and terrain detail per kilometre would fall about 10×. A 2.5–3× rescale (about 1,500–1,800 km, about 5 km/s to orbit) is the largest change worth considering, and only after step 2.
