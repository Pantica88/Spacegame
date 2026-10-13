# Saved rocket: slowdown at 8–30 km

Tested October 10, 2026 with the current player save: **77 parts, seven stages**, profile SHA256 in `profile.sha256`. Two actual vertical flights reached 40 km at 1× time, full throttle and SAS; the craft was not teleported to the measured altitudes. The player's profile and planets were copied to isolated temporary storage. The original profile hash remained unchanged.

Godot 4.5.1 custom double-precision build, Forward+, Radeon RX 580, 1920×1008, VSync disabled. **Stencil split was enabled.** No production renderer or effect settings were changed during this investigation.

## Reproduction

| Altitude band | Median frame | Approximate FPS | Total GPU | Main transparent pass |
| --- | ---: | ---: | ---: | ---: |
| 4–6 km | 14.83 ms | 67 | 13.46 ms | 1.53 ms |
| 8–10 km | 22.38 ms | 45 | 21.07 ms | 8.09 ms |
| 10–12 km | 23.57 ms | 42 | 21.71 ms | 8.42 ms |
| 14–16 km | 22.18 ms | 45 | 21.06 ms | 7.50 ms |
| 22–24 km | 24.15 ms | 41 | 21.87 ms | 7.79 ms |
| 26–28 km | 20.27 ms | 49 | 19.06 ms | 5.02 ms |
| 30–32 km | 20.30 ms | 49 | 19.04 ms | 5.00 ms |

FPS is 1000 divided by each band's median frame time. Screenshot readback frames and the following eight frames were excluded. The full baseline is in `baseline.json` and the flight progress is in `baseline.log`.

[The actual rocket at 12 km](ascent-12km.png).

## Attribution

The second flight alternated short diagnostic modes while climbing. Each mode ran for 18 frames; the first five frames after switching were excluded to allow delayed GPU timestamps to settle. The figures below are the median of matched normal-versus-disabled differences in 2 km bands from 8 to 22 km, using only bands with at least ten samples for both modes. They are approximate marginal costs, not additive budget entries.

| Disabled for measurement | Reduction in total GPU time | Relevant pass reduction |
| --- | ---: | ---: |
| All clouds, including reduced pass and compositor | 4.53 ms | 2.32 ms main transparent |
| All atmospheric heating visuals | 3.85 ms | 3.60 ms main transparent |
| Only the two heating flame shells | 2.56 ms | 2.42 ms main transparent |
| HUD | 2.78 ms | 2.49 ms canvas |

The heating shells are part of the heating total; do not add those rows together. Full ablation measurements are in `ablation.json` and `ablation.log`.

The sharp onset has two overlapping causes:

- Near 8 km, immediate aerodynamic heating crosses the visual activation threshold. All 182 heated meshes acquire the body overlay and two flame-shell passes, even while the visible glow is faint. The GPU pays most of their cost as soon as they are drawn.
- Within the cloud shell, a large part of the screen runs the cloud compositor. Above roughly 25 km, its covered screen area shrinks, explaining the partial recovery. Stencil splitting removed some cost, but classification, the reduced cloud image and required detail work remain.

The HUD costs about 2.5 ms throughout the flight, so it lowers the overall frame rate but does not explain the altitude-specific onset. Renderer CPU time rose from about 2.3 to 3.1 ms, whereas GPU time rose from about 13 to 21–22 ms. This is primarily a rendering slowdown in these runs.

The next candidates are reducing repeated heating-shell work while preserving the current appearance, and reducing cloud classification/compositing overhead. Simply disabling cloud detail would break rocket occlusion; reducing the visible flame layers would change the effect. Neither was applied to production during this test.

## Repeating the test

Use a temporary XDG data directory containing a copy of `BlufftonFlightWorks/Aphelion/profile.json` and its `planets/` directory, then run:

```sh
XDG_DATA_HOME=/tmp/your-isolated-data ASCENT_OUTPUT=/tmp/ascent-baseline \
  ./tools/run.sh --audio-driver Dummy --profile-gpu \
  --script res://tests/benchmark_saved_ascent.gd

XDG_DATA_HOME=/tmp/your-isolated-data ASCENT_COMPARE=1 ASCENT_OUTPUT=/tmp/ascent-ablation \
  ./tools/run.sh --audio-driver Dummy --profile-gpu \
  --script res://tests/benchmark_saved_ascent.gd
```

The test automatically stages if thrust falls to zero while ascending. Keyboard controls are disabled for the run so accidental input cannot change warp or steering. Default target altitude is 40 km; `ASCENT_LIMIT` can change it.

Data caveats: the initial baseline's `canvas_ms` records only the last CanvasLayer timestamp and should not be used; the ablation run sums the CanvasLayers correctly. In the stored ablation run, `gpu_cloud_ms` under `no_clouds` is the engine's stale last timing for the disabled viewport, not work performed that frame. Total GPU and transparent-pass differences remain valid. The benchmark now reports zero for a disabled reduced pass. `no_cloud_mask` also prevents the stencil-tested detail pass from shading, so it is not an isolated classifier-cost measurement.
