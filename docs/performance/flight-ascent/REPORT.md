# Flight ascent and cloud cost — October 10, 2026

All runs used Godot 4.5.1 double precision, Forward+, a Radeon RX 580 at 1280×720, vsync off, and isolated temporary user data holding a copy of the player's save.

## Summary

- **Staging freeze fixed.** Separating stages 2–4 froze the game for 1.1 s and 0.36 s. The cost was the aerothermal wake re-reading every remaining part's vertex arrays to rebuild its hull outline. `world.sync_flight` at separation dropped from 1,019 ms and 236 ms to 25 ms and 12 ms.
- **4× physics warp fixed.** Debris in the atmosphere cost 11 ms per tick at 4×. Godot then ran up to eight ticks per frame to catch up, which held frames at about 145 ms for 30 simulated seconds. Ticks now cost 2.7–6.8 ms, there is one tick per frame for the whole ascent, and median frames stay at or below 18.5 ms.
- **Corrections to the first version of this report:**
  - The game logic does not take 13–17 ms per frame. `Performance.TIME_PROCESS` is the *slowest* frame of the previous second, and it includes rendering submission and the wait for the GPU. Timed directly, the flight scripts take 2–3 ms per tick and `main._process` takes 0.3 ms.
  - The "escape" phase (frames of 83–370 ms, growing with distance) was not caused by distance. Time warp was switched on during that run; altitude rising from 5 to 375 Mm in five seconds shows it. The Godot window takes keyboard focus, and the period key cycles warp.
- Clouds are not the bottleneck. The reduced cloud pass costs 1.4–3 ms through the ascent.

## What was fixed

`tests/_probe/stage_ascent_profile.gd` flies the same ascent as `stage_ascent_perf.gd`. It drives main's physics and process callbacks itself and times each part separately: flight step, telemetry, world sync, UI and process. It blocks keyboard input so the run cannot be changed by stray keys. `PROBE_WARP=4` flies under physics warp, and `PROBE_SECONDS` limits the run.

### Staging freeze — `aerothermal_wake.gd`

Each separation changes the visible hull, so the wake resampled its outline from every remaining mesh with `surface_get_arrays()`. That meant 37 tank canisters at up to 1,600 vertices each, binned in GDScript. The wake now caches a reduced outline per mesh: the outermost vertex per height band and per direction. The canisters share one mesh, so a resample only transforms a few hundred cached points.

### Debris at 4× — `flight_model.gd`, `body_collisions.gd`

After the third separation, 16 spent pieces were integrated at every 1/60 s craft substep, which is four substeps per tick at 4×. Per substep this cost 1.4 ms of collision resolution, 0.75 ms of debris integration and 0.37 ms of `step_limit`.

- Collision resolution solved all 136 pairs four times. It now builds candidate pairs from bounding spheres once per substep, rejects individual shape pairs by their own bounds, and stops iterating after a pass that changes nothing. Previously the 0.0001 m slop of a resting contact counted as a change on every pass, so all four passes always ran.
- `step_limit` computes each body's spin and bounds once instead of once per pair.
- Debris integration checks that a piece's swept bounds cannot reach the terrain before computing support points and terrain queries. It also no longer copies each piece's state every substep.
- Debris more than 2 km from the craft goes to the one-step-per-tick background path unless it is near the ground. Before, any debris inside the atmosphere was kept on the full path, so the stages stayed expensive until they climbed above 100 km. Background steps are at most 1/15 s in the atmosphere (physics warp tops out at 4×, and rail warp is not available there), which keeps drag stable. Ground contact still uses craft-sized substeps. `test_distant_debris.gd` checks both cases.

## Staged ascent after the fixes

Per-second medians. "Physics" is the flight tick timed directly.

| Phase | Altitude | 4× frame | 4× physics | 1× frame | 1× physics |
|---|---|---|---|---|---|
| Pad, early climb | 0–7 km | 13 ms | 2.9 ms | 12–14 ms | 2.1 ms |
| Fast climb | 8–40 km | 16–18.5 ms | 2.8 ms | 16–19 ms | 2.2 ms |
| Stages 2–4 separate | 42–53 km | max 95 ms (one frame) | 2.5 ms | max 80 ms (one frame) | 3.4 ms |
| Debris within 2 km | 53–80 km | 14.7–17.6 ms | 5.4–6.8 ms | 12.7–14.7 ms | 3.0–3.5 ms |
| Upper stages | 80–510 km (1× run: 70–110 km) | 12–14.5 ms | 2.7–3.2 ms | 11.4–11.8 ms | 2.3–2.5 ms |

Before the fixes, the 4× run spent 25 s at about 145 ms per frame (eight ticks of 12 ms each), and the separations took 1,154 ms and 410 ms. The separation frame still costs about 40 ms of script time, 25 ms in `sync_flight` and 12 ms rebuilding the stage list UI.

## Still open

1. **GPU time during the fast climb.** This is investigated below in "GPU time from 6 to 40 km"; nothing has been changed yet.
2. **Rail warp with debris.** At high rail warp, every debris piece is stepped in lockstep with the craft at no more than 10 s per step. One 100,000× tick is about 167 steps across 16 pieces, roughly 38 ms, and that brings back the eight-ticks-per-frame spiral (300+ ms frames). Fixing it means letting distant debris take longer steps at high warp, which trades away some debris trajectory accuracy, so it has not been changed yet.
3. The original run ended without its closing log line. That did not happen in any later run.

The original 1× log is still in `ascent-log.txt`. Its CPU columns are per-second maxima of `TIME_PROCESS` and `TIME_PHYSICS_PROCESS`, as explained above.

## GPU time from 6 to 40 km

`tests/_probe/transparent_pass_ablate.gd` reads the renderer's per-pass GPU timestamps every frame. Run it with `--profile-gpu`; the help text names it `--gpu-profile`, which does nothing. It switches candidates off for 8 frames at a time, so each comparison happens at nearly the same altitude. Its modes are `PROBE_VARIANTS`, `PROBE_SHOTS` and `PROBE_DUMP`. The 1920×1008 window ran at 1×.

The whole rise is in the main view's **3D transparent pass**: 2.7 ms below 6 km, 12 ms at 9–24 km and 9.6 ms above 27 km. Depth prepass, shadows and sky stay flat, and the opaque pass grows by about 1 ms. The rest of a 23 ms frame at 15 km is the opaque pass (3.8 ms), HUD canvas items (2.5 ms at every altitude), the reduced-resolution cloud march in its own viewport (2.3 ms), shadows (1.8 ms) and the depth prepass (1.0 ms).

Main-view transparent pass at 9–24 km:

| Source | Cost | How it was measured |
|---|---|---|
| Aerothermal effect: hull overlay plus two halo shells on all 182 hull meshes | 3.5 ms, of which the shells are 2.3 ms | effect removed until the frame is drawn |
| Cloud composite (`clouds.gdshader`, full screen) | about 5.5 ms | planet node hidden; variants below |
| Exhaust plumes (32) | 0.4 ms | hidden |
| Wake, root glows, ocean, sun, orbit minimap | under 0.2 ms each | hidden |

The composite explains the altitude bands. Pixels whose ray misses the cloud shell are discarded at once:

- below the deck, only the sky above the horizon runs the composite;
- inside the shell (about 6–25 km), every pixel runs it;
- above the shell top, only the ground below the horizon runs it.

The cost-view screenshots show that almost every pixel takes the cheap upsampling branch. Only the rocket and its outline march at full resolution, and they take few samples because the ray stops at the hull 55 m away.

Composite variants, swapped every 8 frames within one run:

| Variant | Main transparent |
|---|---|
| Current | 9.5 ms |
| Without the 4-neighbour `lowres_safe` check | 6.9 ms |
| Without the full-resolution march code | 7.0 ms |
| Without both | 6.5 ms |
| Without the display-space blend | 9.35 ms |
| Neighbour check only where nearby geometry uses it | 9.35 ms |
| Neighbour silhouettes computed analytically (no neighbour rays) | 9.24 ms |

Removing either part saves about 2.5 ms, and removing both saves about 3 ms. Making the check cheaper barely helps. That pattern fits register pressure: one shader holds both the full raymarch and the neighbour checks, so fewer pixels shade in parallel across the whole screen, even though almost all of them only upsample. Both experimental shader changes were reverted.

Options, not yet decided:

- **Split the composite** so the full march runs only on pixels that need it. Godot 4.5 spatial shaders support stencil: one light pass marks the pixels that need a march, a second upsamples the rest, and a stencil-tested march pass covers only the marked pixels. Expected saving is up to about 3 ms inside the shell and less above it.
- **Thin the heating effect.** The two halo shells drawn over every part cost 2.3 ms. One shell, or shells drawn around a single hull proxy instead of 182 part meshes, would cut most of that. This changes how the effect looks.
- **HUD canvas items** cost 2.5 ms at every altitude, which is worth a separate look.

## Cloud cost by class

`tests/_probe/cloud_class_cost.gd` renders a hover view (61 km up, a storm anvil near the horizon) with each weather channel masked in the shader. Occupancy bounds stay as painted. Medians over 120 frames:

| Drawn | Reduced cloud pass | Frame GPU |
|---|---|---|
| All classes | 2.01 ms | 9.49 ms |
| Without storms | 1.69 ms | 9.52 ms |
| Without cumulus | 1.79 ms | 9.44 ms |
| Without stratocumulus | 1.90 ms | 9.46 ms |
| Without stratus | 1.92 ms | 9.50 ms |
| Storms only | 1.48 ms | 9.37 ms |
| None | 0.38 ms | 9.32 ms |

Storms cost the most (0.32 ms), mainly through steps in the clear air of their bounding region. Occupancy skipping was off for this map: its families cover the globe, so `cloud_layer.gd` compiles the bounds checks out. A coarse storm-occupancy grid would let the march skip that air.

The F9 "cloud samples" heatmap counts every march step, including empty ones that return after one weather lookup. With no clouds it still shows a red band at the limb: grazing rays cross about 200 km of storm space, roughly 120 growing steps at two taps each plus 96 low-deck steps. Read red as a long ray, not an expensive pixel.

## Limb staircase

At 37 km (`View: time 5625.0 pos -316840.4, -47452.8, 8325.6 yaw 0.699 pitch -0.532`) the deck's lit limb shows one-pixel steps. `tests/_probe/limb_stairs.gd` ruled out the reduced resolution, temporal reprojection, march step spacing, jitter and density saturation: none changed the edge. Two attempted fixes were reverted:

- averaging density over the pixel's vertical footprint: no visible change;
- averaging four sub-pixel rays where rays graze the deck: no visible change, +4.5 ms per frame.

The much coarser blocks seen earlier came from an outdated worktree (`../001-step2`, branch `step2-body-registry`, 11 commits behind `multi-planet`) that predates ee3d23c.

## Tooling

- `hover_preview.gd` shows a temporary `Clouds:` HUD line (view size, cloud scale, reduced-pass size, temporal history), marked `# TEMP`.
- Probes in `tests/_probe/` are untracked, like the existing ones there.
