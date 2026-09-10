# Atmospheric lighting

Verdant's surface and launch structures rotate about +Y every 24 simulation minutes (3 minutes at 8× warp). The existing launch site lies on this axis. Surface colors use planet-local coordinates, while sunlight, ocean glints, and haze use world-space directions. This is visual surface rotation; flight dynamics still use the existing nonrotating atmosphere approximation. The separately animated sun retains its eight-minute cycle.

The sky and planet surface haze share `assets/shaders/atmosphere.gdshaderinc`. It integrates an approximation of single scattering along each view ray, using wavelength-dependent Rayleigh coefficients and forward-biased Mie scattering. Longer atmospheric paths produce a stronger horizon glow. A broad penumbra blends direct sunlight into weak indirect night-side scattering, keeping the halo continuous around the globe without flattening the day/night distinction. Low-angle light receives an artistic warm tint.

The sun completes one visual day every 480 seconds of simulation time. Time acceleration advances the cycle at the selected rate, while pausing stops it. The visible solar disc, scattering, globe shading, and directional light all use the same moving direction. Stars fade out as the local sun rises instead of depending on atmospheric-glow intensity. Workshop mode retains fixed studio lighting and each rollout begins at the same morning angle. `WorldView.set_sun_direction(direction)` remains available for deterministic rendering and normalizes valid input automatically.

Because the local shadow map cannot cover a whole planet, direct illumination of the craft is explicitly reduced when the sun lies behind Verdant. The globe shades itself independently from the same solar direction so that a visible day-side crescent remains illuminated when the craft is in eclipse. Workshop lighting is restored on return.

This is a visual approximation for the Compatibility renderer, not a full atmospheric transport simulation. Atmosphere scattering uses 64 view samples across a 10 km visual atmosphere and 6 sunlight samples with an inexpensive cubemap path. The higher view-sample count smooths the orbital limb while the compact density profile and reduced scattering multiplier keep its glow restrained. Performance has been exercised on the development desktop, not benchmarked across minimum-spec hardware.

Run the graphical checks with an isolated user-data directory:

```bash
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --script res://tests/test_atmosphere.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --script res://tests/test_rendering.gd
```

Atmosphere checks capture daylight, sunset, night, and ground views to `/tmp/aphelion-atmosphere`. They compare actual image brightness and color, and verify sunlight alignment, eclipse lighting, and workshop reset. The existing rendering suite checks nearby-altitude continuity and camera views through 100 km.

Implementation references: [Godot 4.5 sky shaders](https://docs.godotengine.org/en/4.5/tutorials/shaders/shader_reference/sky_shader.html) and [spatial shaders](https://docs.godotengine.org/en/4.5/tutorials/shaders/shader_reference/spatial_shader.html).
