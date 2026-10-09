# Painting cloud formations

Open the planet editor with `./tools/run.sh res://scenes/planet_editor.tscn` and select the **Clouds** tab. Choose the planet or moon you want to edit. Cloud painting changes that body's weather independently of its terrain and the other bodies in its system.

Choose a formation tile, then left-drag over the globe to paint. Right-drag orbits the camera and the wheel zooms. Each category has four repeatable variants:

| Category | Formation |
| --- | --- |
| Cumulus | Scattered individual cloud puffs with open sky between them |
| Cloud streets | Long rows of cloud puffs |
| Stratocumulus | Broad fields of connected, textured cells |
| Overcast | A dense, continuous cloud deck |
| Storm | Dense storm systems with taller cloud volumes |
| Mushroom clouds | A narrow rising stem under a broad, rounded cap |
| Wispy layer | Thin, cirrus-like streaks and veils |

**Brush radius** controls the area covered, with a radius from 3° to 38° on the body's surface. **Opacity** sets how strongly each stamp adds its formation. **Soft edge** feathers the stamp into surrounding weather, and **Tile rotation** changes the orientation of rows, fronts and wisps. Brush placement follows the sphere, including its longitude seam and poles. Overlapping strokes blend their cloud types and coverage without rectangular tile borders.

Start with a broad, low-opacity stratocumulus or overcast field. Add smaller cumulus patches or storms, vary the tile and rotation, and use **Erase to clear sky** to open gaps. Moderate opacity and a wide soft edge make transitions gradual. The preview and flight view use the same saved weather data and volumetric cloud renderer.

The first paint stroke starts a clear authored weather map. **Clear sky** removes every painted formation. **Procedural** returns the body to its original automatically generated weather. These actions, erasing and whole brush strokes can be undone with **Undo** or **Ctrl+Z** and redone with **Redo**, **Ctrl+Shift+Z** or **Ctrl+Y**.

To reuse a formation you have composed, enter a name under **Your tile library**, choose **Capture a painted region…**, and click the globe. The current radius and rotation determine the captured area. The saved tile becomes the current brush and remains available in **Saved tiles…** across editor sessions and planets. Custom tiles retain the mixture of cloud types; they are stored as image resources in the game's `user://cloud_tiles` directory.

Choose **Bake & Save Planet + Moons** to persist the weather with the planet system. Edited planets, cloud maps, moons and terrain bakes are stored in the game's writable `user://planets` directory, outside the packaged assets. The editor, flight world and planet catalog prefer these saved versions on reload and restart. Saving verifies the cloud pixels before replacing the preview. **Reset** reloads the saved system. A body needs atmosphere height and visual density above zero for clouds to appear; use the **World** tab to change those settings. Painting is a visual weather authoring tool and does not change flight physics or simulate evolving meteorology.

## Random weather

Use **Random Weather** at the top of the Clouds tab to generate an editable weather map. Choose **Mixed cloud types** or a specific category (including mushroom clouds), set **Formations**, and choose **Generate**. The same seed and settings reproduce the same sky. **Randomize** picks a new seed and generates another arrangement. Generation replaces the selected body's weather as one undoable action; paint over the result to refine it, then use **Bake & Save** to keep it.

## Verification

Run the focused checks with an isolated save directory:

```bash
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --headless --script res://tests/test_cloud_painting.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --headless --script res://tests/test_cloud_editor.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --headless --script res://tests/test_cloud_save_persistence.gd
```

The data checks cover repeatable categories and variants, seam and polar painting, feathered edges, bounded overlapping mixtures, erasing, snapshot restoration, custom tile capture, planet/moon persistence and renderer texture binding. The editor checks exercise painting, history, saved custom tiles and the complete Bake & Save weather round trip through the editor itself.

For graphical validation, run the editor test without `--headless` to save `/tmp/aphelion-cloud-editor.png`. The existing cloud rendering regression captures ground, orbit, sunset, night and cloud-volume crossings in `/tmp/aphelion-clouds`:

```bash
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --script res://tests/test_cloud_editor.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --script res://tests/test_cloud_formations.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --resolution 800x450 --script res://tests/test_cloud_horizon.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --resolution 800x450 --script res://tests/test_cloud_distance.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --script res://tests/test_mushroom_clouds.gd
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --disable-vsync --script res://tests/test_clouds.gd
```

Set `GODOT_BIN` to your Godot executable if it is not available on `PATH`.

The authored formation check compares cloud families and mixed coverage from the ground and orbit, and checks continuity when flying through the volume. Its captures are saved to `/tmp/aphelion-authored-clouds`.

The horizon check isolates a far cloud bank at sunset, verifying that grazing rays continue across clear air below the deck instead of cutting clouds off at the inner sphere. It covers painted and procedural traversal; captures are saved to `/tmp/aphelion-cloud-horizon`.

Cloud rendering keeps its full resolution, ray sample budgets, and sample positions. It skips lighting for zero-density samples, unused noise reads at detail-distance endpoints, low-cloud calculations above the deck, and storm calculations outside their painted coverage or tower contour.

To validate a shader optimization, save the original shader before editing, then compare it with the candidate:

```bash
cp assets/shaders/clouds.gdshader /tmp/clouds-reference.gdshader
# Make the shader change, then run:
XDG_DATA_HOME=/tmp/aphelion-weather-check ./tools/run.sh --resolution 800x450 --disable-vsync --script res://tests/compare_cloud_shaders.gd -- /tmp/clouds-reference.gdshader
```

The comparison checks every pixel across saved, low, storm, mixed, clear, and procedural weather at five altitudes, with star animation frozen. It allows at most one 8-bit color level of rounding difference and reports median GPU frame times. Run it without other GPU workloads; timings depend on the scene and hardware.

The distance check verifies clouds beyond 160 km and stable nearby-cloud lighting when the empty part of a ray changes length. Cloud sampling covers the full visible shell within a bounded sample budget; lighting is evaluated at each cloud sample.

Authored weather now caches nonzero RGB/alpha occupancy and conservative filtered
direction bounds. Empty maps hide the cloud pass; edits, erasing, restore and load
invalidate the cache. Sparse or regular-only maps can skip proven-empty rays and
sample intervals while retaining the original integration grid. Dense maps and
very distant cameras keep the original traversal. Procedural weather is unchanged.

See [cloud optimization measurements and validation](CLOUD_OPTIMIZATION.md) for
timings, paired images, bounds details, regression checks and reproduction commands.
The focused cache regression is `tests/test_cloud_occupancy.gd`; the expanded
before/after image harness is `tests/compare_cloud_occupancy.gd`.
