# Flight mathematics and orbital physics

The simulation, engineering estimates, and orbit map share constants and orbital calculations in `scripts/physics_math.gd`. The flight model remains deterministic and independent of rendering.

Flight presentation interpolates the two latest physics poses on each display frame. The planet, launch scenery, vessel, and detached stages share that interpolation; camera framing and atmosphere/cloud uniforms use the resulting displayed pose. Mouse orbit remains immediate. The actual physics pose is restored before the next simulation tick, so interpolation cannot feed back into cloth, staging, or flight calculations. This adds up to one physics tick of presentation delay while removing stepped horizon motion. Explicit syncs, pause, and workshop transitions reset the history; nonphysical time warp presents its current pose directly. `tests/test_flight_interpolation.gd` covers intermediate frames, camera/uniform agreement, restoration, and resets, with optional graphical captures when run without `--headless`.

## Coordinates and units

Distances are metres, time is seconds, mass is kilograms, force is newtons, and angles inside the simulation are radians. Speed is the magnitude of the velocity vector; it has no direction. Velocity, acceleration, and angular velocity are vectors.

The launch pad is world origin. Verdant's center is `(0, -600000, 0)`. Orbital calculations take planet-centered position `r = position - PLANET_CENTER` and inertial velocity `v`. Altitude is `|r| - R`, not distance from the launch pad. Verdant rotates about +Y every 21600 simulation seconds. This keeps equatorial air below orbital speed, so atmospheric drag cannot spin a descending craft into a new climb. Surface velocity is omega cross r; drag, ground speed and impact speed use velocity relative to that rotating surface, while orbital elements retain inertial velocity. The vehicle's local positive Y axis is its thrust direction.

Vertical velocity is the dot product `v · up`; horizontal velocity is the remainder `v - up (v · up)`. Prograde follows velocity, retrograde opposes it, and orbital normal follows `r × v`. The maneuver radial-out direction is `prograde × normal`, perpendicular to velocity within the orbital plane. It differs from surface-up during climbing or descending flight. A stationary or exactly radial trajectory has no defined orbital plane; telemetry reports that explicitly and returns zero for undefined direction vectors.

## Gravity and integration

Verdant has radius `R = 600000 m` (600 km), equatorial circumference approximately `3,769,911 m` (3,770 km), spherical surface area `4.524 × 10¹² m²`, mass `5.292 × 10²² kg`, surface gravity approximately `9.81 m/s²`, and gravitational parameter `μ = g_surface R²`. Gravity is `-μ r / |r|³`. Flight updates use substeps of at most 1/60 second, with symmetric gravity kicks around the position update (velocity Verlet in a gravity-only coast). Thrust and drag are frozen over each small substep; their integration is approximate. Detached stages use the same gravity integration scheme.

Surface contact sweeps against the same generated terrain triangles used by the renderer. Scalar double-precision radius calculations preserve millimetre-scale liftoff motion at the pad in Godot's float32 vector build. Ground clearance is separate from sea-level altitude. See TERRAIN.md.

Splashdowns float as rigid bodies: sampled hull volumes apply buoyancy and water drag at their own positions, so draft, heel and capsize follow from the vessel's mass distribution. See WATER.md.

## Atmospheric coasting

The controlled vessel resolves aerodynamic resistance along the hull and across it. Frontal resistance uses the existing effective drag area and total airspeed; broadside resistance uses the lateral airflow component and hull length. Broadside force therefore damps lateral motion without applying the entire exposed side area as an additional axial brake. The resulting force dissipates air-relative kinetic energy and can curve the flight path. It does not provide a wing or a sustained-glide model.

Crossflow exposure builds and fades with a 0.5-second response time, based on the angle between the hull and current air-relative movement. This is a gameplay approximation for a gradual aerodynamic response during turns. Only the resistance coefficient is relaxed: force direction follows current airflow, and inertial velocity is never interpolated or reset by steering. The substep uses mean exposure over its duration; vacuum clears the response. `tests/test_turn_drag.gd` checks momentum continuity, gradual buildup and decay, descent, and timestep consistency.

Each component uses an implicit drag update so strong drag approaches rest without reversing velocity in one step. Fuel exhaustion changes thrust and mass, but does not introduce an extra braking force. Parachute resistance remains isotropic, with only the canopy force contributing to parachute attachment torque. `tests/test_atmospheric_coast.gd` covers unpowered forward travel, descent, directional resistance, strong-drag stability, vacuum, and frame-rate consistency.

## Separated assemblies

Separation runs through the same code for legacy designs and editable staging plans. Each side booster becomes its own body; the core's connected engine, tanks, fins, and decoupler remain one released assembly. A detached body stores its own center position, velocity, orientation, world-space angular momentum, remaining fuel, and approximate cylinder dimensions.

At release, each body inherits the parent velocity plus `omega × offset` from the parent's rotation. Opposed booster springs give each booster 0.8 m/s outward motion. The capsule decoupler applies equal-and-opposite impulses for 0.8 m/s relative separation speed. These conserve linear momentum. The controlled capsule's contact-point position is rebased at separation so its visible position stays continuous. Rendered debris is offset around its own center, not the original rocket's origin.

Released bodies use spherical gravity and gravity-Verlet integration at the flight substep. Drag uses velocity relative to the rotating atmosphere, with end-on and broadside projected areas. Angular momentum is preserved in vacuum; approximate aerodynamic rotational damping acts in air. A released liquid engine retains its ignition state and throttle at separation and burns its remaining fuel. A powered stage that catches the capsule transfers force through body collisions. Ignited solid boosters continue burning; each accounts for half the pair's fuel and thrust. Escaping fuel carries its proportional share of spin momentum.

Terrain contact sweeps the oriented cylinder's lower support point. Detached assemblies break up only when the contact point closes into the surface faster than 20 m/s, measured relative to the moving surface and including spin. The controlled vessel and capsule also explode above 20 m/s of inward surface-relative speed at touchdown; the destroyed hull disappears, stops colliding, and cannot relaunch. Gentler detached-part impacts bounce with restitution 0.35 and friction, allowing longer hops in low gravity. Tangential motion slides or rolls. Unpowered debris below 0.4 m/s and 0.35 rad/s for two seconds of continuous contact retires without exploding. Destructive impacts emit a brief expanding explosion and leave physics and tracking immediately. This applies to local and background debris on planets and moons. Stable debris IDs preserve the remaining assemblies' visual ownership when one disappears. Touchdown records the result without pausing: released stages and world rotation continue until the player pauses or returns to the workshop. The flight report is available from the pause menu; its flight duration stays fixed at touchdown.

Separated assemblies collide with each other and with the controlled rocket. The active craft uses a compound of rounded-cylinder shapes for its core, capsule, and attached boosters; debris uses one shape per connected assembly. Contact impulses apply mass-dependent recoil and off-center torque to both bodies. Friction and restitution remove energy, and mass-weighted position correction resolves overlaps without injecting velocity.

When nearby bodies move quickly, the flight timestep shrinks so relative translation plus rotational tip travel is at most one quarter of the smallest collider radius. This prevents high-speed bodies from crossing through one another between contact checks, including during time acceleration. Co-moving bodies use relative speed, so orbital speed alone does not force tiny steps.

This is an approximate detached-body model: uniformly distributed cylinder mass/inertia and rounded-cylinder collision shapes rather than triangle-mesh contact. Windows, antennas, fins, and ring openings are not individually resolved. Structural breakup, detailed aerodynamic lift/center-of-pressure torque, and exhaust impingement are not simulated. The controlled rocket's existing simplified attitude controls remain active after collision recoil.

`tests/test_detached_physics.gd` checks independent booster release, mass/momentum transfer, continuity at release, spin, vacuum gravity, rotating-air drag, projected area, live fuel burn, swept impact destruction, one-shot explosion events, stable survivor identity, and background impact cleanup. `tests/test_body_collisions.gd` also checks impact momentum/energy, glancing spin, overlap correction, waking, high-speed debris/debris and debris/capsule impacts, and clean separation. The standard check script includes both.

## Orbits and the map

Specific angular momentum is `h = r × v`. Specific orbital energy is `ε = |v|²/2 - μ/|r|`. The eccentricity vector is `(v × h)/μ - r/|r|`; its magnitude is eccentricity `e`. The semimajor axis is `a = -μ/(2ε)` and the semilatus rectum is `p = |h|²/μ`.

Periapsis altitude is `p/(1+e) - R`. Bound trajectories have apoapsis altitude `a(1+e) - R` and orbital period `2π sqrt(a³/μ)`. Open trajectories have no finite apoapsis or period. Near-zero energy is treated as parabolic within a relative tolerance of 1e-6 to account for float32 input precision. Hyperbolic trajectories have negative semimajor axis. A stable orbit requires a bound trajectory with periapsis above the 90 km atmosphere.

The map samples the conic `r(ν) = p/(1+e cos ν)` in its actual orbital plane. This removes accumulated drift from the old independent Euler prediction. Radial and almost-radial suborbital paths use time integration because their angular range is too small for regular anomaly sampling. Prediction stops at the surface or map distance limit. The map displays eccentricity and period, or identifies an open trajectory.

Circular speed is `sqrt(μ/r)`; escape speed is `sqrt(2μ/r)`. These are exposed in telemetry alongside energy, angular momentum, eccentricity, semimajor axis, period, and maneuver directions.

## Propulsion

Specific impulse uses the fixed standard gravity `g₀ = 9.80665 m/s²`, independently of Verdant's gravity or altitude. Exhaust velocity is `Isp g₀`, propellant flow is `F/(Isp g₀)`, and ideal delta-v is `Isp g₀ ln(m_initial/m_final)`. Launch thrust-to-weight instead uses Verdant's surface gravity. Reported g-load uses standard gravity.

Combined core/booster estimates divide the burn at each fuel exhaustion event. The combined exhaust velocity is total thrust divided by total mass flow while both engines burn. If the core empties first, its dry mass remains attached for the remaining booster burn. If boosters empty first, the estimate assumes immediate booster separation followed by the remaining core burn. Booster-first estimates preserve core fuel until separation. These are ideal performance estimates; arbitrary user staging delays, early separation, gravity losses, and drag losses can reduce achieved delta-v.

## Mounted mass and balance

Separator–1 is 1.4 m tall and contributes 12 kg per physical mount. Each Booster–1 contributes 90 kg dry mass, 320 kg propellant and 22 kN thrust; legacy two-booster designs retain the former aggregate propulsion values. The workshop supports independent surface mounts and 1/2/4/6/8-way placement symmetry.

The flight model sums individual component masses at their attachment positions, recomputing the center of mass as propellant burns or stages detach. Component cylinder approximations and the parallel-axis theorem provide diagonal body-axis moments of inertia. This is an approximate inertia model: products of inertia are not included. Attitude controls apply fixed control torque divided by that inertia. Each engine contributes `(thrust_position - center_of_mass) × thrust` torque, so asymmetric placement can rotate the rocket. Uniform gravity accelerates the whole mass without an artificial off-center gravity torque.

Each booster separates from its rendered mount position and inherits rotation-induced velocity. Radial release impulses include recoil of the retained craft to conserve total linear momentum. All boosters share the existing ignition/separation stage group and burn at the same rate. Collision shapes and exhausts follow the individual mounts. `test_radial_mounts.gd` verifies mass, balance, torque, saves and separation across every symmetry count; `test_radial_builder.gd` verifies surface placement, previews, overlap rejection, removal and undo.

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


## Time warp

Period cycles high-speed warp through 1, 5, 10, 50, 100, 1,000, 10,000 and 100,000×. Alt+Period (Command+Period on macOS) selects physical warp at 1, 2, 3 or 4×. Period also selects physical warp when high-speed warp is unavailable. The HUD names the active mode. Physical warp retains the normal substepped forces, controls, fuel consumption and collisions; prefer 2× during demanding burns.

High-speed warp requires zero throttle and no burning attached boosters or detached engines. A stationary launchpad or settled surface craft can use every rate. Otherwise each planet/moon imposes a minimum altitude: max(atmosphere height, twice terrain relief + 100 m), plus its radius multiplied by 0, 0.1, 0.25, 0.5, 1, 2 or 5 for the seven accelerated rates. All bodies are checked in their moving frames. These thresholds scale with the game's bodies rather than using Kerbin's dimensions.

High-speed flight uses adaptive gravity integration with terrain and vessel collisions, zero angular velocity, frozen attitude, no thrust, no drag, and no fuel consumption. Moving landed craft remain on physical warp until settled. Surface-resting craft follow the body's rotating frame. Accelerated steps stop at altitude restrictions and the HUD immediately downshifts; the delayed downshift hazard in the reference is deliberately avoided. Solar and flight clocks advance by the actual elapsed simulation time, including interrupted frames. Parachute deployment physics freezes during high-speed warp. The current rigid assembly model has no flexible part joints or thermal destruction. Aerodynamic heating produces a visible fire shell and a flight warning.


## Atmospheric heating

Aerodynamic resistance uses velocity relative to the local rotating atmosphere and scales with density, exposed area, and inverse mass; the controlled vessel separates frontal and crossflow resistance as described above. Vessel temperature now integrates a gameplay heating rate of `110 * sqrt(density / 1.225) * (airspeed / 700)^3` K/s with exponential cooling toward 288 K at 0.10/s. This applies equally to ascent and descent, with zero heat input in vacuum. Temperature is capped at 4000 K; the surface glow fades in from 700 to 1400 K. Heat overlays follow each part mesh, with brighter windward faces and a thin conformal airflow sheath independent of engine thrust. The wake uses many individual streamlines traced outside a polar envelope sampled from visible hull mesh vertices. Paths slide around the capsule, tanks, and fins before peeling downstream. The compact wake uses 36 steps of 0.15–0.31 m, depending on airspeed, with a tapered fade. The sampled hull is uploaded as a small radius texture. A fixed set of 120 ribbon seeds persists through a full turn; the vertex shader traces their paths against that hull using the current airflow every frame. Exposure fades continuously on sheltered surfaces. Turning and speed changes do not rebuild meshes, wait for workers, or crossfade old shapes. Only changes to the visible parts rebuild the hull profile and seeds. Bright packets move along the paths at a compressed visual speed of `5 + airspeed * 0.055` metres per simulated second, so 1000 m/s is visibly faster than 100 m/s. Layered surface plasma shares the same advection rate. Both surface flame tips and the wake stream opposite the current velocity relative to the local atmosphere, refreshed after physics integration. Windward faces have denser moving flame tongues and wider, brighter roots where the air first hits; this concentration follows surface orientation continuously while the compact downstream trail keeps its length. Wake brightness scales with current heating and surface glow. Residual surface glow remains during cooling in vacuum, while the airflow sheath and wake fade with heat input. The HUD warns while hot. These are gameplay tuning values, not a material simulation; thermal part damage is not implemented.

The planet baker stores one shared mesh for the editor/map preview, moon rendering, near-surface flight (LOD 0), and collision triangles. Independent preview tessellation is not used for these surfaces: even the same elevation field at a different resolution can put visible triangle planes metres above or below contact. Bake version 6 rejects older resources with separate preview geometry; Bake & Save rebuilds them. Higher flight LODs remain distance-only simplifications.

### Reaction wheels

Gyro–1 rings contribute 12,000 N·m per local axis per attached wheel, added to
the existing control torque before division by the corresponding moment of
inertia. Each wheel contributes 50 kg at its actual stack position (0.948 m
radius, 0.2 m height). The control rate limit is 1 + 0.5 × wheel count rad/s;
existing SAS damping is unchanged. Wheels require a turn command, consume no
propellant, and stop supplying torque when detached. Capsule recovery uses its
original mass, inertia and control authority after shedding the wheel stack.
A decoupler mounted beneath a gyro instead releases only its lower descendants;
the retained gyro continues contributing mass, inertia and control torque.
