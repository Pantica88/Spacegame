# Gameplay performance baseline — 7 October 2026

Completed two compatible standard suites: eight checkpoints × three repeats per suite (48 accepted trials). Both reports validate successfully; no source changes or competing graphical Godot instances were reported. The repeat triggered no regression flags. This is a baseline capture, not an optimization claim.

## Artifacts

- [Baseline interactive report](../build/performance/baseline-20261007/20261007T174336664927Z-baseline/report.html)
- [Independent repeat and comparison](../build/performance/baseline-20261007/20261007T175347988647Z-repeat/report.html)
- Frozen source and import cache: `build/performance-baseline-20261007-source/`. Keep this directory: the reports hash assets but do not archive their contents.
- Saved baseline pointer: `build/performance/baseline-20261007/baselines.json`.
- Each report includes raw CSV/JSON timings, per-repeat traces, event markers, warmup/startup measurements, logs and final screenshots. Orbit and landing screenshots were visually inspected; all fixtures passed their expected-effect assertions.

## Conditions

Godot 4.5.1 Standard, OpenGL Compatibility, AMD Radeon RX 580, Mesa 25.0.7, Intel Core i5-9600K. Output 1280×720, logical viewport 1600×900, VSync off, uncapped rendering, native 60 Hz physics, fixed seed 17171, dummy audio. Each trial uses a fresh process and isolated user directories, two seconds of render warmup and eight simulation seconds of measurement. Scenario order reverses on alternate repeats. The performance harness passed all 17 Python tests.

## Measurements

Baseline pooled measurements in milliseconds. The 60 FPS frame budget is 16.67 ms. P95 and p99 describe the slow tail; lower is better.

| Checkpoint | Frame median | Frame p95 | Frame p99 | Worst frame | GPU median | Frames over budget | Repeat median |
|---|---:|---:|---:|---:|---:|---:|---:|
| launch | 10.67 | 11.79 | 12.24 | 23.22 | 10.28 | 0.22% | 10.70 |
| dense_clouds | 13.43 | 13.92 | 15.04 | 86.58 | 12.88 | 0.68% | 13.43 |
| staging | 12.86 | 14.11 | 15.76 | 29.50 | 12.29 | 0.87% | 12.81 |
| orbit | 19.27 | 19.99 | 20.95 | 85.23 | 18.63 | 99.76% | 19.24 |
| map | 7.81 | 9.76 | 10.07 | 76.94 | 7.23 | 0.24% | 7.95 |
| reentry | 11.19 | 13.13 | 13.75 | 76.73 | 10.63 | 0.39% | 11.19 |
| parachute | 14.46 | 15.06 | 15.44 | 19.22 | 13.92 | 0.18% | 14.39 |
| landing | 14.32 | 16.43 | 52.36 | 173.19 | 10.74 | 4.46% | 14.25 |

## Findings and next measurements

1. **Orbit rendering:** median frame 19.27 ms and median GPU 18.63 ms, with almost every frame over budget. In baseline repeat 1, viewport medians were 13.65 ms for the main viewport and 4.96 ms for the separate cloud viewport. This suggests a GPU bottleneck; the main viewport needs finer profiling before attributing its cost to terrain, atmosphere, cloud compositing, or another effect.
2. **Landing CPU spikes:** baseline p99 52.36 ms, repeat p99 52.00 ms, baseline maximum 173.19 ms. In baseline repeat 1, its worst frame included 119.05 ms in the main physics callback. Profile contact, cloth and first-use work independently; current instrumentation does not identify the responsible function.
3. **Early checkpoint stalls:** the worst frames in baseline repeat 1 for orbit, map and reentry occurred at simulation tick 1 or 2 with roughly 51–53 ms in the main physics callback. These fixtures jump directly to checkpoints, so this evidence does not establish that ordinary mission transitions stall the same way.
4. **Tail variability:** no automatic regression flags does not mean identical timing. Dense-cloud p99 changed from 15.04 to 17.51 ms despite nearly identical medians. Keep multiple repeats and inspect tails when accepting improvements.

## Capture recovery and limitations

The first suite command terminated after the final landing trial wrote output but before runner finalization. That original trial remains under `interrupted-landing-repeat-03/` and is excluded from accepted results. The final trial was rerun through the existing `run_case` validation and contention checks; source hashes were verified before and after recovery, all 24 accepted results passed the normal report validator, and only then was the baseline selected. `run.json` records this recovery. The second suite completed normally.

These are short fixed checkpoints on one machine, not a continuous mission, soak test, 1080p result, or release-build guarantee. CPU and GPU timing overlap and must not be added. Main callback timing excludes independently processing child nodes. Fresh processes do not guarantee cold driver caches. Best-effort Godot contention checks cannot exclude every background GPU workload. Exit logs include ObjectDB leak warnings; this performance pass does not resolve those lifecycle issues.

## Reproduce

From the project root, with other graphical Godot instances closed:

```bash
python3 build/performance-baseline-20261007-source/tools/perf_lab.py \
  --output "$PWD/build/performance/baseline-20261007" \
  run --preset standard --label unchanged-repeat
```

For a candidate in the working tree, use `./perf.sh --output "$PWD/build/performance/baseline-20261007" run --preset standard --label candidate`. Keep the same settings, alternate reference/candidate runs, and preserve the frozen source.
