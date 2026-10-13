# Cloud compositor stencil split — October 10, 2026

Forward+ now uses a lightweight stencil classifier, a cheap upsampling shader, and a separate full-detail shader restricted to the marked pixels. The classifier preserves the original scene-depth, terrain silhouette, cloud-limb and altitude-crossfade decisions. The two color passes cover disjoint pixels, avoiding double blending. Both draw after the sun and before exhaust and atmospheric fire.

The full-screen upsampling shader has no compiled volume-integration calls. All passes share the same weather, camera, low-resolution/temporal texture and altitude-blend parameters. Other rendering backends retain the original compositor. Shader replacements used by diagnostic tools disable the supporting passes; restoring the production shader restores them.

F10 now cycles **stencil split → original → no full-detail march → no edge check → neither**. The last three remain diagnostic modes and can lose occlusion or silhouette quality. F9 continues to show cloud sample cost and overdraw.

## Saved-rocket measurement

Godot 4.5.1 double precision, Forward+, Radeon RX 580, 1920×1008, vsync disabled. An isolated copy of the player save climbed to 12,019 m, then simulation and weather were frozen. The rocket had 182 heated meshes. Each mode was warmed before measurement. Four comparisons alternated mode order, collecting 160 GPU samples per mode after discarding switching frames.

| Mode | Median main-view transparent pass |
| --- | ---: |
| Original | 10.906 ms |
| Stencil split | 8.397 ms |
| No full-detail march | 5.965 ms |
| No edge check | 8.537 ms |
| Neither | 5.963 ms |

The split saves **2.509 ms (23.0%)** in this view while retaining foreground occlusion. It does not reach the unsafe no-march mode's speed: exact pixel classification and the remaining detail work still cost time. These are transparent-pass timings, not whole-frame timings.

## Validation

`tests/test_cloud_composite_split.gd` compares rendered pixels against the original compositor below, inside and above the cloud layer, in orbit, during the far-altitude blend, without a rocket, at full resolution and with temporal reconstruction. It also checks shared uniforms, supporting-pass lifecycle, diagnostic replacement and F10 selection. Run with `--profile-gpu` to include paired GPU timings:

```sh
./tools/run.sh --profile-gpu --script res://tests/test_cloud_composite_split.gd
```

Captures are saved under `/tmp/aphelion-cloud-split`. The inside/above cases also verify that disabling the detail march produces a measurable error: clouds visibly wash out the rocket. The split preserves its opaque silhouette.

Graphical launch-warmup and flame/cloud-overlap checks pass. Headless cloud-editor and aerothermal checks pass.

The older `tests/test_clouds.gd` distant-depth-reference assertion fails with both compositors: mean RGB difference 0.00635145 for the split and 0.00635173 for the original, against a 0.003 threshold. Its other checks pass. This existing failure was reproduced without the split and was not changed as part of this optimization.
