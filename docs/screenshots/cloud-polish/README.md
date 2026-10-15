# Cloud visual pass — 2026-10-14

The low-flight comparison reproduces the supplied screenshot camera: time 0,
position (34571, 613.8, -30347.8), yaw -0.461, pitch -0.165, weather time 42.3.
Captures are 1280 × 720 with the HUD hidden and weather frozen.

- [Before](low-before.png)
- [After](low-after.png)
- [Above the low deck](above-after.png)
- [Sunset](sunset-after.png)

Long paths previously increased the minimum march step even near the camera.
Capping that minimum at 60 m resolves nearby edges without increasing the
256-iteration budget. Hashed pixel seeds and a golden-ratio temporal sequence
replace the diagonal interleaved pattern. Low cloud shapes vary more with
height and have stronger erosion; slightly weaker multiple scattering gives
interiors more contrast. The CPU density and lighting port matches the shader.

Validation:

- `tools/run.sh --headless --script res://tests/test_clouds.gd`: pass.
- GPU version at 1280 × 720: pass, including 512-point CPU/GPU parity,
  foreground occlusion and moving-versus-stationary rendering.
- Maximum moving/stationary mean RGB difference: 0.0006 (limit 0.03).
- Actual benchmark viewport: 1920 × 1008 (desktop-constrained window), RX 580,
  Vulkan Forward+, 45 measured frames per view, vsync disabled.

| View | Median total GPU ms | Median cloud passes ms |
| --- | ---: | ---: |
| Ground horizon | 4.43 | 1.48 |
| Inside deck | 5.78 | 3.70 |
| Above deck | 4.16 | 1.97 |
| 12 km ascent | 3.80 | 1.56 |
| Orbit | 6.80 | 2.18 |

These are post-change GPU timings for the probe's standard saved-weather views,
not a before/after performance comparison or a CPU/frame-rate guarantee.

Reproduce the comparison:

```sh
CLOUD_POSES='low:0 34571 613.8 -30347.8 -0.461 -0.165 42.3;above:0 36575.1 2424.1 -28253.7 0.241 -0.393 53;sunset:3150 39754.9 6041.6 -71517.9 1.216 -0.053 126.6' \
CLOUD_VIEWS=low,above,sunset CLOUD_SHOTS=/tmp/cloud-polish \
tools/run.sh --resolution 1280x720 --script res://tests/_probe/cloud_views.gd
```
