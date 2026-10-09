# Flight trajectory planning

Updated: 2026-10-02. Scope corrected: calculating trajectories in the orbital map.

## Implemented first version

- Click the craft's coast to open a two-option popup: Create plan or Warp here. Creating a plan replaces the previous node at the selected predicted time.
- Drag six direction symbols to add or reduce prograde/retrograde, normal/anti-normal, and radial-out/radial-in delta-v. Shift gives fine adjustment; Escape restores a cancelled drag. Optional numeric fields allow precise signed values. The axes are evaluated at the predicted node time.
- Shift the burn time by ten seconds, or delete the node.
- Warp to a selected coast time under existing safety limits, clamp the final simulation step to the destination, and return to 1×. Allow cancellation and preserve the target through pause.
- Draw a separate purple post-burn trajectory; retain the current coast and recorded flight history.
- Display planned apoapsis/periapsis, delta-v, countdown, full-throttle burn duration, fuel requirement, and available delta-v from currently ignited liquid engines.
- Recalculate from the current flight state after coasting or staging. Suppress stale guidance under thrust, after passing the burn time, or when the reference body is unsupported.
- Supply the existing navball maneuver marker while the prediction is valid, including with the map closed.

The planner does not change the vessel, expend fuel, fire stages, or execute a burn. An impossible burn remains editable and is explicitly marked as lacking usable fuel or an ignited engine.

## Prediction contract

The first version supports elliptical and hyperbolic home-planet coasts, with a six-hour planning horizon. It solves Kepler's equation and applies an instantaneous delta-v at the node. Radial and near-parabolic degeneracies are unavailable rather than assigned an invented orbital plane.

The approach to the burn must remain above the home planet's atmosphere and conservative terrain envelope. Prediction stops at that envelope or where a sampled moon's acceleration exceeds one percent of the home planet's acceleration. These limits identify unsupported regions; they do not calculate encounters or atmospheric entry. Preview sampling is finite and is not a collision guarantee.

Burn-duration and fuel estimates account for depletion of independently fed liquid engines at full throttle. They assume no staging, no solid-booster contribution, and no gravity or drag loss during the burn. Finite manual burns can differ from the impulsive preview. The displayed suggested start time centers the estimated burn on the node.

Plans are session-only and reset on rollout/retry. Flight save/resume, autopilot, multiple nodes, target selection, moon-centered planning, and encounter/transfer prediction remain future work.

## Architecture and verification

- `scripts/maneuver_plan.gd`: render-independent propagation, time-of-flight conversion, node basis, and fuel estimates.
- `scripts/orbital_map.gd`: orbit popup, editor, domain limits, and distinct preview rendering.
- `scripts/maneuver_gizmo.gd`: six projected drag handles using the original navball symbols.
- `scripts/flight_model.gd`: authoritative usable engine/fuel telemetry.
- `scripts/main.gd`: telemetry, navball integration, and warp-to-time execution; flight controls are suppressed while typing or dragging burn values.

`tests/test_maneuver_plan.gd` checks analytic orbits, circularization, signed burn frames, fuel/depletion behavior, and agreement with numerical integration and flight simulation. `tests/test_maneuver_map.gd` checks placement, editing, rendering, invalidation, navball guidance, and retry. `tests/test_orbit_interaction.gd` checks the two-action popup, all six drag directions, fine adjustment, cancellation, and exact warp stopping. All run in `tools/check.sh`; graphical interaction tests capture `/tmp/aphelion-orbit-menu.png` and `/tmp/aphelion-maneuver-handles.png`.
