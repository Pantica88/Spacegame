# Repeatable performance lab

[Measured baseline and independent repeat — 7 October 2026](PERFORMANCE_BASELINE_2026-10-07.md).

Run from the project directory in a graphical desktop session:

```bash
./perf.sh                              # standard: all checkpoints, three repeats
./perf.sh run --preset quick           # shorter functional/performance smoke run
./perf.sh run --preset soak            # 60 simulation seconds per checkpoint, three repeats
```

Python 3.11+ and the Godot 4.7.2 double-precision build are required. The runner discovers `GODOT_BIN`, the double-precision editor at `~/godot-double/src-4.7/bin/godot.linuxbsd.editor.double.x86_64` (then the previous 4.5.1 build in `~/godot-double/src/bin/`), `godot`, `godot4`, or the existing `/tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64` installation. Use `--godot /absolute/path` to override. It uses Forward+ (`tests/performance/lab.json`), 1280×720, VSync off, uncapped rendering, a fixed seed, and native 60 Hz physics. Audio uses Godot's Dummy driver, so these captures do not measure hardware audio output. The project runs through the selected Godot executable, not an exported release build; keep that execution mode consistent. Timing includes the small test instrumentation overhead.

The first **valid** run for a preset, scenario selection and settings becomes its saved baseline. Subsequent matching runs compare automatically. Runs are never overwritten; failed runs retain their logs and cannot become baselines. Results live in ignored `build/performance/`. Open the printed `report.html` locally; it needs no server or network access.

```bash
./perf.sh run --label before
# Make one optimization, then repeat the same command/settings:
./perf.sh run --label after
./perf.sh list
./perf.sh baseline RUN_ID              # explicitly replace the saved reference
./perf.sh compare BEFORE_ID AFTER_ID   # regenerate AFTER's report against BEFORE
./perf.sh scenarios
./perf.sh run --scenario map --label map-investigation
./perf.sh run --preset quick --repeats 2 --label smoke
./perf.sh run --baseline /path/to/reference --fail-on-regression
```

Run IDs, unique labels, or run-directory paths identify saved runs. `--output /absolute/path` goes **before** the subcommand. `--resolution 1920x1080`, `--warmup-seconds 3`, `--sample-seconds 10`, `--repeats 3`, and `--no-capture` are run options. A new configuration receives a separate baseline. Explicit comparisons reject incompatible configurations, fixture versions, Godot/renderer/GPU/driver or CPU changes. Keep power settings and background workloads consistent too; software cannot establish that the machine is idle.

## What is exercised

| Checkpoint | Workload |
|---|---|
| `launch` | Nine Titan engines, ignition at the first measured physics tick, native flight loop and UI |
| `dense_clouds` | Flight at 3,850 m in a fully occupied, mixed-family authored cloud map |
| `staging` | Powered flight with eight radial boosters; separation at tick 60 |
| `orbit` | Circular-orbit checkpoint at 100 km |
| `map` | Live orbital flight with the map open and scripted camera rotation |
| `reentry` | Hot descent at 12 km with the aerodynamic heat wake |
| `parachute` | Deployment at the first measured tick, inflation and descent |
| `landing` | Ground contact with deployed fabric and subsequent cloth settling |

These are fixed checkpoints, not a replay of a complete mission. The runner verifies that expected effects actually occur: thrust, detached debris, clouds, map, heat wake, parachute fabric and ground contact. It starts a fresh Godot process and isolated save/config/cache directories for each trial. It does not use or alter your saved weather, craft or progress. Test-only subclasses measure the existing main callbacks; production controls, physics and rendering are unchanged.

Each trial draws the checkpoint during a wall-time warmup, then advances a fixed number of **simulation ticks**. Faster machines render more frames over the same simulated interval. Ignition, staging and parachute deployment remain measured events, so their first-use spikes are visible. Scenario order reverses on alternate repeats; only one game process runs at a time. A process lock prevents overlapping lab runs, including across worktrees. A Linux process check rejects other graphical Godot instances before capture and checks again once per second during each trial; a conflict stops the batch and invalidates it. Close other games/editors and avoid interacting with the test window. These guards cannot detect all non-Godot GPU workloads, short-lived processes between checks, or processes hidden by container permissions.

## Reading the report

The HTML report provides per-scenario median, p95, p99, maximum and percentage of frames over 16.67 ms, separate GPU timing, interactive per-repeat traces, warmup traces, event markers, startup timing, screenshots and baseline deltas. Hover over the trace to inspect a sample. Expand analysis using `frames.csv`, `summary.json`, or each trial's `result.json` and `godot.log`.

- **Frame time:** wall interval between completed draws. This includes scheduling, CPU work, rendering and stalls; it is not isolated GPU time. Consistent 60 FPS requires meeting the frame budget, especially at the tail, not merely a good median.
- **GPU time:** sum of measured active viewports, including internal offscreen cloud rendering and both map viewports. Timer results can lag CPU events. Zero-only GPU captures are invalid.
- **Render CPU:** active-viewport render CPU plus renderer frame setup. This excludes script processing.
- **Main physics/process CPU:** measured main-game callbacks per rendered frame. Independently processing child nodes are excluded. Several physics ticks may occur in one frame; zero ticks is also normal. CPU and GPU overlap: do not add their timings as if they were sequential.
- **First frame:** fixture setup and fixture-to-first-draw are separate from engine-start-to-first-draw. Fresh application processes do not guarantee a cold driver shader cache. Warmup and measured event spikes remain separate in the report.
- **Regression flag:** frame p95 or GPU median worsened by both >5% and >0.5 ms. This is an investigation signal, not statistical proof. `--fail-on-regression` returns 2 for a flagged valid comparison; errors/incompatible comparisons return 1. Deadline misses remain visible even when no regression is flagged.

Each trial saves `final.png` after timing ends. Readback and PNG encoding do not enter the timing samples. Screenshots are checkpoint evidence, not pixel-exact visual regression tests: native scheduling, temporal effects, particles and interpolation can differ. Use the dedicated cloud visual tests for controlled image comparisons. The lab does not claim a full-game FPS improvement from an isolated GPU delta, nor guarantee continuous 60 FPS across every mission, hardware configuration or long session. Quick mode validates the harness; use standard repeats and longer targeted runs before accepting optimizations.

For before/after decisions, alternate unchanged baseline and candidate source checkouts with identical settings (A/B/A/B), running each sequentially. The suite reverses scenario order within each run; it does not automatically switch source trees. Baselines remain saved until explicitly replaced. Keep the full traces and compare per-repeat spread, not just pooled medians.

## Reproducibility and maintenance

`tests/performance/lab.json` defines presets and descriptions. `run_scenario.gd` constructs the checkpoints; `timed_game.gd` instruments callbacks. Increment `FIXTURE_VERSION` whenever changing checkpoint content, camera, event timing or measurement semantics; incompatible fixture versions must not be compared. Source fingerprints include scripts, scenes, assets, project settings and lab implementation; hashes and modification times are checked before/after capture, and changed files invalidate the run. The run also saves before/after source fingerprints, names changed files, and saves Git status and the tracked diff. Hashes identify untracked assets but do not archive their contents: retain the original checkout/assets to reproduce a run. Generated import caches are excluded from the fingerprint.

No source files, commits or worktrees are changed by the runner. Only benchmark artifacts and Godot's ordinary project import cache may be written. Interrupting a running trial kills that child process and retains an invalid partial report.

Validate the reporting and runner safeguards without a display:

```bash
python3 -B -m unittest discover -s tests -p 'test_perf_*.py'
./tools/run.sh --headless --check-only --script res://tests/performance/run_scenario.gd
```

Then use a graphical quick run to verify actual GPU measurement and fixture assertions. Existing `tools/check.sh` remains the broader gameplay regression suite. The specialized cloud occupancy/image benchmarks and their documented validation remain useful for shader changes; the gameplay lab complements those tests.

[Implementation validation, artifacts and known existing regression failures](PERFORMANCE_LAB_VALIDATION.md).
