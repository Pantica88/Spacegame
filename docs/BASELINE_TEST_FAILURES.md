# Baseline check fixes

Review of the baseline-fixes WIP against `multi-planet`, 2026-10-09. Verification uses `tools/run.sh`'s default double-precision editor, without setting `GODOT_BIN`. `tools/check.sh` creates fresh XDG data, config and cache directories for every check; standalone diagnostic runs do the same.

Final validation: **83/83 checks passed**, including all 19 reported baseline failures, on `4.5.1.stable.double.custom_build.f62fdbde1`. The complete `tools/check.sh` run exited 0 with no script, parse or engine errors. The watchdog probes also passed. The protected roadmap “Step 1 progress” section, `deck_rise` test and planet asset contents were verified unchanged. The existing editor round-trip test rewrites then restores `ochre.tres`; its contents match the starting commit. All other planet files, including every bake, retain their original size and modification time, with no files added or removed.

## Production fixes

- `tools/check.sh`: a failed assertion can abort a SceneTree test before `quit()`. Create the log before launching the process, watch for `SCRIPT ERROR:` or `Parse Error:`, allow about two seconds for the backtrace, terminate the test process group and return failure. Keep the ordinary exit code and error-log checks. Manual runner probes verified assertion and parse-error hangs stop in about two seconds, exit 7 remains exit 7, successful tests pass, and consecutive checks have independent storage.
- `scripts/cap_tether.gd`: evaluate sleep eligibility at each fixed physics step. Sampling only the last step of a render frame missed motion spikes and changed the sleep time at different frame rates. The original `test_cap_tether.gd` is unchanged.
- `scripts/flight_model.gd`: add dry rolling resistance for a recoverable hull resting on its side, proportional to the normal contact impulse and hull radius. Exponential damping alone left a persistent downhill rolling speed. Contact resistance now permits static rest; settling thresholds and hillside time limits are unchanged.
- `scripts/world_view.gd`: locate installed tank fins with `RadialCraft.tank_center()`, matching placement previews and the craft graph. The old reversed tank-index calculation used a different tank position. The fin-vertex assertions are unchanged.
- `scripts/solar_body.gd`: correct a stale comment about the sun/planet radius ratio; no behavior change.

The WIP's additional scalar math, collision-query precision workarounds, launch-contact workaround and craft-focus rebasing were removed after switching verification to double precision. Their affected tests pass without those changes. `scripts/physics_math.gd`, `scripts/planet_terrain.gd` and `scripts/orbital_map.gd` now match `multi-planet`.

## Terrain diagnosis

The launch frame intentionally moved to +Z (`PlanetTerrain.LAUNCH_DIRECTION`), on the equator of the unchanged +Y spin axis. `test_equatorial_launch.gd` already checks this behavior. `Vector3.UP` is the north pole, not the pad.

On the double build, `Terrain.new(Definition.new())` reports north-pole elevation **−375.761379 m**, launch-direction elevation **0 m**, and launch-direction contact radius **600,000 m**. The old launch-complex and bake tests sampled the north pole. Correcting their sample frame fixes both failures while retaining their geometric tolerances. No terrain generation changes or bake-version bump are needed; `BAKE_VERSION` remains 9. Bundled planet definitions and bakes were neither rewritten nor deleted.

## Test edit audit

Each changed existing test is listed below. These fixture updates follow the intended 600 km planet, 90 km atmosphere, equatorial pad, craft graph and staged UI. No numerical tolerance was widened.

| Check / file under `tests/` | Root cause and retained coverage |
| --- | --- |
| `launch_complex` — `test_launch_complex.gd` | Sample mesh vertices and the 149 m grading grid in the actual launch frame. Keep all three seeds, the `launch_rings=false` case, exact deck vertex heights and the 0.065 m elevation tolerance. |
| `maneuver_math` — `test_maneuver_plan.gd` | A nominal vacuum flight at 40 km was inside the new 90 km atmosphere. Use 40 km above the atmosphere; retain the propagation, impulse and actual-flight comparisons. |
| `maneuver_map` — `test_maneuver_map.gd` | The fixed 100 km orbital radius was inside the 600 km planet. Use planet radius + atmosphere height + 10 km, with the existing circular-speed calculation and maneuver assertions. |
| `orbit_interaction` — `test_orbit_interaction.gd` | The same underground orbit produced an empty selection dictionary. Correct the orbit radius; retain all selection/edit behavior checks. |
| `orbit_mouse` — `test_orbit_mouse.gd` | The same underground orbit had no visible coast point. Correct the orbit radius; retain real mouse interaction checks. |
| `orbital_map` — `test_orbital_map.gd` | Replace the old 90 km radius/620 m/s orbit and fixed escape speed with a circular orbit above the atmosphere and 1.2 times escape speed. Project logical map positions through the existing `_project_map_position()` helper, which accounts for focused-body rebasing. Keep the 2-pixel focus, trajectory, occlusion and selection assertions. |
| `sun` — `test_sun.gd` | The sun is now 1.5 planet radii, not 15. The camera far plane also includes distant moons, so check the sun's own bounded visual distance instead of requiring the entire scene's far plane below 1,000 km. Give the map its normal full-rect layout. Restore the original 1,000 m/s impact, quarter-segment fraction, 2 m surface tolerance and 0.01 map alignment tolerance; add actual terrain occlusion coverage. |
| `flight` — `test_flight.gd` | Account for the equatorial launch basis, rotating-ground velocity and actual terrain clearance in launch/recovery fixtures. A destructive crash has no surviving vessel to carry with the ground; verify destruction, frozen report time and disabled engine, while `vessel_settling` retains intact-vessel ground-following checks. Clear inherited launch velocity for the pure gravity case. Move vacuum/conic fixtures above the atmosphere and scale map bounds and plane-change impulse to the current world. See the ascent details below. |
| `distant_debris` — `test_distant_debris.gd` | Background integration and tiny-stage culling intentionally exclude atmospheric flight. Put vacuum physics and high-altitude rendering fixtures 30 km above the atmosphere, retaining the explicit low-altitude, approach and powered-stage exceptions. |
| `detached_physics` — `test_detached_physics.gd` | The vacuum fixture at 30 km experienced atmospheric angular drag. Put it 30 km above the atmosphere; retain all momentum tolerances and separate atmospheric drag cases. |
| `body_collisions` — `test_body_collisions.gd` | Aim the fast debris at the capsule's actual oriented collision center. Align the powered-core comparison with its chosen north-pole fixture and disable the reference core's per-engine thrust entries as well as aggregate thrust. Otherwise both cores were powered. Preserve the contact/recoil assertions. |
| `game_loop` — `test_gameplay.gd` | Place the retry's 100 m / 100 m/s crash above the actual pad. The old north-pole position was already beneath mountainous terrain. Contract/reward and crash/retry assertions remain intact. The initial altitude contract already passes on double precision without the WIP launch workaround. |
| `vessel_settling` — `test_vessel_settling.gd` | Place flat-pad landing fixtures in the equatorial frame with velocity relative to rotating ground. Compare attitudes and support against the local terrain normal and planet center. Preserve settling deadlines, tilt, persistent rest, relaunch and breakup checks. |
| `hillside_recovery` — `benchmark_hillside_recovery.gd` | The rolling failure needs the production contact fix. Also select live cloth (`fade_after_landing=false`) for this cloth-sleep/draping benchmark, as the drape and cutaway tests already do. Normal gameplay now uses a baked collapse and fade. Keep all three hillsides, sleep, terrain penetration and zero-work-at-rest assertions. |
| `builder` — `test_builder.gd` | The fin-preview mismatch needs the production placement fix. Update the separate HUD assertion for the intended numbered stage button and `ignite:engine` indicator; keep all installed/preview vertex comparisons. |
| `rollout` — `test_rollout.gd` | Detached-only stages are intentionally skipped. Verify the skip leaves both controlled and discarded engines unlit. Add a combined detach-and-ignite case that must still return “blocked”, retain the stage index and perform no partial actions. |
| `planet_bake` — `test_planet_bake.gd` | Query the actual launch direction using the saved definition's radius. Restore the original visible-triangle clearance and swept-contact assertions, including rotation and their 0.03 m tolerance. The test only bakes its temporary fixture in isolated `user://` storage. |
| `terrain_landings` — `test_terrain_landings.gd` | The old 60,200 m highland filter admitted sea-level terrain on a 600 km planet. Select samples above radius + 200 m and outside the current launch cap. Restore the original contact-radius and recovery-plane comparisons; retain eight distinct highlands, sixteen rotated landings and fast-impact checks. |

`tests/flight_fixture.gd` is a new shared helper for actual-pad position, orientation and ground-relative velocity. The WIP's `tests/terrain_fixture.gd` was removed when the original geometric assertions were restored. `tests/test_planet_surface.gd`, including the intentional `deck_rise` change, is untouched.

The `flight` ascent fixtures needed two intended-world updates:

- The starter still must exceed **12 km**, within the same complete 121-second burn/coast simulation. Check this milestone after that simulation instead of at 51 seconds; the current world reaches 11,544 m at 51 seconds. Burn-rate, liftoff, burnout and mass assertions remain unchanged.
- The previous starter-rocket orbit profile cut off at **45 km apoapsis**, then waited to pass the **90 km** atmosphere. Use an orbital craft (eight tanks, Kestrel, paired boosters), an equatorial gravity turn and a **130 km** apoapsis target. It still uses player throttle/attitude/staging controls and must reach a stable orbit, retain **over 200 kg fuel**, and remain stable after engine cutoff. README's flight instructions match the tested profile.
