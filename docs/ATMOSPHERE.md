# Atmospheric lighting

Verdant's surface and launch structures rotate about +Y every 24 simulation minutes (3 minutes at 8× warp). The existing launch site lies on this axis. Surface colors use planet-local coordinates, while sunlight, ocean glints, and haze use world-space directions. This is visual surface rotation; flight dynamics still use the existing nonrotating atmosphere approximation. The separately animated sun retains its eight-minute cycle.

The sky and planet surface haze share `assets/shaders/atmosphere.gdshaderinc`. It integrates an approximation of single scattering along each view ray, using wavelength-dependent Rayleigh coefficients and forward-biased Mie scattering. Longer atmospheric paths produce a stronger horizon glow. A broad penumbra blends direct sunlight into weak indirect night-side scattering, keeping the halo continuous around the globe without flattening the day/night distinction. Low-angle light receives an artistic warm tint.

The sun completes one visual day every 480 seconds of simulation time. Time acceleration advances the cycle at the selected rate, while pausing stops it. The visible solar disc, scattering, globe shading, and directional light all use the same moving direction. Stars fade out as the local sun rises instead of depending on atmospheric-glow intensity. Workshop mode retains fixed studio lighting and each rollout begins at the same morning angle. `WorldView.set_sun_direction(direction)` remains available for deterministic rendering and normalizes valid input automatically.

Because the local shadow map cannot cover a whole planet, direct illumination of the craft is explicitly reduced when the sun lies behind Verdant. The globe shades itself independently from the same solar direction so that a visible day-side crescent remains illuminated when the craft is in eclipse. Workshop lighting is restored on return.

This is a visual approximation, not a full atmospheric transport simulation. Sky, terrain haze, the ocean patch, foreground moon haze, eclipse lighting and star fading read the planet radius and atmosphere height from the saved definition. Verdant uses visual density 0.18 to compensate for its 90 km atmosphere and reduce haze opacity.

Sample budgets depend on the observer's altitude band (lower half of the air, up to 0.8 body radii, beyond) and the **Atmosphere** quality preset in the pause menu, saved in the profile and applied at once. Ultra keeps the original 16/32/64 view samples with 2/3/6 sunlight samples; High (the default), Medium and Low reduce view samples, take coarser steps on rays that end on terrain or water, and integrate the sky's scattering at half resolution. The sunlight optical depth comes from a small precomputed table per body (`scripts/atmosphere_quality.gd`) built with the shader loop's own quadrature, so every preset keeps the original sunlight colour. Presets never affect flight or physics. Measurements, captures and the reasoning behind each value are in [RENDERING_PERFORMANCE.md](RENDERING_PERFORMANCE.md).

Clouds are a separate volumetric renderer that shares this atmosphere: the haze between the camera and a cloud is the same scattering integral the terrain and sky use, with the same sunlight table, and the sunlight on a cloud reddens through the same air. See [cloud rendering](CLOUDS.md).

The planet editor's **Clouds** tab paints reusable formation tiles directly onto the globe. Cumulus, cloud streets, stratocumulus, overcast, storms and wispy layers have distinct patterns; feathered spherical stamps blend cloud coverage and type across their edges, poles and longitude seam. Painted regions can be captured as custom tiles. Each planet or moon saves its own weather map, and the editor preview and flight renderer consume the same texture. Bodies without an authored map retain procedural weather. See [cloud painting controls and verification](CLOUD_PAINTING.md).

Clouds do not cast shadows on the terrain or simulate physical weather. Their layer heights scale with the atmosphere ([CLOUDS.md](CLOUDS.md#layers)); the editor brush paints at the same height the flight view draws. Airless worlds, zero-density atmospheres and workshop views hide them. The orbital map keeps its existing surface preview.

Run the graphical checks with an isolated user-data directory:

```bash
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --script res://tests/test_atmosphere.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --script res://tests/test_rendering.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --resolution 1280x720 --script res://tests/test_clouds.gd
```

Atmosphere checks capture daylight, sunset, night, and ground views to `/tmp/aphelion-atmosphere`. They compare actual image brightness and color, and verify sunlight alignment, eclipse lighting, and workshop reset. The existing rendering suite checks nearby-altitude continuity and camera views through 100 km.

The cloud checks are described in [CLOUDS.md](CLOUDS.md#checks).

Implementation references: [Godot 4.5 sky shaders](https://docs.godotengine.org/en/4.5/tutorials/shaders/shader_reference/sky_shader.html) and [spatial shaders](https://docs.godotengine.org/en/4.5/tutorials/shaders/shader_reference/spatial_shader.html).
