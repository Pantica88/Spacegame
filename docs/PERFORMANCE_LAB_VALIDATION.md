# Performance lab validation — 6 October 2026

Update, 7 October: two standard gameplay suites now have validated GPU measurements and a compatible repeat comparison. See [the baseline results and capture recovery notes](PERFORMANCE_BASELINE_2026-10-07.md). The earlier implementation-validation record below is retained; its regression failures were not repaired by the baseline capture.

The reusable harness is implemented. A clean full-suite GPU baseline remains pending because another development session was changing the terrain shader and running its own Godot GPU benchmark during validation. No timings from those affected suites should be used to accept an optimization.

## Passed

- **17 Python tests:** timing statistics and deadline misses; zero/invalid GPU samples; incomplete runs; wrong simulation duration; configuration incompatibility; duplicate results; path confinement; isolated saves; missing output; script errors despite exit code zero; renderer contention; and two complete simulated batches exercising automatic baseline persistence/comparison and reversed repeat order.
- **Godot parse check** for the scenario runner.
- **All eight graphical checkpoints, twice each**, with their expected-effect assertions and 1280×720 captures. These demonstrate fixture functionality. The overall run was correctly rejected when its source fingerprint changed.
- **Launch-only graphical capture** completed and saved its baseline before the full-suite attempts. This is not a full-game performance baseline.
- **GPU accounting:** root rendering plus internal cloud viewports, and active map viewports, appear separately in raw samples and are summed in the report.
- **Visual inspection:** captures showed powered launch, mixed clouds, detached boosters, orbit, the orbital map, aerodynamic wake, inflated canopy and landed fabric.
- **Chrome report check:** populated scenario table, 16 trial choices, startup details and chart script; JavaScript syntax check passed.
- **Contention safeguard:** rejected a real concurrently running graphical Godot benchmark. The unit tests also verify that a renderer appearing during capture invalidates the trial.
- **Existing regressions passed:** parachute staging, cloth sleeping/waking, and cloud occupancy (49,129 tested directions, including 13,135 occupied directions).
- `git diff --check` passed. Existing production modifications were preserved.

The Python end-to-end test uses a fake engine and synthetic samples to validate orchestration, not performance. Graphical checkpoint runs exercise the real engine. Interruptions and rejected captures retain their logs and cannot replace the saved baseline.

## Existing failures, reproduced without the harness

`tests/test_flight.gd` reports **24 failures out of 223 checks**. The same result occurs in a separate project containing the existing production files and flight test, with no performance harness. Flight, physics, surface and map script hashes match those recorded at the initial capture. Some test inputs still use 61,000/70,000 m planet-centered radii while the current reference planet radius is 600,000 m; this explains part of the mismatch, not necessarily every failure.

`tests/test_orbital_map.gd` fails its screen-direction assertion at **line 87**. It reproduces in that separate project without the harness. The failed assertion prevents normal script shutdown, so the test was stopped by its timeout. A transient shader-compilation error also occurred while the other session edited terrain; that error did not recur in the frozen-project rerun, but the map assertion still did.

Logs are retained in `build/performance/validation-regressions/`. These failures were not repaired as part of the testing-environment task.

## Artifacts and next clean run

- Functional suite / rejected source-changing run: `build/performance/20261007T010820951740Z-verified-baseline/report.html`.
- Interrupted frozen suite affected by external GPU use: `build/performance/20261007T011537101857Z-frozen-baseline/report.html`.
- A frozen validation project remains at `build/performance-validation-project/` (approximately 1 GB of copied assets plus caches), separate from the working source.

Once other Godot instances are closed and source editing is paused for the capture:

```bash
./perf.sh run --preset quick --repeats 2 --label baseline
./perf.sh run --preset quick --repeats 2 --label repeat
```

The first valid full suite saves its baseline; the second compares automatically. Then use `./perf.sh` for the longer standard preset before judging optimizations. A clean paired full-suite GPU comparison and a long soak remain unvalidated. The environment explicitly reports invalid runs rather than interpreting them as speedups or evidence of continuous 60 FPS.
