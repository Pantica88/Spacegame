# Dynamic terrain water

Near-surface water follows the supplied InfiniteOcean reference: two drifting
wave textures, two overlapping normal textures, depth-dependent blue/cyan
colour, sky reflections, and contact foam. The ocean is wrapped onto the
planet instead of using a flat tiled plane.

`OceanPatch` uses a single continuous ring mesh. The nearest 250 metres keep
their original grid spacing as the camera climbs; outer rings stretch gradually
to cover the horizon. This preserves the reference's dense-near/coarse-far
approach without tile seams. Clockwise triangle winding keeps the lit face
above the water.

Ripple displacement fades smoothly within 85 metres of the player. Smaller
waves disappear when the mesh cannot resolve them; normal-map details fade
independently according to their pixel footprint. Modest smooth swells remain
at larger scales, damped in shallows. OceanPatch's CPU height sample shares the
shader's swell amplitudes, regional strength and ripple fade, so floating
vessel presentation can follow the visible water.

At 18–25 km camera altitude, the patch fades into the planet terrain's water.
The terrain shader supplies ocean shading in planet previews and the orbital
map, including filtered noise-gradient waves and irregular shoreline foam.
Open-sea albedo is restrained rather than reduced to 30% of its base colour.

Shader material controls in `assets/shaders/terrain.gdshader`:

- `water_wave_strength`: 0–2, default 1; controls slopes, ripples, and foam.
- `water_wave_speed`: 0–3, default 1; controls animation speed; 0 freezes it.

The physical water surface remains calm mean sea level; the vessel's drawn
position additionally rides the visible swell. Wave animation uses the real
clock independently of time warp. This is not a fluid-flow simulation.

## Floating physics

A splashdown (touchdown where terrain water coverage exceeds 0.5) hands the
vessel to `scripts/hydrostatics.gd`, a rigid-body flotation model:

- The hull is the collision envelope sampled as volume slices along each
  part: the capsule's lathed outline, the core stack and attached boosters.
  Each slice has a centre sample and a ring at sqrt(2/3) r, which reproduces
  both its volume and its waterplane second moment (the metacentric term).
- Every submerged sample applies buoyancy (ρ = 1025 kg/m³) and water drag at
  its own position: quadratic drag on its end face or broadside, plus a
  radiation-damping term proportional to its displaced mass so small motions
  die out.
- Linear and angular motion integrate with the vessel's mass, centre of mass
  and inertia, so entry momentum carries the hull under, the draft settles
  where displaced mass equals vessel mass, and the mass distribution decides
  attitude. A tall stack capsizes and floats on its side. The default capsule
  (centre of mass 1.3 m above its base) rights itself from heels up to about
  25°; beyond that it settles on its side near 120° (Apollo's "Stable II").
- Motion accumulates as a small offset from the splashdown point to avoid
  planet-scale float32 quantization. After 2 s with speed below 0.05 m/s and
  rotation below 0.03 rad/s the vessel rests, which re-enables time warp.

Splashdown outcome rules are unchanged: water never destroys the vessel, and
the 8 m/s safe-landing speed still separates "landed" from "crashed".
Detached debris still treats the sea surface as ground.

Validation:

- `tests/test_ocean_mesh.gd`: every ocean triangle has the correct front face.
- `tests/test_water_landing.gd`: entry momentum and plunge, Archimedes draft,
  capsule upright / stack capsize, drift damping, rest, time warp and pause.
- `tests/capture_ocean_distance.gd`: graphical captures near sea level, at
  500 m, 6 km, 22 km (handoff), and 40 km. Requires display/GPU access;
  `OCEAN_CAPTURE_DIR` overrides `/tmp/aphelion-ocean-distance`.
- `docs/screenshots/water-comparison/infinite-ocean-update.png`: reference,
  previous game water, and updated water under matching lighting/cameras.
