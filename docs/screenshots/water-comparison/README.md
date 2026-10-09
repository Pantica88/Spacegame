# Water visual comparison

Rendered October 7, 2026 with Godot 4.7.2, OpenGL Compatibility, Radeon RX 580. Inputs: `WaterShader.zip` and `InfiniteOcean.zip` from the user's Downloads folder. Game: current workspace ocean shader and WorldView, before any water shading changes for this request.

## Captures

- `scene-comparison.png`: supplied projects' original scenes/cameras alongside an actual game ocean scene. Scene, illumination, and framing differ intentionally; this shows each project's presentation.
- `controlled-comparison.png`: both supplied water materials and the game's OceanPatch in one shared fixture: same reference panorama, sun, camera positions, sandy seabed at -4 m, and partially submerged block. Top row: camera at (0, 5, 22); bottom: (0, 45, 25); both look at (0, 0, -25). FOV and resolution match. Game atmosphere is disabled in this fixture to isolate the water material. Tutorial surfaces use the same 2 km plane; game uses its existing curved ring mesh. Material and wave settings retain their own defaults.
- Individual full-resolution images accompany both contact sheets. `game-scene-overhead.png` provides an additional full-game view.

## What the captures show

The demos are brighter blue/cyan with clear sky reflections. WaterShader has finer, calmer detail; InfiniteOcean has stronger overlapping ripples. The game is substantially darker under the same fixture lighting, with much larger irregular swells and dense surface detail. Some game wave troughs expose the fixture's shallow seabed; these are not shoreline foam. The full-game ocean also looks dark and shows broad, soft wave bands. Its custom sky and atmospheric lighting change the presentation further.

Matching the reference look calls for brighter water and reflection response, less dominant swells, and improved depth/foam blending. These captures do not establish animation quality, performance, or physics correctness.

## Compatibility adaptations

The supplied 2023 demo shaders use implicit screen/depth samplers and outdated depth linearization. Temporary copies explicitly declare these samplers and reconstruct depth with inverse projection for the installed Compatibility renderer. The unadapted version rendered nearly white due to incorrect foam depth; those invalid captures are excluded. Resource paths are rebased for the temporary combined project; panorama images are loaded directly. The original archives and game water shaders are unchanged. Input actions are registered for the demo camera controller.

Temporary runnable comparison project and harnesses: `/tmp/water-comparison`, `controlled.gd`, `native.gd`, and `game-scene.gd`. Controlled runs select `WATER_VARIANT=water-shader`, `infinite-ocean`, or `game`; `OCEAN_CAPTURE_DIR` selects the output folder. The full game capture runs `game-scene.gd` with the game workspace as Godot's project path.

## InfiniteOcean update

`infinite-ocean-update.png` shows the reference, the earlier game shader, and
the revised shader under matching fixture conditions (Godot 4.7.2).
`updated-distance-views.png` shows the full game in the documented Godot 4.5.1
version, with daylight applied after flight synchronization. This version
loads the saved planet bake and activates the near ocean patch; the capture
script explicitly checks patch visibility. The six distance captures span
near surface to 40 km altitude. Full-game lighting and tone mapping differ
from the fixture.

Changes: corrected clockwise ring-mesh winding (the dark appearance came
from lighting its underside); retained dense geometry within 250 m while
stretching outer rings toward the horizon; matched the reference's separate
wave bump texture; reduced large swell amplitudes; filtered the two normal
layers independently; kept CPU wave height parameters synchronized; softened
the old deep-water albedo reduction in the terrain fallback.

Godot 4.5.1 checks passed for all 392,704 ocean triangles, water landing and
buoyancy, launch-island dry ground, and six graphical ocean distance views.
