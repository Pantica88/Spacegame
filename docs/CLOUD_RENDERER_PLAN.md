# Cloud renderer replacement

Reviewed October 13, 2026 against the working tree, including the existing
storm-motion fixes and stencil compositor. This is a staged renderer change;
the weather editor and saved planet data remain the content interface.

## Findings from the second code review

- `clouds_volume.gdshaderinc` already integrates light, transmittance and a
  contribution-weighted distance. Its `vec4` interface combines the result
  with atmospheric haze, then loses the distance. `clouds_resolve.gdshader`
  reconstructs history using a low-deck sphere and a storm-sphere fallback.
  Neither represents the actual samples along a pixel's ray.
- Atmospheric storm views currently bypass temporal reconstruction. The
  reduced target renders all pixels instead of one quarter each frame. This
  is a documented correctness workaround, not a measured-depth solution.
  See [storm motion](performance/storm-base-motion/REPORT.md).
- The reduced march ignores scene depth. The main composite repairs opaque
  intersections and silhouettes by marching affected pixels again. The
  [stencil split](performance/cloud-composite-split.md) reduces that cost,
  but does not remove the duplicate integration.
- Authored weather permits 320 iterations, with a separate low-deck step
  budget and two density taps per storm interval. Occupancy uses two broad
  family boxes; empty gaps inside them still consume traversal work. These
  are separate issues from temporal reconstruction.
- Cloud light uses the artistic color convention described in
  `renderer_color.gdshaderinc`. An unencoded float value from this integrator
  must not be mislabeled as physical scene-linear radiance. Removing gamma
  encoding alone would not establish a correct HDR pipeline.
- Ocean reflections include the volume's density and shadow helpers. Vessel
  sunlight and cloud glow mirror density on the CPU. Flight, hover and editor
  cameras also share this renderer, including floating-origin coordinates,
  offset editor cameras and wind rotation.
- The older distance/horizon tests replace strings in `clouds.gdshader` that
  moved into the volume include. Those fixture substitutions can be no-ops.
  They are not evidence for the new depth contract. New synthetic tests must
  assert their substitutions, and comparisons must freeze shared includes
  and account for the reduced pass.

## Design boundaries

Keep weather RGBA formation weights, save formats, painting, world rotation,
wind, and the current density/lighting functions during the foundation work.
GPU distances are kilometres along normalized camera rays in planet space;
CPU camera differences stay double precision. The shader's inverse-view
translation is not the source of planet-relative position.

Treat volume integration, atmospheric composition, buffer encoding, and
temporal reconstruction as separate interfaces. The initial result carries
premultiplied light in the existing working space and transmittance, plus
optional measured depth statistics. Atmosphere is applied by the legacy
presentation wrapper, preserving the existing look.

Measured cloud depth is a distribution of extinction contributions, not an
opaque surface. Depth must remain valid for dark clouds and for a sample at
zero distance. Several translucent banks cannot always share one reliable
reprojection point; retain support and spread, and render fresh samples when
history is unreliable.

## Step 1 — Integration contract and reference checks

**Scope:** implement the foundation without selecting a new runtime renderer.

1. Add a small shader include defining an explicit `CloudIntegral` result.
   Preserve light, remaining transmittance, the existing weighted-distance
   sum, density-sample count, and whether the ray reached traversal.
2. Expose `integrate_cloud_volume()` before haze or presentation encoding.
   Retain `integrate_clouds()` as the existing color/opacity interface.
3. Under `CLOUD_MEASURE_DEPTH`, collect positive extinction-contribution
   weight, first/last contributing sample distances, weighted mean and
   variance. Use weighted Welford accumulation relative to the first sample
   to avoid subtracting nearly equal squared orbital distances. Legacy
   shaders do not enable this extra work.
4. Test the shared accumulation on the GPU against independent analytic
   answers. Test actual volume traversal with asserted deterministic density
   fixtures, including misses, empty traversals, clipping and opacity exit.
5. Compare the refactored renderer to a frozen pre-change reference; exercise
   composite, storm-motion, reflection/foreground integration and headless
   lifecycle checks. Record actual results below.

**Exit:** valid finite measurements, unchanged legacy output within declared
readback tolerance, and no changes to production temporal policy, density,
sample positions, save data or color conventions. A zero contribution has
light zero, transmittance one and invalid depth. A traversed empty ray remains
distinct from an early-cull ray for the F9 cost view.

The two storm density taps retain their existing representative interval
midpoint. Depth describes the current numerical integration; changing that
quadrature is separate work. The existing weighted-distance sum remains the
input to legacy haze so introducing stable moments does not shift its math.

## Step 2 — Opt-in buffers and opaque-depth integration

Prototype a separate Forward+ rendering path with explicit GPU targets and
scene-depth input. Godot 4.5 `CompositorEffect` supplies callbacks and resolved
scene buffers; evaluate it before replacing SubViewports. Its API is
experimental, so keep backend plumbing separate from the integration model.
See [Godot's compositor API](https://docs.godotengine.org/en/4.5/classes/class_compositoreffect.html).

Start with fresh reduced-resolution frames and floating-point light,
transmittance and depth data. Use 32-bit float depth data initially; kilometre
distances and squared spread do not belong in the current RGBA8 texture or
unscaled half-float channels. Define attachment layout, validity and format
support explicitly. Establish and test conversion from legacy working color
to scene-linear composition before claiming an HDR radiance pipeline.

Clip rays to opaque scene geometry before integration, then reconstruct
around depth discontinuities with selective fresh work. Validate foreground
rockets, terrain, MSAA edges and near/far depth precision. Preserve ordering
with the transparent sun, ocean, exhaust and heat: a generic compositor
callback does not automatically reproduce the current render priorities.
Test resize, resource cleanup, multiple viewports, hidden/map modes and
unsupported-backend fallback. No automatic production switch in this step.

## Step 3 — Reconstruction using measured depth

Reproject from measured cloud contribution distances with previous/current
camera transforms, projection and weather motion. Reject history at
disocclusions, incompatible depth/spread, weather edits, body changes,
teleports, lens changes and target resizes. Handle wind separately from
shape evolution; opaque motion vectors do not describe cloud motion.

Use front/support and spread to identify ambiguous multilayer pixels. Refresh
those pixels instead of forcing a single-depth match. Compare every temporal
phase against fresh reference frames during movement. Remove the storm
bypass only after these checks pass below, inside and above the clouds.

## Step 4 — Traversal and distance detail

Measure isolated march, reconstruction and composite costs on the RX 580
with identical weather and views. Add conservative hierarchical occupancy
for empty gaps; verify it never removes nonzero density. Filter density by
pixel footprint and vary sampling/detail continuously from flight to orbit.
Keep distant coverage tied to the same authored weather. Test bank outlines,
planet limbs and altitude transitions while moving, not just settled images.

Select budgets from measured quality/cost tradeoffs. No promised frame-time
target or speedup follows from choosing compute shaders alone.

## Step 5 — Lighting, rollout and retirement

Improve sunlight attenuation and cloud shape only after depth, composition
and reconstruction have reliable references. Evaluate cached light sampling
and optional local 3D storm assets separately. Any density change must also
update vessel lighting, reflections and editor previews.

Enable the new renderer by default only after paired visual and performance
checks cover procedural and painted weather, day/night/sunset, moving storm
views, a rocket inside cloud, reflections, atmosphere crossings, orbit and
distant planet views. Preserve the old path for comparison until acceptance;
then remove obsolete passes and update the affected tests and diagnostics.

## Step 1 validation record

Recorded October 13, 2026 on the RX 580 (Vulkan, Forward+, double-precision
Godot 4.5.1), each run with scratch `XDG_*` storage. This step does not fix
temporal artifacts or change the cloud appearance.

- **Shared accumulation:** `tests/test_cloud_integral.gd` runs the include in
  a compute shader against a CPU double-precision oracle (direct prefix
  products, two-pass variance). 11 cases, including a zero-distance sample,
  sub-precision opacity and 3000 km banks: pass, with legacy fields
  bit-identical with and without `CLOUD_MEASURE_DEPTH`.
- **Volume traversal:** `tests/test_cloud_volume_result.gd` replaces only the
  density function, after asserting the substitution. Misses, clip before and
  within the shell, camera inside cloud, opaque exit, separated layers, a
  marched empty shell, a sub-cutoff thin volume and a grazing two-bank ray
  match analytic transmittance and depth moments, with the cost view on and
  off: pass. The test now restores the cost-view global to its project default
  instead of reading it, which logs an editor-only error at runtime.
- **Frozen reference:** `tests/_probe/cloud_integral_reference.gd` compiles
  the pre-change integrator
  ([frozen copy](performance/cloud-foundation/clouds_volume.pre-integral.gdshaderinc.txt))
  beside the current one and compares their outputs per ray in float.
  It first checks that all shared helpers are textually identical. It covers
  32 configurations of 8192 rays (measured/legacy × procedural/authored ×
  ground, inside, above, 100 km, 2700 km, night, occupancy miss, cost view),
  three clip distances and mixed weather with storm-free texels. Every ray
  agrees within 1e-5. Each view except the deliberate authored occupancy miss
  covers 1300–8192 cloud rays. The first version of this probe had a uniform
  storm weather map, which disables authored cumulus and stratocumulus, and its
  2700 km view missed the planet. Both gaps are now fixed.
- **Composite and motion:** `test_cloud_composite_split`,
  `test_cloud_motion_reprojection` and `test_cloud_deck_reconstruction`
  pass. The split far-fade check is marginal: max error is 5/255 against
  a 0.02 limit in the baseline and in three reruns. One run reached 6/255
  and failed. Both values compare split with original within one build.
- **Foreground, lighting, reflections:** `test_flame_cloud_overlap`,
  `test_cloud_vessel_light`, `test_ocean_mesh` and
  `test_launch_island_water` pass. Ocean and vessel lighting use the
  shared density and shadow helpers, which the reference guard shows are
  unchanged.
- **Other graphical cloud tests:** formations, mushroom, horizon and distance
  pass. Horizon and distance substitutions may be no-ops (see findings), so
  they are not evidence for the depth contract. `test_clouds` failed "Distant
  clouds match a high-precision depth reference" (mean difference 0.007
  against a 0.003 limit) with the frozen integrator and at commit `ee3d23c`.
  The test captured three frames after jumping from 100 to 1600 km. Since full
  resolution moved to about 3000 km, that view uses temporal reconstruction.
  It refreshes each pixel every fourth frame with 70% history, so detail
  sharpens with a time constant of about 13 frames. The two captures measured
  that convergence, not depth precision (`tests/_probe/globe_depth_reference.gd`):
  a near-plane change at a settled pose differs by under 0.0001. The test now
  settles 120 frames before each capture and passes at 0.00011.
- **Headless lifecycle:** `tools/check.sh` passes all 89 checks, including
  import, the gameplay smoke test, cloud editor, painting, save and occupancy.

Exit criteria met: measurements are finite and valid, legacy output matches
the frozen reference, and temporal policy, density, sample positions, save
data and color conventions are unchanged.
