# Timewarp stalls — October 10, 2026

Two CPU stepping bugs were reproduced and fixed without changing rendering settings or shaders.

## Warp-altitude boundaries

`FlightModel.step_rails()` divided clearance above the current warp boundary by total relative speed. Sideways orbital travel therefore forced approximately 0.001-second steps even when the craft maintained its altitude. The home world's higher warp boundaries include 390, 690, 1,290 and 3,090 km with the bundled settings.

A circular orbit 1 metre above the 1,000× boundary took 1,089.7 ms to advance only 10 simulated seconds before a diagnostic guard stopped it at 10,000 steps. After the fix, the entire requested 16.667 seconds takes 11 steps and approximately 1.5 ms. At 10,000× and 100,000×, the fixed cases complete in 61 and 221 steps respectively; the old cases also exhausted the diagnostic guard. These are individual headless CPU measurements, not whole-game FPS estimates.

The limiter now estimates approach using radial velocity and radial acceleration, including the tangential contribution that balances gravity in a circular orbit. Moon-relative acceleration accounts for the moving body's acceleration. Existing curvature limits and per-step warp eligibility checks remain active. The radial estimate is local to each integration interval, not an exact orbital event solver.

## Distant debris

`BodyCollisions.step_limit()` applied contact-sized steps whenever another body was within the distance reachable during the requested interval, even across kilometres of empty space. A stage 10 km away with 1,500 m/s relative velocity made a 1,000× tick take 2,261 ms before the same 10,000-step guard stopped it after only 1.567 simulated seconds.

The limiter now advances toward the enclosing collider bounds before using contact-sized steps. The reproduced tick completes all 16.667 simulated seconds in three steps, approximately 0.8 ms. Nearby collision tests still prevent tunnelling and verify momentum transfer.

## Rendering check and limits

A separate graphical hover-view sweep from 300 to 3,000 km ran twice at 1280×720 using Godot 4.5.1 double precision, Forward+, and a Radeon RX 580. It exposed rendering cost transitions, but no second-long stall: median frame intervals rose from approximately 5.3 to 7.8 ms across 480 km and from 4.7 to 8.2 ms entering the distant-cloud crossfade around 2,480 km. This sweep excludes flight physics and does not reproduce the user's exact trajectory or clear driver caches. Its rendering paths were not changed.

At 100,000×, even the corrected circular-orbit case still took approximately 27 ms of CPU time for a full tick. The fixes remove the reproduced pathological step counts; they do not establish that every high-warp frame meets a 60 FPS budget.

## Validation

`tests/test_rail_warp_boundaries.gd` is registered in `tools/check.sh`. It checks complete elapsed time and bounded step counts at all four higher boundaries, fuel preservation, inward and gravity-driven boundary stops, outward flight, and distant fast debris. Work-count assertions avoid machine-dependent timing thresholds.

The targeted suite passed: the new boundary regression, 27 body-collision checks, 43 detached-body checks, distant debris, timewarp UI/safety, moon flight, and water landing. The complete project check suite was not run.

## Follow-up: gameplay slowdown at 3,000,000 km

This is 3 billion metres, distinct from the cloud-resolution transition at approximately 3,000 km. The source-game reproduction uses the camera aimed at Verdant and an outward velocity of 3,000 m/s.

Two additional CPU costs were isolated:

- When the nearest reference body switched to Mun, `_refresh_telemetry()` built its collision mesh for the first ground query. An instrumented run measured 178.35 ms inside telemetry. Home and moon contact structures are now prepared under the existing launch cover.
- The unconditional ten-second ceiling required 167 integrations per 100,000× tick even millions of kilometres away. Debris-free flight now permits longer intervals bounded by every body's relative travel, gravitational timescale, and warp boundary. Debris retains the ten-second ceiling.

`tests/benchmark_distant_warp.gd` repeats the source-game camera comparison. Each sample runs one explicit 1/60-second physics tick, followed by rendering; these intervals are not native-scheduler FPS. Both runs used 1280×720, Forward+, the RX 580, and isolated temporary user data. Five warm frames precede 20 recorded frames per case.

| View, at 100,000× | Before median CPU | After median CPU | Before median frame | After median frame | Before maximum frame | After maximum frame |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Toward Verdant | 21.16 ms | 1.46 ms | 30.12 ms | 9.96 ms | 238.86 ms | 10.73 ms |
| Away | 20.39 ms | 1.50 ms | 28.21 ms | 10.05 ms | 30.20 ms | 14.35 ms |
| Toward Verdant, clouds hidden | 20.43 ms | 1.46 ms | 28.16 ms | 9.32 ms | 30.54 ms | 9.78 ms |

At 1×, the toward-Verdant median frame was 9.21 ms before and 9.40 ms after. The measured slowdown was primarily CPU work; hiding clouds did not remove it. The fixes do not change shaders or visual settings. Preparing collision meshes adds work to launch preparation instead of flight.

`test_distant_rail_warp.gd` checks inward, stationary, and outward coasts at 2.9, 3.0, and 3.1 million km. Each complete accelerated tick uses one integration and differs from a ten-second reference by less than 0.0007 m in position and 0.000000002 m/s in velocity. These short fixture comparisons are not a proof of long-term trajectory accuracy for every orbit.

The distant-coast regression, launch preparation (including actual moon readiness), existing timewarp, boundary regressions, moon flight, and distant-debris suites passed after these changes. An independent GPU diagnostic also found distant ray/sphere precision errors; those are separate from this confirmed gameplay slowdown and were not changed in this fix.
