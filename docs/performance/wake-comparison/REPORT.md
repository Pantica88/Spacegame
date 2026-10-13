# Wake enabled versus disabled during ascent

Tested October 10, 2026 after removing both body flame shell passes. Two actual straight-up flights of the current saved **78-part, eight-stage rocket** reached 32 km at full throttle, SAS and 1× time. These runs use the latest save, which differs from the earlier 77-part ascent benchmark. The original profile remained unchanged; its hash is in `profile.sha256`.

Godot 4.5.1 custom double-precision build, Forward+, Radeon RX 580, 1920×1008, VSync disabled. Cloud stencil split, hull heating, engine exhaust and HUD remained active. Only the atmospheric wake mesh visibility alternated. Wake updates still ran, so this measures its GPU rendering cost, not its CPU update cost.

## Result

The remaining wake is a small contributor to the reported ascent slowdown. Median paired GPU savings were **0.102 ms** and **0.060 ms** in the two runs; transparent-pass savings were **0.074 ms** and **0.057 ms**. Median paired frame-time differences were 0.130 ms and 0.095 ms, which amount to substantially less than 1 FPS around a 20 ms frame.

Removing the entire wake is a practical estimate of the upper limit on savings from optimizing its GPU path tracing in these conditions. Baking would retain texture lookups, animation and pixel drawing, so its savings would normally be smaller. These results do not justify baking as a priority for the 8–30 km ascent slowdown. They do not establish the wake's cost during strong re-entry or broadside flight. Earlier cloud measurements identified a much larger contributor, although those measurements preceded shell removal and used the earlier rocket.

## Method and limitations

Alternated every 18 frames, skipping the first five frames after each switch. Run 1 used `normal,no_wake`; run 2 reversed that order. Measurements are matched within 2 km altitude bands, requiring at least ten samples in both modes. Summary values are medians of band differences from 8 to 30 km, not subtraction of unrelated whole-flight medians. Below heating onset the wake is naturally hidden.

The 24–26 km band straddles a sharp cloud-rendering cost change. The modes sample different moments within that transition, producing a large unrelated difference; it is shown below but must not be attributed to the wake. The median summary is resistant to this outlying band. Small differences elsewhere are subject to frame/GPU timing noise; the repeat confirms the scale rather than precise microsecond accuracy.

| Run | Altitude km | Samples on / off | GPU on ms | GPU off ms | GPU saving ms | Transparent saving ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 8–10 | 56 / 57 | 18.684 | 18.523 | 0.160 | 0.080 |
| 1 | 10–12 | 52 / 47 | 19.153 | 19.033 | 0.120 | 0.125 |
| 1 | 12–14 | 39 / 52 | 18.864 | 18.761 | 0.102 | 0.116 |
| 1 | 14–16 | 49 / 39 | 18.554 | 18.496 | 0.058 | 0.074 |
| 1 | 16–18 | 41 / 39 | 18.656 | 18.537 | 0.119 | 0.112 |
| 1 | 18–20 | 32 / 39 | 19.004 | 18.851 | 0.154 | 0.069 |
| 1 | 20–22 | 34 / 33 | 19.165 | 19.111 | 0.054 | 0.047 |
| 1 | 22–24 | 30 / 32 | 19.345 | 19.259 | 0.086 | 0.062 |
| 1 | 24–26 | 35 / 27 | 19.385 | 17.525 | 1.860 | 2.876 |
| 1 | 26–28 | 27 / 38 | 16.582 | 16.558 | 0.024 | 0.057 |
| 1 | 28–30 | 38 / 26 | 16.508 | 16.423 | 0.085 | 0.069 |
| 2 | 8–10 | 56 / 65 | 18.473 | 18.412 | 0.060 | 0.076 |
| 2 | 10–12 | 52 / 52 | 18.942 | 18.973 | -0.031 | 0.004 |
| 2 | 12–14 | 52 / 41 | 18.711 | 18.626 | 0.085 | 0.093 |
| 2 | 14–16 | 39 / 50 | 18.444 | 18.422 | 0.022 | 0.044 |
| 2 | 16–18 | 46 / 39 | 18.524 | 18.443 | 0.080 | 0.060 |
| 2 | 18–20 | 33 / 39 | 18.786 | 18.755 | 0.031 | 0.051 |
| 2 | 20–22 | 38 / 35 | 19.054 | 19.044 | 0.010 | 0.043 |
| 2 | 22–24 | 35 / 30 | 19.279 | 19.224 | 0.054 | 0.052 |
| 2 | 24–26 | 30 / 36 | 19.376 | 16.650 | 2.726 | 2.943 |
| 2 | 26–28 | 38 / 29 | 16.599 | 16.527 | 0.072 | 0.069 |
| 2 | 28–30 | 27 / 36 | 16.493 | 16.385 | 0.108 | 0.057 |

## Reproduce

Copy the desired profile and planets into an isolated XDG data directory, then run:

```sh
XDG_DATA_HOME=/tmp/your-isolated-data ASCENT_OUTPUT=/tmp/wake-run1 \
  ASCENT_COMPARE=1 ASCENT_MODES=normal,no_wake ASCENT_LIMIT=32000 \
  ./tools/run.sh --audio-driver Dummy --profile-gpu \
  --script res://tests/benchmark_saved_ascent.gd
```

Repeat with `ASCENT_MODES=no_wake,normal` and a separate output directory. `run1.json` and `run2.json` retain the per-band medians, sample counts and frame p95 measurements. Progress logs record the actual flight trajectory. No production effect settings were changed by this comparison.
