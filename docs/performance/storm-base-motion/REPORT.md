# Storm base during forward and backward movement

## Current fix: atmospheric storm views

The earlier 5,300–6,700 m bypass was too narrow: the same temporal distortion
was reproduced at 4,100 m and above 6,700 m. Authored weather containing storms
now uses fresh half-resolution cloud frames throughout atmospheric flight.
The guard follows the planet's atmosphere height (90 km in this saved world),
not another narrow band around the low deck. Orbital views and storm-free
weather retain temporal reconstruction. This remains a bypass of the
single-sphere depth approximation, not measured per-pixel cloud depth.

[Comparison at 4,100, 8,000 and 12,000 m](altitude-before-after.png)

Validation sweeps from y=3,500 to 16,000 m and immediately back, moving 25 m
per rendered frame with the supplied x/z, yaw, pitch and weather held fixed.
Thirty moving snapshots plus the starting frame are retained in each of
`altitude-before/`, `altitude-reference/` and `altitude-fixed/`. The reference
disables temporal reconstruction explicitly. All fixed captures confirm that
the temporal march is inactive. Mean RGB error over moving frames versus
the reference fell from 0.738848 to 0.000064 byte levels; the compared scene
includes other independently animated rendering. See `altitude-errors.json`.

The atmospheric lifecycle check covers 4,100 m, both former band boundaries,
the atmosphere exit and history restart, a shorter atmosphere, storm-free
weather and explicit temporal disable. The wider bypass keeps the same
half-resolution output but marches all its pixels rather than one quarter,
so the increased cloud GPU workload now applies throughout atmospheric
storm views. This capture is not a performance benchmark.

The atmospheric lifecycle, graphical storm-motion, and eight-case cloud
composite regressions all pass. Logs are `atmosphere-regression.log`,
`atmosphere-motion-regression.log`, and `atmosphere-composite-regression.log`.

An initial fixed sweep lost its Vulkan device context and stopped partway
through; `altitude-interrupted.log` preserves that failure. The rerun completed.

## Superseded fix for the 6,000 m crossing

The first fix rendered fresh half-resolution cloud frames while
the camera is inside the low deck and the authored weather contains storms.
In this saved world that band is 5,300–6,700 m. The previous reconstruction
places history on a sphere at the deck midpoint (6,000 m). Near that sphere,
the assumed cloud distance can collapse toward zero, making distant storm
pixels move incorrectly as the camera passes through it.

This is a targeted bypass of that depth approximation, not a new measured
cloud-depth implementation. Outside the band, or in storm-free weather,
normal temporal reconstruction remains enabled. Leaving the band invalidates
old history. Cloud volume sampling and output resolution are unchanged, but
inside the affected band all reduced-resolution pixels are now marched each
frame instead of one quarter: more GPU work in exchange for stable crossings.

[Crossing before/after](crossing-before-after.png) · [Fixed moving frame](crossing-fixed/forward_064.png)

Vertical reproduction uses the supplied x/z, yaw, pitch and weather, starting
at y=5,760 m, climbing to 6,240 m and descending back without stopping for
history to settle. `crossing-before/`, `crossing-reference/` (temporal off),
and `crossing-fixed/` retain 13 images each. Across the 12 moving captures,
mean RGB difference against fresh reference frames fell from 1.28727 to
0.000073 byte levels. See `crossing-errors.json`. The fixed captures retain
the configured temporal preference; the low-deck guard bypasses it there.

Validation: `test_cloud_deck_reconstruction.gd` passes, covering both deck
crossings, the reported 5,885/6,000 m heights, image resolution, history reset,
storm-free weather and explicit temporal disable. The storm-cap motion
regression passes above the band. The composite regression passes on repeat;
its first run reported an intermittent distant `far_fade` maximum difference
of 0.098039, while both a guard-bypassed baseline and repeat passed at 0.019608.
That distant case lies outside the new guard and is recorded rather than
treated as a verified correction to the separate far-view issue.

The sections below document the earlier diagnostic captures.

Captured October 11, 2026 using the supplied view:

```text
View: time 0.0  pos 127.0, 5984.9, -400.4  yaw -0.000  pitch 0.095  weather 24.1
```

[Snapshot overview](motion-snapshots.jpg) · [Settled start](start.png) · [Moving frame](forward_064.png) · [Exact positions](manifest.json)

The moving frame shows dotted horizontal bands across the lower cloud region
and near the terrain horizon. The settled starting frame is visibly smoother.
These captures reproduce the artifact; they do not establish its cause.

## Follow-up: temporal reconstruction comparison

Replaying the same movement with `STORM_MOTION_TEMPORAL=0` removes the fine
dotted bands in the inspected frame, while retaining the clouds and their
broader shading. This isolates a temporal reconstruction contribution to the
reported heat-haze appearance. It does not identify every remaining artifact
or prove which depth assumption causes it. The production renderer remains
unchanged by this comparison.

[Same-frame comparison](shimmer-comparison.png) · [Full frame without temporal reconstruction](no-temporal/forward_064.png)

All thirteen comparison frames and their exact poses are in `no-temporal/`.

The production hover scene loads a copy of the user's saved planet data from
`/tmp/aphelion-storm-motion-data`. The viewport is 1600 × 900, with normal
temporal reconstruction enabled. Time, weather, yaw and pitch remain fixed.
After 120 settling frames at the supplied position, the camera moves 4 metres
per rendered frame along its viewing direction for 120 frames (480 metres),
then reverses immediately and returns along the same path for 120 frames.
This follows the pitched viewing direction, so altitude changes slightly.
VSync is disabled; displacement is fixed per frame, not per second.

Snapshots follow movement frames 1, 16, 32, 64, 96 and 120 in each direction,
without stopping or allowing history to settle. PNG readback can stall wall
time. The final position exactly matches the supplied starting position.

Reproduce from the repository root:

```bash
XDG_DATA_HOME=/tmp/aphelion-storm-motion-data \
STORM_MOTION_OUTPUT="$PWD/docs/performance/storm-base-motion" \
./tools/run.sh --script res://tests/_probe/storm_base_motion.gd
```

The shader includes the preceding base-haze, storm cumulus and storm
stratocumulus removals. No renderer changes were made for this capture.
