# Navball guidance

The navball uses original, outlined vector glyphs drawn at UI resolution. A compact legend below the ball shows each icon with its meaning, and the same text is available on hover. Gold split diamonds indicate prograde and retrograde; lilac pennants indicate normal and anti-normal; cyan chevrons indicate radial out and radial in; coral brackets indicate target and anti-target; a white lightning glyph indicates a maneuver. Opposing velocity, normal and target glyphs have a central cross. Radial chevrons point outward or inward.

Directions are projected in the vessel frame: +Y is the nose, +X is screen-right, and -Z is screen-up. Front-facing directions move across the disc; rear-facing directions use smaller, dim rim symbols with outward ticks. Exactly aft uses the bottom rim because there is no unique turn direction. Undefined and non-finite directions are omitted.

Orbital markers use the flight model's active reference body's inertial orbital vectors, including its velocity and local orbital plane. Radial out is perpendicular to velocity in that plane, rather than necessarily straight away from the surface. The surface horizon uses telemetry's local surface-up vector.

The orbital map's single-node maneuver planner supplies `maneuver_direction`, a world-space burn vector evaluated in the orbital frame at the planned time. Valid guidance remains visible with the map closed. Thrust, a passed node, unsupported coast conditions, or node deletion remove guidance; cutting throttle recalculates the plan. Planning does not steer or fire the engine. See [map planning](ORBITAL_MAP.md#maneuver-planning).

Target selection is not implemented. The display accepts optional `target_position`, an absolute world-space position. Omit guidance fields when unavailable; zero-length vectors do not create a marker. Target and anti-target use the line of sight, not relative velocity.

Run `./tools/run.sh --headless --script res://tests/test_navball.gd` for projection, guidance availability, attitude rotation and all nine glyph drawing checks. This check is also included in `tools/check.sh`.

Behavior reference: https://wiki.kerbalspaceprogram.com/wiki/Navball (the site blocked direct access during implementation). Glyph artwork is original.

The flight HUD includes a spherical heading grid, numbered pitch marks every 10 degrees, intermediate 5-degree ticks, a curved horizon, and fixed green rim pointers. Sky/ground shading and grid markings rotate with vessel pitch and roll. Grid north projects world -Z onto the local tangent plane (with +Y as the polar fallback). The right rim needle indicates vertical speed, saturating at ±100 m/s; the numerical V/S readout remains unbounded.

Drag the left green throttle arc from its lower end (0%) to its upper end (100%). This replaces the separate bottom slider and uses the same throttle setter as Shift/Ctrl, X, and Z, including time-warp limits and warp-to cancellation.
