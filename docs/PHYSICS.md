# Flight mathematics and orbital physics

The simulation, engineering estimates, and orbit map share constants and orbital calculations in `scripts/physics_math.gd`. The flight model remains deterministic and independent of rendering.

## Coordinates and units

Distances are metres, time is seconds, mass is kilograms, force is newtons, and angles inside the simulation are radians. Speed is the magnitude of the velocity vector; it has no direction. Velocity, acceleration, and angular velocity are vectors.

The launch pad is world origin. Verdant's center is `(0, -60000, 0)`. Orbital calculations take planet-centered position `r = position - PLANET_CENTER` and inertial velocity `v`. Altitude is `|r| - R`, not distance from the launch pad. Verdant rotates about +Y every 1440 simulation seconds. Surface velocity is omega cross r; drag, ground speed and impact speed use velocity relative to that rotating surface, while orbital elements retain inertial velocity. The vehicle's local positive Y axis is its thrust direction.

Vertical velocity is the dot product `v · up`; horizontal velocity is the remainder `v - up (v · up)`. Prograde follows velocity, retrograde opposes it, and orbital normal follows `r × v`. The maneuver radial-out direction is `prograde × normal`, perpendicular to velocity within the orbital plane. It differs from surface-up during climbing or descending flight. A stationary or exactly radial trajectory has no defined orbital plane; telemetry reports that explicitly and returns zero for undefined direction vectors.

## Gravity and integration

Verdant has radius `R = 60000 m`, surface gravity `9.81 m/s²`, and gravitational parameter `μ = g_surface R²`. Gravity is `-μ r / |r|³`. Flight updates use substeps of at most 1/60 second, with symmetric gravity kicks around the position update (velocity Verlet in a gravity-only coast). Thrust and drag are frozen over each small substep; their integration is approximate. Detached stages use the same gravity integration scheme.

Surface contact sweeps against the same generated terrain triangles used by the renderer. Scalar double-precision radius calculations preserve millimetre-scale liftoff motion at the pad in Godot's float32 vector build. Ground clearance is separate from sea-level altitude. See TERRAIN.md.

## Orbits and the map

Specific angular momentum is `h = r × v`. Specific orbital energy is `ε = |v|²/2 - μ/|r|`. The eccentricity vector is `(v × h)/μ - r/|r|`; its magnitude is eccentricity `e`. The semimajor axis is `a = -μ/(2ε)` and the semilatus rectum is `p = |h|²/μ`.

Periapsis altitude is `p/(1+e) - R`. Bound trajectories have apoapsis altitude `a(1+e) - R` and orbital period `2π sqrt(a³/μ)`. Open trajectories have no finite apoapsis or period. Near-zero energy is treated as parabolic within a relative tolerance of 1e-6 to account for float32 input precision. Hyperbolic trajectories have negative semimajor axis. A stable orbit requires a bound trajectory with periapsis above the 18 km atmosphere.

The map samples the conic `r(ν) = p/(1+e cos ν)` in its actual orbital plane. This removes accumulated drift from the old independent Euler prediction. Radial and almost-radial suborbital paths use time integration because their angular range is too small for regular anomaly sampling. Prediction stops at the surface or map distance limit. The map displays eccentricity and period, or identifies an open trajectory.

Circular speed is `sqrt(μ/r)`; escape speed is `sqrt(2μ/r)`. These are exposed in telemetry alongside energy, angular momentum, eccentricity, semimajor axis, period, and maneuver directions.

## Propulsion

Specific impulse uses the fixed standard gravity `g₀ = 9.80665 m/s²`, independently of Verdant's gravity or altitude. Exhaust velocity is `Isp g₀`, propellant flow is `F/(Isp g₀)`, and ideal delta-v is `Isp g₀ ln(m_initial/m_final)`. Launch thrust-to-weight instead uses Verdant's surface gravity. Reported g-load uses standard gravity.

Combined core/booster estimates divide the burn at each fuel exhaustion event. The combined exhaust velocity is total thrust divided by total mass flow while both engines burn. If the core empties first, its dry mass remains attached for the remaining booster burn. If boosters empty first, the estimate assumes immediate booster separation followed by the remaining core burn. Booster-first estimates preserve core fuel until separation. These are ideal performance estimates; arbitrary user staging delays, early separation, gravity losses, and drag losses can reduce achieved delta-v.

## Scope and verification

This is a single spherical body's two-body gravity model. Multiple gravitational bodies, patched spheres of influence, atmospheric pressure-dependent engine performance, and full aerodynamic torque/lift simulation are not implemented. Rotation and terrain contact are implemented for the home world. Fins and stability assistance still use simplified angular damping; the atmosphere and parachute remain gameplay approximations.

`tests/test_flight.gd` checks analytic circular/elliptical orbits, escape and radial degeneracies, maneuver directions, map apsides, several orbits of energy/angular momentum conservation, independent numerical delta-v integration, and the launch/orbit/recovery loops. Run `./tools/check.sh` for all headless checks.

## References

The user supplied the [KSP terminology Mathematics section](https://wiki.kerbalspaceprogram.com/wiki/Terminology#Mathematics). Its anti-bot page denied automated access during this change, so its exact contents were not verified. The implementation uses standard mechanics checked against these accessible references:

- [NASA: Gravity and Mechanics](https://science.nasa.gov/learn/basics-of-space-flight/chapter3-1/)
- [NASA: Specific Impulse](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/specific-impulse/)
- [NASA: Ideal Rocket Equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/ideal-rocket-equation/)
- [JPL Horizons: orbital element definitions](https://ssd.jpl.nasa.gov/horizons/manual.html)
- [NIST: conventional standard gravity](https://www.nist.gov/system/files/documents/srd/jpcrd574.pdf)
