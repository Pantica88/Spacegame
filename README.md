# APHELION

**Build a rocket. Fly it yourself. Bring something home.**

APHELION is a working title for an original 3D rocket-building game about running the fictional Bluffton Flight Works. This is a playable desktop foundation for a future commercial game, with a compact space program focused on short flights, improving designs, and recovering capsules. It is not ready for a paid Steam release.

Flight and the map now share orbital mathematics, with conic coast paths, eccentricity and period, improved orbital integration, and corrected staged Δv estimates. See [physics conventions, equations, and limits](docs/PHYSICS.md).

The orbital map now supports [maneuver planning](docs/ORBITAL_MAP.md#maneuver-planning): click a future coast point and choose **Create plan** or **Warp here**. Drag the plan's six direction symbols to adjust the burn and compare the purple trajectory with the current coast. The panel shows burn timing, delta-v, estimated fuel use, and planned apsides. This source feature models one manual burn around the home planet; see the [trajectory planning scope](docs/FLIGHT_SYSTEM_PLAN.md).

Verdant has sunlight-dependent atmospheric scattering: blue daylight, warm low-angle light, and a dim night side. The sky, terrain haze, and scene light share one sun direction. See [atmosphere rendering](docs/ATMOSPHERE.md).

## Play

Version 0.3.26 is the current Linux development build. Run `./play.sh` from this workspace to launch it. Windows exports are deferred until the final release stage, so the familiar Windows ZIP may represent an earlier development checkpoint. Previous physical exports remain preserved under `build/archive`. The window title and game header display **v0.3.26**. The launch site is on the equator; the planet retains its original north–south rotation axis.

To edit the game or run from source:

Use **Godot 4.5.1 built with double precision** (`precision=double`; GDScript, no .NET required). Official downloads are single precision only. Build the editor and export templates from source as described in [the multi-planet roadmap](docs/MULTI_PLANET_ROADMAP.md#1-double-precision-godot-build); the build includes a required engine patch. The official [4.5.1 download](https://godotengine.org/download/archive/4.5.1-stable/) still runs the project, but its float32 coordinates fail several precision-sensitive tests and reject bakes made by the double build.

1. Open Godot, choose **Import**, and select `project.godot` in this folder.
2. Wait for the initial asset import.
3. Press **F5** to run the game. **F6** runs the currently open scene; open `scenes/main.tscn` before using it.
4. In the workshop, configure a rocket, select a contract, and launch.

On Linux, you can also use:

```bash
./tools/run.sh
# If Godot is outside PATH:
GODOT_BIN=/path/to/godot ./tools/run.sh
```

Inspect the planet and launch site without a rocket or gravity:

```bash
./hover.sh
```

**WASD** moves the free camera, **Q/E** moves down/up, and holding **right mouse** lets you look around. Use **− / =** (or numpad **− / +**) to adjust movement speed; hold **Shift** for 10× speed or **Ctrl** for fine movement. **Scroll up/down** scrubs time forward/backward by 1/96 of a planetary day per notch, changing sunlight and moon positions while keeping the camera anchored to the terrain. Time stays at the selected moment; **T** restores the starting time. **R** resets to the launch pad, **H** hides the controls, and **Esc** exits. The camera stops when you release movement keys and can pass through scenery. This standalone preview uses the game's terrain, water, clouds, atmosphere, and moons without changing your craft or progress. In Godot, open `scenes/hover_preview.tscn` and press **F6**.

Try the atmospheric plasma without launching a flight:

```bash
./test-plasma.sh
```

The preview starts at maximum airspeed (2,000 m/s) and 100% heat glow with automatic tumbling. Reset restores these maximum values. Use the sliders for airspeed, travel direction, heat, and turn rate; choose a rocket, capsule, or boosted rocket. **WASD / QE** turn the vessel manually, **T** toggles automatic tumbling, **Space** pauses, and **R** resets. Right-drag to orbit the camera and scroll to zoom. Travel direction changes movement independently of the nose; flames stream opposite that motion. Heat is held steady for visual inspection. In Godot, open `scenes/plasma_preview.tscn` and press **F6**.

The standalone planet editor runs as its own scene:

```bash
./tools/run.sh res://scenes/planet_editor.tscn
```

`tools/run.sh` (and every script that uses it, including `tools/check.sh`) picks Godot in this order: `GODOT_BIN`, the double-precision editor at `~/godot-double/src/bin/godot.linuxbsd.editor.double.x86_64`, `godot` or `godot4` on `PATH`, then the official editor downloaded during development to `/tmp/aphelion-godot/`. `./perf.sh` uses the same order.

## Controls

| Input | Action |
| --- | --- |
| W / S | Pitch |
| A / D | Yaw |
| Q / E | Roll |
| Shift / Ctrl | Increase / decrease throttle |
| Z / X | Full throttle / cut throttle |
| Space | Ignite or advance staging |
| T | Toggle stability assistance |
| M | Toggle orbital map |
| H | Hide / show the in-game HUD for a clean view |
| . (period) | Cycle high-speed warp: 1×, 5×, 10×, 50×, 100×, 1,000×, 10,000×, 100,000×; automatically selects physical warp when high-speed warp is unavailable |
| Alt + . (Command + . on macOS) | Cycle physical warp: 1×, 2×, 3×, 4×, including under thrust |
| Esc | Pause |
| F11 | Toggle fullscreen |
| Right mouse drag | Orbit the camera |
| Mouse wheel | Zoom |

Start with a modest design and keep it upright for your first launch. Watch fuel, speed, and altitude, then cut thrust and separate the capsule using staging. Deploy its parachute while descending below 2.5 km and under 180 m/s. An orbit requires sideways speed as well as height.

## Your first flights

Use **two tanks, the Sparrow engine, fins on, boosters off**, with stability assistance on and time at **1×**. This is the starter design used in the flight tests.

For **A little altitude**, launch straight up with **Space** at full throttle. At about **1.2 km altitude**, press **Space** again to separate the capsule. It will coast higher and then fall. Once descending below **2.5 km** and at **180 m/s or less**, activate the parachute stage with **Space**. Allow the parachute to carry the capsule to the surface.

For **Around we go**, use **eight tanks, the Kestrel engine, and paired boosters**. The automated flight test reaches orbit with this design and continuous steering corrections:

1. Launch upright at full throttle and separate the boosters when they run out of fuel.
2. Starting at **3 km**, gradually turn east toward the horizon, reaching a horizontal attitude near **63 km**. Stability assistance stops rotation when you release the controls; continue making small steering corrections.
3. Watch **APOAPSIS**, the predicted highest point of your coast, and press **X** when it reaches about **130 km**. Coast toward it while holding an eastward horizontal heading.
4. As your upward **VERTICAL SPEED** falls below about **50 m/s**, press **Z** to burn at full throttle. Keep the engine attached and maintain the horizontal heading.
5. Watch **PERIAPSIS**, the lowest point of the coast. When it rises above **90 km** and the orbit mission completes, press **X**. Press **M** to view the predicted coast around the planet.

| Contract | Completion condition |
| --- | --- |
| A little altitude | Reach 1 km and land safely |
| The sky gets quiet | Reach 12 km and land safely |
| Around we go | Establish a closed orbit with periapsis at least 90 km; recovery is optional |

Manual steering takes practice. The map predicts a coast without thrust or atmospheric drag. A capsule separated in a stable orbit has no engine to bring it back down; preserve the engine and remaining fuel if you want to attempt a later return.

## Included

- A 3D workshop with up to 16 fuel tanks, three engines (Sparrow, Kestrel, Titan), boosters, and fins.
- A stylized planet and launch site, a following flight camera, and an orbital map.
- A simulation of central gravity, thrust, fuel use, drag, staging, and capsule recovery.
- Three starter contracts, flight results, and saved program progress.
- Throttle-responsive engine audio, including Titan’s supplied recording and an original Sparrow sound with ignition on launch, sustained restarts from second 1, and smooth volume-only thrust control, sound toggle, pause menu, and fullscreen toggle.
- Windows x86-64 and Linux x86-64 export presets.

The physics and planetary scale are tuned for a game. They are not an engineering simulator. Assembly uses configurable stacks; a general-purpose attachment editor, multiple celestial destinations, a complete campaign, controller support, and production QA remain future work.

Version 0.1.1 replaces the overlapping ground and ocean geometry with one continuous planet surface, addressing the broken geometry reported near 3.7 km. It also removes the old surface switch at 6 km so ascent, descent, and lateral flight use the same terrain. The saved [before](docs/screenshots/rendering-fix/before-3700m.png) and [after](docs/screenshots/rendering-fix/after-3700m.png) renders show the 3.7 km comparison. The next milestone is a guided first recovery mission, clearer staging, and a small craft library; see the [playtest plan](docs/PLAYTEST_PLAN.md).

Program progress and your latest design are stored in Godot's `user://profile.json`; use **Project → Open User Data Folder** in the editor to find it. An active flight is not saved for later resumption.

## Validate and export

```bash
./tools/check.sh
```

Checks import the project, exercise assembly, launch, ascent, map, pause, and workshop return, then run flight model, recovery/reward/retry/crash, saved-profile, and closed planet surface tests. They use temporary save folders so they do not overwrite your progress. They require Bash, `rg`, and Godot.

Run the rendering regression on a graphical desktop, without `--headless`:

```bash
./tools/run.sh --script res://tests/test_rendering.gd
```

Rollout displays **Preparing launch…** before rebuilding the craft, then prepares terrain detail levels, flight effects, cloud shader variants, map views, and a reusable impact pool while simulation is paused. Run `./tools/run.sh --script res://tests/test_launch_warmup.gd` on a graphical desktop to check that these views render under the cover and the launch state is restored. Its headless mode checks resource readiness and state restoration without compiling GPU shaders.

It compares rendered images near the reported 3.7 km altitude and across the old 6 km boundary during ascent, descent, and lateral movement. It also saves camera and altitude captures under the temporary directory `aphelion-render-regression` for visual review. These checks supplement manual playtesting.

Install matching templates through **Editor → Manage Export Templates** in Godot. Open **Project → Export**, select **Windows Desktop** or **Linux**, and export a release build. Create the destination folders first. For command-line exports:

```bash
mkdir -p build/0.3.18/linux
./tools/run.sh --headless --export-release "Linux" build/0.3.18/linux/APHELION.x86_64
# Export Windows only when preparing the final release candidate.
python3 tools/package_builds.py
```

The Python 3.9+ packaging tool reads `config/version` from `project.godot` and defaults to `build/<version>`; without a version it uses `build`. Publication updates the familiar launch paths and writes `build/LATEST` last. Use `--no-update-current --build-dir <path>` to package another directory without selecting it, or `--check-only` to validate inputs without writing packages. It creates Linux, Windows, and source ZIPs, verifies their CRCs and the Linux executable permission, and writes `SHA256SUMS.txt`. Source packages exclude build outputs, caches, repository internals, and export credentials. Keep export paths and the project version aligned when preparing another release, and export into a new version directory if an older build may still be running.

Distribute each executable with its neighboring `.pck` file and notices. Windows resource editing and code signing are disabled in this initial preset to support exports from Linux without extra tools. Configure release metadata and signing as appropriate before distribution. Neither preset uploads anything to Steam.

Source validation for 0.1.1 passes 163 flight simulation checks, 136 profile persistence checks, 18 closed planet surface checks, the UI and recovery/retry scenarios, and four graphical rendering regression comparisons. The rendering run also produced 28 camera and altitude captures; representative views were reviewed through 100 km. Both 0.1.1 desktop exports succeeded. The standalone Linux build rendered 180 frames on an AMD Radeon RX 580 and exited successfully without runtime errors; it emitted an ObjectDB instance-leak warning during the forced exit. The Windows build has not been run on Windows. Wider hardware and player testing remain necessary.

See [the Steam roadmap](docs/STEAM_ROADMAP.md) for product scope and release gates, [the multi-planet roadmap](docs/MULTI_PLANET_ROADMAP.md) for the technical path to visiting other bodies, and [third-party notices](THIRD_PARTY_NOTICES.md) for the engine dependency.

Release publication checks: `python3 tests/test_packaging.py`. For a graphical check of the actual Linux package, run `./play.sh --audio-driver Dummy --script "$PWD/tests/test_packaged_rendering.gd"` with isolated XDG data/config/cache directories and `APHELION_RENDER_DIR` pointing to a temporary capture directory. This checks a full ascent from 3.7 to 30 km and compares frames across the former 6 km boundary.

Version 0.1.3 removes the circular ocean/cloud mask around the launch island: local water shares the global ocean shading, clouds cover both consistently, and the surrounding coastline blend has an irregular boundary. Packaged Linux views were reviewed at 48.56 and 100 km; all four 6 km continuity comparisons pass.

Version 0.1.4 removed the painted cloud patches from the planet surface. Flight now has a separate lightweight cloud layer with shaded undersides, sunset lighting and atmospheric haze; see [atmosphere rendering](docs/ATMOSPHERE.md).

Version 0.2.0 adds **Parts** and **Stages** tabs in the workshop. The assembly list shows the capsule, its integrated decoupler, individual fuel tanks, engine mount, and paired side attachments. Add/remove tanks (up to 16), swap engines, and attach/remove boosters or fins while the 3D preview and engineering report update. This remains a guided axial builder; arbitrary attachment graphs and multiple liquid stages are future work.

The workshop is a separate indoor location with a larger detailed assembly hall; **Roll out to pad** switches to the outdoor launch site. **Expand workshop** hides the side panels for a wider work area; **Show panels** brings them back. Right-drag over the rocket or empty assembly area to orbit freely through all angles, middle-drag to pan, and scroll to zoom. **Fit rocket** frames the whole stack; rockets over four tanks gain floor clearance and camera space automatically. **View rocket…** selects front, back, left, right, top, or bottom views; **Reset view** restores the starting angle and zoom. The floor and nearby walls cut away when viewing from beneath or outside the hall.

The parts catalogue provides **Separator–1** and **Booster–1** separately. Choose **Single, 2, 4, 6, or 8** in the symmetry selector, then drag separators onto the fuel-tank surface. The pointer chooses a continuous angle and height; orbit the workshop camera to reach the back of a tank. Each 1.4 m separator must fit within its tank and avoid existing mounts. Boosters snap to free separators with matching symmetry; overlapping boosters are rejected. Each mount is independently selectable, movable and removable together with its booster. Booster staging ignites/releases all installed boosters, retaining separator hardware on the core. Legacy paired-booster saves remain compatible.

Each separator adds **12 kg**. Each booster adds **90 kg dry mass, 320 kg fuel, and 22 kN thrust**. Mass and fuel affect weight, thrust-to-weight ratio and acceleration; actual attachment positions affect center of mass, rotational inertia, and off-axis thrust torque. Hover the launch-mass readout for installed counts, dry mass and lateral center-of-mass offset.

With boosters attached, choose simultaneous ignition or **Boosters first, then core**. The numbered stage preview lists each Space action. Booster-first launches preserve liquid fuel until you press Space to jettison the boosters and ignite the core; the final Space action separates the capsule. The HUD and flame effects follow the selected sequence, and Save design persists it. The thrust/weight and delta-v estimates account for the selected ignition order. Wait for solid booster burnout before staging for the intended performance estimate.

Version 0.2.1 replaces the Parts controls with a draggable catalogue. Each card includes a part illustration, description, and specifications. Drag onto a compatible mount beside the 3D rocket; matching mounts highlight during the drag. Engine drops replace the engine, tank drops extend the stack, and side parts attach symmetrically. Right-click a mount to remove a tank or side attachment. One tank and an engine are retained for a flight-ready core. Wrong mounts, duplicate side attachments, and tanks beyond the supported tank limit reject drops without changing the design.

## Planned assembly and staging expansion

The agreed [rocket assembly and staging plan](docs/ROCKET_ASSEMBLY_AND_STAGING_PLAN.md) records the direct 3D building workflow, full staging mechanism, implementation workstreams, and first playable acceptance criteria. It describes planned work beyond v0.2.1.

## Connected assembly checkpoint — 0.3.0

**New** starts from a recovery capsule. Drag the capsule decoupler, tanks, and an engine onto their connection points to build a launch core. Drops show a translucent preview; incomplete builds can be saved but cannot roll out. Existing designs migrate to connected parts with stable identities. Select a tank to rotate it with **R**, duplicate with **Ctrl+D**, or remove with **Delete**. **Undo/Redo** (also Ctrl+Z / Ctrl+Y) covers part and stage edits. Right-click connection points to remove the corresponding attachment.

The **Stages** column on the right replaces ignition presets. Drag an action to another group, drag a stage header or use its arrows to reorder groups, and add or delete empty groups. New installed stageable parts create actions automatically. Hovering an action highlights its target; capsule separation highlights the discarded lower assembly. The **Flight checks** tab contains the mission selector and engineering report. The flight HUD lists completed and upcoming stages.

Space validates the entire next group before firing it: separation executes before ignition, and chute deployment executes last. An unsafe parachute action holds the whole group without side effects; retry Space when safe. Control remains with the capsule. Impossible discarded-engine ignition and incomplete craft block rollout. Active-core separation is a warning, allowing an intentional separation; the detached assembly retains fuel, thrust, mass and ballistic motion. Parachutes deploy through the staging sequence with Space.

This is an implementation checkpoint, not completion of the full plan. Assembly remains a single axial core with paired boosters and four fins. Freeform subassembly movement, selectable radial symmetry, a fully generic multi-engine flight model, and complete per-part editing remain outstanding. See the saved plan's progress section.

Version 0.3.1 corrects the assembly interaction. **New** opens an empty indoor hangar with only the capsule available. Drag the capsule into the bay, then attach each newly unlocked part by moving it near a compatible surface. The held 3D part is red away from a valid connection, snaps and turns green near one, and connects only when released while green. Permanent plus-sign targets have been removed. Rollout moves the completed vehicle to the outdoor launch pad.

Version 0.3.2 makes the command capsule the fixed assembly root. Its first valid drop chooses its height while constraining it to the bay centerline. That height is saved with the design, and every axial part added afterward extends below the capsule without recentering the camera or moving the capsule.

Version 0.3.3 lets players grab an installed part and drag it back onto the parts catalogue to remove it. Removal updates associated stage actions and supports undo. Fins can now snap to either the command capsule or any installed fuel tank; capsule-mounted fins remain with the capsule after separation.

Version 0.3.4 replaces generic drag volumes with glowing procedural models of the actual capsule, decoupler, tanks, engines, booster pair, and fin set. Returning a part to inventory now clears its selection, drag ghost, and stage-hover highlight immediately.

Version 0.3.5 adds visible return dragging. Grabbing an installed part creates a full 3D copy that follows the pointer, glows orange while moving through the hangar, turns green over the catalogue, and clears after a successful drop or cancellation.

Version 0.3.6 makes installed-part dragging dual-purpose. Release near a compatible craft surface to reposition the part, or release over the catalogue to remove it. Fins can move between capsule and tank surfaces, and the capsule can be repositioned vertically while remaining constrained to the assembly centerline.

Version 0.3.7 removes the visible square selection handles. Selecting an installed part now draws a thin mint silhouette around its real procedural model. The remaining legacy cylinder and cone selection volumes have been replaced, including tanks, engines, boosters, fins, the decoupler, and capsule.

Version 0.3.8 applies attachment-graph subtree behavior. Selecting a part highlights that part and every descendant connected beneath it. Dragging moves the same complete subassembly preview. Returning its root to the catalogue removes the entire subassembly and all associated stage actions; Undo restores the group.

Version 0.3.9 expands each installed part's invisible pointer target across its visual model, with separate targets for paired boosters and fins so they do not obstruct the center stack. Hovering a part outlines its complete affected subassembly in mint; selecting it changes the same outline to orange.

Version 0.3.10 removes powered exhaust from engine editor ghosts. A freely dragged engine shows its clean bell geometry; reaching a valid snap surface turns it green, places it in the installed orientation, and adds the feed skirt and mounting collar used by the assembled core.

Version 0.3.11 keeps the decoupler pointer region centered on its rendered model as fuel tanks alter the assembly's local layout. Its thin visible strip also takes pointer priority where neighboring full-model hit regions overlap.

Version 0.3.12 allows fins to slide vertically along a capsule or fuel tank while held. The selected surface height is saved with the attachment and restored with the craft. Capsule-mounted fins tilt to follow the command capsule's tapered hull in the snap preview and assembled model.

Version 0.3.13 makes model-edge highlights camera-distance aware. Thin parts such as the capsule decoupler retain a readable mint or orange silhouette when the workshop camera is zoomed out, with a capped scale that keeps close-up outlines precise.

Version 0.3.14 resolves hover centrally when part hitboxes overlap at distant zoom. The closest visible part wins, with the narrow decoupler ring prioritized near its center. Left-clicking unused assembly space clears the current part selection.

Version 0.3.15 aligns the fin ghost's origin with its real attachment line, removing the vertical jump when a free drag becomes a valid snap. Capsule-mounted fins now flare in the correct direction along the tapered hull.

Version 0.3.16 corrects capsule fin geometry after visual review. Capsule-mounted fins use a shorter, vertically inverted profile that follows the widening hull downward, while tank fins retain their full upright shape. Free, snapped, selected, and installed fin models share the same centered mounting offset.

Version 0.3.17 makes valid snap ghosts use the same depth occlusion as installed parts. Portions of fins buried inside the capsule or tank no longer render through the hull in green, so the snap preview matches the visible final placement. Free invalid ghosts remain visible through the craft while being moved.

Version 0.3.18 gives the planet slope-dependent exposed rock, stable ground material detail, sharper coasts and sky fill lighting. Flight and the orbital map share the material; terrain collision geometry is unchanged.

The planet editor supports **Add moon** and **Remove moon**. Use the body selector beneath the planet list to edit the planet or one of its moons. Each moon has its own live terrain preview, seed, relief, continents, ocean, colors, size, atmosphere and orbit settings. **Bake & Save Planet + Moons** saves the complete selected planet system; **Reset** reloads it from disk. New moons start as dry, airless rocky bodies. Saved planets and moons appear in the orbital map with their terrain, labels, selectable focus, and orbit lines. Moon orbits follow their parent planet using the saved distance, period and phase. Show orbit line controls the orbit ring; the body remains visible. Saved moons also render in the flight view with the same terrain and orbit timing as the map. Spacecraft feel each moon's saved gravity and can orbit, collide with, crash into, or land safely on its moving terrain.

The editor's **Clouds** tab paints reusable formation tiles directly onto the globe: cumulus, cloud streets, stratocumulus, overcast, storms, and wispy layers. Soft brush edges blend overlapping cloud families in the volume renderer. Set the brush size, opacity, softness, rotation, and tile variant; left-drag paints, right-drag orbits, and **Ctrl+Z / Ctrl+Shift+Z** undo and redo whole strokes. Capture a painted region into your tile library to reuse it on other planets. **Bake & Save Planet + Moons** persists each body's weather for the editor and flight view. See [cloud painting](docs/CLOUD_PAINTING.md) for controls and details.

## Asset viewer and reference canister

**Gyro–1 reaction wheel** is available in the Parts catalogue after placing a capsule. Stack its decoupler-sized rings above the fuel tanks for faster pitch, yaw and roll. Each adds 50 kg and 12 kN·m of torque per axis; its torque ends when the wheel separates from the controlled craft. [Model and gameplay details](assets/models/gyro_1/README.md).

Run `./view-assets.sh` (or `./tools/run.sh res://scenes/asset_viewer.tscn`) to browse the Canister–1, Explorer–1 and Atlas–1 models. The viewer includes a component list with visibility checkboxes, selected-component isolation, exploded assembly, turntable rotation, zoom and front/top/bottom views.

[Canister–1 asset details](assets/models/canister_1/README.md): reference-proportioned GLB with nine named components and 49,968 triangles. It supplies the gameplay fuel-tank visual, fitted to the existing attachment envelope, and has an Explorer–1-style standalone preview in `scenes/canister_1_preview.tscn`.

Version 0.3.19 adds **Asset Viewer** to the game header and pause menu. Browse the canister, capsule and decoupler, then choose **Back to game** or press **Esc**. Opening the viewer preserves the current craft and pauses flight.

Parachute–1 is available in the workshop **Parts** menu after placing a capsule. Drag it onto the capsule top mount. Activate the parachute stage with **Space** during safe descent to release the tethered nose cap and inflate the canopy; the opened lower housing stays attached and visible. The module adds 18 kg and persists in saved craft. [Parachute–1 asset and animation details](assets/models/parachute_1/README.md).

The Clouds tab also includes a **Random weather generator** with repeatable seeds, formation counts, and mixed or single-category generation. **Mushroom clouds** have a rising stem and rounded cap; use their brush or generate a mushroom field. Generation is undoable and its result remains editable.

The Clouds tab's **Sky dynamics** section sets per-planet wind speed and heading (the whole weather map drifts around the globe), billow evolution (cloud shapes slowly boil and reform), procedural coverage and cloud density. A preview time-lapse slider speeds this up in the editor only. Clouds are ray-marched at half resolution in an offscreen pass and upsampled with opacity weighting; only pixels where a nearby craft sits inside the cloud layer are integrated at full resolution against the depth buffer, so hull edges stay sharp. The saved time pays for sun shadowing: each visible cloud sample looks toward the sun through its own formation, so towers and anvils shade their stems and bases, with a two-lobe scattering phase for silver linings and a multiple-scattering term that keeps shadowed cores grey rather than black. Cellular detail noise gives near clouds rounded, billowing edges.

## Performance lab

Run `./perf.sh` for repeatable gameplay checkpoints, saved baselines, frame/GPU timing reports and screenshots. Use `./perf.sh run --preset quick` for a shorter smoke run. [Setup, scenarios and comparison workflow](docs/PERFORMANCE_LAB.md).
