# Seeded planetary terrain

Planet and moon resources use `scripts/planet_definition.gd`. A seed, continental field, mountain belts and smaller relief determine a repeatable spherical height field. Climate and elevation determine the land palette, shore coverage and snow. Changing the seed or shaping settings intentionally changes geography. Existing resources retain their previous geography when the new shaping controls are neutral.

## Modeling controls

The planet editor opens on its **Terrain** tab. **World** contains body names, moons, radius, gravity, rotation, atmosphere and orbit settings; **Clouds** contains weather painting. Each planet and moon has independent terrain settings.

- **Continents**, **Continent edge** and **Sea level** set the large land masses and shoreline transition.
- **Coast irregularity** warps the continental sampling coordinates to produce bays and peninsulas. Zero preserves the original continental field.
- **Relief** sets the overall height budget. **Mountains** sets the frequency of regional mountain belts, and **Mountain height** scales their contribution independently of continental heights.
- **Ridge roundness** rounds mountain crests. **Erosion** narrows ridge shoulders and carves smaller gullies using deterministic noise. This is an authoring approximation, not a running hydraulic erosion simulation.
- **Small ridges** adds another land relief layer, and **Ridge frequency** controls its scale. The same field supplies rendered geometry, baked detail and physical contact.
- Ocean, snow, launch-island options and the palette remain independent controls.

Terrain styles provide starting points for rolling hills, rugged ranges, weathered ridges and island coasts. Styles keep the body's seed, radius, relief budget and palette; the island style also adjusts continent frequency and sea level. The launch facility retains its flat, dry center after shaping.

The inspection toolbar offers **Natural**, **Elevation**, **Slopes**, and **Land & water** views. Inspection views only change the material. Turn off **Rotate preview** to inspect a stationary feature. Right-drag orbits the globe and the mouse wheel zooms. Camera orientation remains continuous across both poles.

## Responsive previews

Terrain edits are debounced for 120 ms. A worker generates a quick 64×32 mesh first, then refines it and prepares surface maps. The worker operates on a settings snapshot and CPU arrays/images; mesh and texture resources are created on the main thread. An older job cannot replace the preview after a new edit or body selection. Leaving the editor joins outstanding work.

The default **Adaptive detail** preview uses 256×128 near the globe and 128×64 farther away, with the launch-region rings where applicable. It does not build collision geometry. The toolbar reports the displayed triangle count. The live surface maps use 1024×512 texels, independent of mesh density. A cache retains at most two sets of generated maps, so zoom and preview-layer changes can reuse them without retaining every slider state. Atmosphere, lighting color and orbit changes do not regenerate terrain.

The flight-layer selector still exposes each exact saved mesh. Use it when inspecting a layer's physical geometry: adaptive preview triangles are a visualization approximation. Saving builds the full contact mesh and all runtime layers.

## Mesh and contact budgets

The full closed terrain mesh uses 512 longitude segments and 256 latitude intervals, plus local launch-site rings. Its triangle budget remains below 300,000. Terrain shaping adds variety within this fixed mesh density. Positions, smooth vertex normals, land colors, water coverage and the TriangleMesh contact structure originate from these triangles.

Runtime flight rendering selects five cached layers at 0, 8, 22, 65 and 120 km: 512×256, 256×128, 128×64, 64×32 and 64×32. The first layer includes local launch rings. Altitude hysteresis limits switching near a boundary. Only the rendered layer changes; contact and swept impacts use LOD 0. The editor's explicit flight previews show these same layers. Map and moon callers can continue to request the full shared preview mesh.

Flight tests contact against the actual rotating triangles. The HUD separates ground clearance from sea-level altitude. Launch grading keeps the ground below the level facility deck. Ocean geometry terminates at sea level; recovered vessels use entry momentum, water drag and buoyancy after splashdown. Underwater seabed meshes are not implemented.

## Surface detail and saving

**Bake & Save Planet + Moons** writes compressed terrain resources in a `baked/` directory beside the planet resource, and independently saves its moons. The bake contains all five meshes and a preview referring to LOD 0. Collision is generated from the saved full-detail mesh. Geometry/color settings, generator version and engine version form the bake signature; shaping changes invalidate a stale bake.

Each bake contains two mipmapped 2048×1024 maps shared by every render LOD:

- Linear land color and water coverage in an RGBA half-float surface texture.
- Body-space surface normals in RGB and normalized elevation in A, using an RGBA8 topography texture. This adds about 10.7 MiB including mipmaps per newly baked body.

Topography uses finite differences of the already sampled elevation field. It adds no extra elevation sampling pass and no per-frame terrain generation. Normals for submerged samples remain spherical. The shader samples this map to preserve smaller land slopes and ridge lighting on lighter meshes; it does not add triangles or displace the contact surface. Mipmaps, seam-correct derivatives and distance filtering prevent unresolved detail from shimmering. Existing body-space material grain continues to fade with pixel footprint.

Version 8 bakes remain usable when the new shaping controls are neutral, preserving cached geometry and colors during loading. Their original mesh normals remain the runtime fallback. Preview refinement can add detailed normals in the editor; the next save persists the new topography map in a version 9 bake. Legacy bakes with edited shaping settings are rejected.

Live edits do not modify the active flight world until saved and reloaded. Source saves do not update a previously exported game pack; export and package a release to include them in `play.sh` builds.

## Near-surface ocean

Below 25 km, `scripts/ocean_patch.gd` draws the StayAtHomeDev "infinite ocean" (`assets/shaders/ocean.gdshader`) at true sea level. The tutorial's uniforms and defaults, NoiseTexture2D settings, wave displacement within 85 m of the craft (`ocean_pos`), fresnel albedo, Beer's-law depth colour, screen refraction, edge foam, normal maps and specular all carry over. Planet adaptations:

- Waves are keyed to a planet-fixed tangent frame instead of `world_pos.xz`, so they do not slide with the camera.
- The mesh is one disc of geometric rings (~0.25 m cells under the craft), wrapped onto the sphere and scaled to reach past the horizon (8–220 km). The tutorial's tile-seam stitching is therefore not needed.
- Displacement is centred on sea level, so the mean surface matches splashdown.
- Depth is linearised with the inverse projection; the tutorial's fixed near/far planes do not fit a 0.5 m–1000 km camera.
- Distant water uses the same atmospheric scattering as the terrain.
- Swell: the tutorial's ridged 20 m wave texture tiles visibly at scale. Four swell octaves (97 m to 3.7 km, up to 6 m) use a separate smooth noise texture, rotated and drifting. Each texture tile spans four octave scales (`swell_repeat`), so the 97 m octave repeats only every ~390 m; with a few waves per 97 m tile it read as a lattice of converging lines and blobs. They displace the mesh where its cells resolve them, and always light the surface from their height gradient (slopes are exaggerated only beyond 300 m, so distant swell stays visible). Each octave and the tutorial detail vary regionally (`sea_state`) between calm and rough patches, so no layer repeats evenly. Swell shrinks with seabed depth, and the tutorial's fine detail fades once it is smaller than a pixel.
- Beyond 1.5–4 km the depth buffer cannot resolve metres of water, so water thickness comes from the known seabed shape along the view ray. Beyond 15 km, water is discarded over mapped land, because low-detail flight terrain sags below sea level along coasts.

The tutorial needs something beneath the water for depth colour, refraction and foam. Within the patch, the terrain shader turns water pixels into a sandy seabed that shelves from `seabed_shallow_m` (2.5 m) to `seabed_depth_m` (70 m) and writes that depth. Coarse coastal triangles otherwise lift water toward the hills. Between 18 and 25 km the patch cross-fades back to the terrain's own water (`fade`); the seabed and the patch's shallows only appear above 90% fade, so the old water never shows tinted through them. The waves are visual only: splashdown contact and buoyancy still use sea level.

## Scope and validation

The globe is a spherical height field. Caves, overhangs, terrain brush painting, streaming and physically simulated erosion are not implemented. Fine surface-normal detail is a shading approximation, while actual hull contact follows the full mesh. Any future local mesh refinement must update rendering and physical contact together.

`tests/test_planet_detail.gd` covers deterministic shaping, finite heights and normals, spherical oceans, launch grading, small-radius worlds and legacy cache compatibility. `tests/test_planet_preview.gd` covers debounce, workers, stale-job rejection, adaptive density, map reuse, inspection views and thread shutdown. Run it with a graphical display to capture the four views in `/tmp/aphelion-planet-view-*.png` and compare full-globe versus adaptive GPU/render CPU timings. Editor persistence tests cover independent planet/moon shaping and saved topography. Existing surface, camera, bake and cloud-editor checks provide broader regression coverage.
