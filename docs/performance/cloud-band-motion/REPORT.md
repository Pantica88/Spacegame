# Cloud bank during vertical motion

**Follow-up:** the moving dotted-row artifact now has a storm-depth
reprojection correction. See [fix, heatmap and validation](fixed/REPORT.md).
The observations below document the initial capture before that correction.

Captured October 11, 2026, from the owner's supplied view:

```text
View: time 0.0  pos -450.2, 8166.1, 35.8  yaw 1.427  pitch -0.197  weather 167.7
```

The right-hand cloud rim develops dotted horizontal rows during both ascent
and descent. Disabling temporal reconstruction removes those dotted rows in
the paired captures, while broader shading bands remain. This isolates the
temporal contribution; it does not establish the cause of the reported
performance slowdown or resolve the separate lower-edge artifact.

- [Right-edge crops during ascent and descent](right-edge-motion.png)
- [Same ascending frames, temporal on versus off](temporal-comparison.png)
- [Full starting view](start.png)
- [Exact poses for every snapshot](manifest.json)

## Capture method

Godot 4.5.1 double-precision, Forward+, AMD RX 580, 1600 × 900 viewport.
The hover scene uses the production renderer and the saved planet data copied
into an isolated data directory. The rocket is hidden, as in the supplied hover
view. Time, weather, yaw, pitch, x and z remain fixed. Each direction begins at
the supplied position after 120 settling frames, then moves 8 metres per rendered
frame for 120 frames. VSync is disabled, so this is a fixed displacement per
frame, not a fixed speed in metres per second.

Snapshots are taken after drawing movement frames 1, 16, 32, 64, 96 and 120,
without pausing to let history settle. The up run ends at y=9126.1 m; the down
run ends at y=7206.1 m. The labels give launch-frame y; the manifest also records
radial altitude. The crops cover x=850–1250, y=200–460 of the full captures.

The root images use normal temporal reconstruction. `no-temporal/` contains
the same sequence with reconstruction disabled, still at the normal reduced
cloud resolution. Both use the original two-tap storm sampling and the stencil
split. All full frames and capture logs are retained.

Reproduce with `tests/_probe/cloud_band_motion.gd`: set `BAND_OUTPUT` to a
directory, use `tools/run.sh --script tests/_probe/cloud_band_motion.gd`, and
optionally set `BAND_TEMPORAL=0`. Supply an isolated `XDG_DATA_HOME` containing
the same saved planet to reproduce its authored weather.

## Renderer state and validation

An earlier experiment separately shaded each storm density sample with smaller
steps. It reduced some broad banding but failed the `far_fade` image comparison
(maximum channel error 0.098039, allowed below 0.02). That experiment was backed
out before the captures in this directory. The existing render-cost counters,
stencil split and disabled flight body-heating effect were preserved.

After restoring the original sampling, the graphical
`tests/test_cloud_composite_split.gd` regression passed all eight cases,
including foreground occlusion, far fade and temporal reconstruction. Its
summary is in [validation.log](validation.log). No cloud rendering fix is
claimed by this capture report.
