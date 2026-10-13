# Storm-bank motion correction

The fine dotted rows beneath the right-hand cloud rim were partly a temporal
reprojection error. The history shader placed every cloud on the low-deck
sphere. Rays missing that sphere used its closest approach, or zero distance
when looking upward, even while seeing a tall storm cap. Vertical travel then
misaligned old pixels with the fresh quarter-frame samples.

The shader now uses the authored storm-cap sphere for rays that cannot hit
the low-deck sphere ahead of the camera. The cap height follows the existing
76% formation profile. Weather without storms clears this fallback. Low-deck
hits retain their previous depth calculation. This remains an approximate
cloud depth, not a per-pixel measurement of the volume.

- [Before/after during ascent and descent](before-after.png)
- [Comparison with freshly rendered frames](reference-comparison.png)
- [Density-sample heatmap during ascent](heatmap.png)

The heatmap shows a broad strip of high sampling cost near the horizon, not
fine cost boundaries matching the dotted rows. It counts density and shadow
evaluations, not individual texture reads or per-pixel milliseconds. Colours
are quantized into ranges and reconstructed like the normal cloud image.
The F9 overlay wording now makes the counted quantity explicit.

## Measurements

Same view, weather, 1600 × 900 viewport, and 8 m displacement per rendered
frame as the initial report. Over all twelve moving snapshots, mean absolute
RGB error in the right-rim crop (x=850–1200, y=230–370) versus non-temporal
half-resolution reference frames fell from **0.820 to 0.438 byte levels**,
a **46.6% reduction**. The renderer keeps its existing march resolution and
sample count; it does not turn on a full-screen detailed march.

Paired uncapped runs, with screenshot readback disabled during movement:

| GPU median | Previous depth | Storm fallback |
| --- | ---: | ---: |
| Main viewport | 6.542 ms | 6.548 ms |
| Reduced cloud march | 1.673 ms | 1.682 ms |

This pair shows no meaningful additional measured GPU cost. It is not evidence
of a speedup. Raw manifests are `bench-old.json` and `bench-fixed.json`; their
resolve timing field was unavailable (zero), so it is excluded here.

## Validation and remaining limits

- New graphical `tests/test_cloud_motion_reprojection.gd` uses a generated
  mushroom bank, independent of the player's save. Averaged over all four
  temporal phases, error versus fresh frames fell from 0.000485 to 0.000341
  during ascent and 0.000494 to 0.000371 during descent. Both pass the required
  15% reduction. See `motion-regression.log`.
- Graphical `tests/test_cloud_composite_split.gd` passes all eight cases,
  preserving foreground occlusion, silhouettes, distant blending and
  diagnostic switching. See `split-regression.log`.
- Additional moving captures at 12 km and 30 km were visually checked against
  non-temporal frames; representative frames are retained here.

Broader volume-shading bands, the separate lower-edge artifact and the broad
horizon sampling cost are not solved by this reconstruction correction.
The earlier smaller-step lighting experiment remains backed out. Flight body
heating remains disabled, as requested for the performance comparison.
