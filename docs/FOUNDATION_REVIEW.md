# Foundation review

Every foundational technical decision, checked against the long-term game vision (see [the roadmap's vision section](MULTI_PLANET_ROADMAP.md#how-the-game-vision-shapes-this-plan)). Each entry records what the project does today, why, whether that fits the vision, and when to revisit it.

First written **2026-10-09**, after finding that the project ran on single-precision coordinates without anyone having decided that. The purpose of this document is that no foundational choice stays implicit. Re-read it at the start of each roadmap step, and update an entry whenever its decision changes.

Status key: **OK** fits the vision · **Conditional** fits if the noted condition holds · **Gap** needs work before the vision can be built · **Undecided** no recorded reason; needs a deliberate decision

## Summary

| # | Decision | Status | Act when |
|---|---|---|---|
| 1 | Engine: Godot 4.5.1, custom double-precision build | OK | Upgrade to 4.8.x when stable, between roadmap steps |
| 2 | Coordinate precision: double | OK | — |
| 3 | Renderer: moving from Compatibility to Forward+ | **Decided, in progress** | Branch `renderer-forward-plus` |
| 4 | Simulation in GDScript, custom flight model | Conditional | Requires step 6 (on-rails, level of detail) |
| 5 | No Godot physics engine; all collision custom | OK | Note for docking and combat |
| 6 | Solar system: fixed sun, no heliocentric orbits (sun size decided) | **Gap** | Fold into step 3 |
| 7 | Planet scale: Verdant 600 km | OK | — |
| 8 | Time: one float (64-bit) simulation clock | OK | Make it universal in step 6 |
| 9 | Saves: versioned, but a version change discards the save | **Gap** | Before any persistent world (step 6) |
| 10 | Part definitions hardcoded in `scripts/parts.gd` | **Gap** | Before campaign and technology content |
| 11 | Large coordinator scripts (`main.gd`, `world_view.gd`) | Conditional | Split during steps 2–3, not later |
| 12 | Tests, perf lab and git practice | OK | Tag releases from now on |
| 13 | Engine bug: preload order breaks planet resources | Worked around | Fixed by the 4.8 upgrade |
| 14 | Hidden single-planet values found in step 2 | Gap | Step 3 |
| 15 | Engine bug: negated camera position in double-precision Forward+ shaders | Worked around | Fixed by the 4.8 upgrade (verify) |

## 1. Engine and version

**Today:** Godot 4.5.1, built from source with `precision=double` and one local patch (`~/godot-double/patches/`). Latest stable on 2026-10-09 is 4.7.2; 4.8 is in feature freeze (dev 7, 29 Sept 2026).

**Fits the vision:** yes. 4.6 and 4.7 improve Jolt physics, Forward+/Mobile rendering, animation and the editor, none of which the game uses ([4.6](https://godotengine.org/releases/4.6/), [4.7](https://godotengine.org/releases/4.7/)). The local `SurfaceTool` patch is still needed on 4.7.2.

**Decision:** stay on 4.5.1; upgrade once to 4.8.x (ideally 4.8.1) after it is stable. The upgrade also fixes the preload-order engine bug in entry 13. Upgrade between roadmap steps, never during a refactor, so engine changes and code changes are never mixed. An upgrade means: rebuild editor and templates, re-apply patches, re-bake every planet (the version is in the bake signature), run the test suite and perf lab, and check custom shaders visually.

`project.godot` still lists the feature tag `"4.4"` because no 4.5 editor has re-saved it. That is harmless; it updates on the next editor save.

## 2. Coordinate precision

**Today:** double precision everywhere (step 1, done). Verified: 1 mm stays representable at 600 km, and 1 cm at 1 AU. Cost measured: about 3.5% frame time, no GPU cost.

**Fits the vision:** required by it. Interplanetary distances, stations and docking all need it.

## 3. Renderer

**Today:** `gl_compatibility` (OpenGL 3.3) for desktop and mobile. No document records why. The custom atmosphere, clouds, water and terrain shaders are written for it ([ATMOSPHERE.md](ATMOSPHERE.md) calls the atmosphere "a visual approximation for the Compatibility renderer").

**Why it matters:** this is the most expensive decision to reverse. Every custom shader and every performance number depends on it.

- Compatibility has no compute shaders and fewer built-in effects. Godot's rendering investment goes mainly into Forward+ and Mobile; the 4.7 release notes say the Vulkan Mobile renderer now matches or beats Compatibility in some benchmarks.
- Compatibility runs on the widest range of hardware, including old integrated GPUs. If broad low-end support is the goal, that is a valid reason to keep it.
- The development GPU (RX 580) and Steam Deck both support Vulkan.

**How it was chosen:** an earlier agent picked Compatibility without asking; there was no requirement behind it.

**Decision (2026-10-09): move to Forward+.** Reasons: the game is a desktop Steam game, where Vulkan or Direct3D 12 GPUs are nearly universal (the RX 580 and Steam Deck support them); the vision's stations, fleets, weapons and explosions need many dynamic lights, which Forward+'s clustered lighting handles and Compatibility limits per object; compute shaders, temporal anti-aliasing and FSR2 upscaling become available; and Godot's rendering development concentrates there. The owner accepts the cost of porting custom shaders.

**Stop condition:** keep Compatibility only if Forward+ has a blocker with no clear fix, or 1080p frame times on the RX 580 are clearly worse than Compatibility after reasonable tuning. Record the result here either way.

**1080p result before tuning (2026-10-09, RX 580, fullscreen, standard preset):** Forward+ costs about 12% more GPU time in every scenario. Orbit (16.8 ms) and re-entry (18.6 ms) exceed the 16.7 ms budget; Compatibility measured 15.0 and 16.1 ms. The owner chose to keep Forward+ and tune.

**Known porting work:** `ocean.gdshader` converts depth with the OpenGL convention (`raw * 2.0 - 1.0`, `linear_depth`); `clouds.gdshader` already branches on `CURRENT_RENDERER` and shows the pattern. Forward+ renders in linear HDR where Compatibility does not, so atmosphere, sky, sun and glow colours will need re-tuning by eye. `tools/perf_lab.py` hardcodes `gl_compatibility` and needs a renderer option.

## 4. Simulation language and architecture

**Today:** all simulation is GDScript. The flight model (`scripts/flight_model.gd`, `RefCounted`) and craft model are separate from scene nodes and rendering, which is the right structure. Measured physics cost for one craft: 0.3–2.8 ms per frame (highest with parachute cloth).

**Fits the vision:** only with step 6. Dozens of vessels on full physics would not fit in a frame budget. The vision already calls for detailed simulation near the player and strategic simulation elsewhere.

**Decision:** keep GDScript. Keep simulation code free of scene nodes so it stays testable, and so a hot loop can move to a C++ GDExtension later if profiling shows it is needed. Do not port speculatively.

## 5. Physics engine

**Today:** no Godot physics (no rigid bodies, areas or physics server). Flight, terrain contact, parachutes and body collisions are custom and deterministic at 60 Hz. `TriangleMesh` is used only as a geometry query.

**Fits the vision:** yes; deterministic custom physics suits orbital mechanics and testing. Note that docking contacts, vessel-to-vessel collision and combat hits will all be custom work too.

## 6. Solar-system model

**Today:** the sun is fixed at 13,599,840,256 m from Verdant (`SolarBody.DISTANCE`, the same as KSP's Kerbin orbit). Verdant does not orbit the sun in the simulation. Planet orbits around the sun exist only in the orbital map, which positions them from `orbit_distance_au` with "illustrative phases". The Mun's orbit is real (`SolarBody.moon_offset`).

**Fits the vision:** no. Flying to another planet needs every planet on a real orbit around the sun, a heliocentric frame between spheres of influence, and transfer windows that come from real orbital positions.

**Sun size decided (2026-10-09):** physical radius 63,000 km, so the sun spans about 0.53° from Verdant like our Sun from Earth. The owner tried it in the hover preview and approved it. The visible sun keeps the physical sun's true angular size, so before this change the disk was about 0.2 px and only the sky shader's glow was visible; now a disk about 13 px wide shows inside the glow. Previously the physical radius was 900 km (`SolarBody.RADIUS`), 1.5 times Verdant's. From Verdant that is about 0.008° across, against 0.53° for the real Sun; the game draws a separately scaled visual sun. The simulation does not yet define a mass for the sun; heliocentric orbits will need one, so decide the sun's radius and mass together with the system scale.

**Proposed for step 3 (confirm then):** keep the current sun distance (13,599,840,256 m) as the system's 1 AU, and choose the sun's mass so Verdant's year equals its `orbit_period_days`.

**Decision:** extend step 3 to include heliocentric orbits for all planets (Keplerian rails around the sun), with Verdant moving too. Also fix the system scale: what an AU is in metres, and whether `orbit_distance_au` becomes a real semi-major axis.

## 7. Planet scale

**Today:** Verdant has a 600 km radius and 9.81 m/s² surface gravity (about 1/10.6 of Earth's radius, like KSP's Kerbin). Low orbit needs about 3.4 km/s of delta-v.

**Fits the vision:** yes. Earth scale would need about 9.4 km/s to orbit and much larger rockets. Recorded in the roadmap's "Planet scale" section; a 2.5–3× rescale is the largest change worth considering, and only after step 2.

## 8. Time

**Today:** simulation time is a GDScript `float` (64-bit), in seconds, with physics at a fixed 60 Hz. 64-bit seconds stay precise to well under a millisecond for thousands of years of game time.

**Fits the vision:** yes. In step 6, make one universal clock the only source of time for every body, vessel and colony, so on-rails propagation and time warp agree everywhere.

## 9. Save system

**Today:** `scripts/profile.gd` saves JSON with a `version` field and writes through a temporary file (safe against crashes mid-write). When the stored version differs from `SAVE_VERSION`, it reports "Saved profile version is unsupported. Starting with a fresh design." and discards the save. In-flight state is not saved.

**Fits the vision:** not yet. With persistent satellites, stations and colonies, any save-format change would wipe a player's world.

**Decision:** before step 6, add migrations: each version bump ships a function that upgrades the previous format, with a test that loads a saved file from each older version. Keep the safe-write behaviour.

## 10. Content definitions

**Today:** planets are data-driven `.tres` resources edited in the planet editor, which is the right model. Parts are not: engines, boosters and tanks are dictionaries in `scripts/parts.gd` (three engines today).

**Fits the vision:** no. It calls for many parts, station modules, planetary structures, technologies, resources and factions, defined as data.

**Decision:** before campaign and technology work, move part definitions to resource files the way planets work, so content can grow without code changes.

## 11. Code structure

**Today:** `main.gd` (2,341 lines, 113 functions) and `world_view.gd` (2,239 lines, 93 functions) coordinate most of the game and both assume one home planet. The simulation layer (`flight_model.gd`, `craft_model.gd`) is already separate.

**Fits the vision:** only if new systems don't keep landing in these two files.

**Decision:** split them along the lines steps 2–3 already require (body lookup, per-vessel frames, camera-relative rendering) while that code is being rewritten anyway. New systems (stations, colonies, factions) get their own modules.

## 12. Testing, tooling and history

**Today:** 83 checks in `tools/check.sh` with isolated saves, a repeatable perf lab with saved baselines, and a separate double-precision engine build with scripts. Git history starts on 2026-10-09; versions 0.1–0.3.26 exist only as old exports, which have been deleted except 0.3.26.

**Decision:** tag each release (`git tag v0.3.27`) so any version can be rebuilt from source. Consider CI later.

## 13. Planet resources and script loading

**The bug:** if a script preloads a planet `.tres`, and a script that preloads it then preloads `scripts/planet_definition.gd`, the preloaded planet resource loses its script variables (`radius` and the rest disappear) while the script object itself stays intact. Investigated 2026-10-09:

- It happens for every planet file (Verdant, the Mun, Ochre), and only when the `.tres` is preloaded inside another script; preloading any other script afterwards is harmless.
- It reproduces in a minimal clean project with a two-line custom resource, on both our double build and the official 4.5.1 download. It is a **Godot engine bug**, not project code, and the missing script `uid` in planet files is unrelated (it reproduces with and without one).
- Likely upstream issue: [godot#87019](https://github.com/godotengine/godot/issues/87019) ("Error accessing custom resource caused by order of preload", targeted for 4.6); related: [#98551](https://github.com/godotengine/godot/issues/98551), [#110394](https://github.com/godotengine/godot/issues/110394).
- **Fixed in official Godot 4.7.2**: the same minimal project passes there.

**Decision:** until the 4.8 upgrade, no script preloads a planet `.tres`. `BodyRegistry` and `PlanetSurface.HOME` load at runtime instead (`HOME` became a static property using `load()`). The upgrade removes the underlying bug; this is one concrete reason for it (entry 1).

## 14. Hidden single-planet values found in step 2

- `MIN_RAIL_WARP_ALTITUDE = 90000` (`flight_model.gd`) is the home atmosphere height, applied as a time-warp floor to every body, the Mun included. Replace with per-body logic in step 3.
- Moon orbital periods (`orbit_period_days`) are stored data, not derived from the parent's gravitational parameter and the orbit distance, so changing either leaves a physically wrong period unless the editor recomputes it. Derive them in step 3.
- `world_view.gd`'s `SOLAR_DAY_SECONDS = 480` and `_solar_time` are written but never read. Remove when that file is split.

## 15. Camera position in double-precision Forward+ shaders

**The bug:** in Godot 4.5.1 built with `precision=double`, the RD renderers overwrite the translation of `INV_VIEW_MATRIX` with the *negated* camera origin (`render_scene_data_rd.cpp`, `split_double(-cam_transform.origin.x, &ubo.inv_view_matrix[12], ...)`) for their internal double emulation. Custom shaders reading `INV_VIEW_MATRIX[3]` or `CAMERA_POSITION_WORLD` get a wrong camera position. Godot 4.7.2 stores the precision part separately, which suggests it is fixed upstream (verify on upgrade).

**Effect found:** below about 30 m the ocean's mirrored sky and clouds turned white with black holes (view rays pointed the wrong way).

**Decision:** custom shaders must not use `INV_VIEW_MATRIX[3]` or `CAMERA_POSITION_WORLD`; use the script-set `camera_planet_km` or view-space `VERTEX`. The ocean was the only user (fixed 2026-10-09).

## Decisions to make before step 2

1. **Renderer** (entry 3): run the renderer experiment and record the choice.
2. **Solar system** (entry 6): confirm that step 3 includes heliocentric orbits, and decide the system scale.
3. **Mun size** (roadmap open decision): the campaign opening favours a clearly visible Mun.

Entries 9 and 10 are not urgent for step 2, but they must be done before step 6 and before campaign content respectively.
