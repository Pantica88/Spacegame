# APHELION

**Build a rocket. Fly it yourself. Bring something home.**

APHELION is a working title for an original 3D rocket-building game about running the fictional Bluffton Flight Works. This is a playable desktop foundation for a future commercial game, with a compact space program focused on short flights, improving designs, and recovering capsules. It is not ready for a paid Steam release.

Flight and the map now share orbital mathematics, with conic coast paths, eccentricity and period, improved orbital integration, and corrected staged Δv estimates. See [physics conventions, equations, and limits](docs/PHYSICS.md).

Verdant has sunlight-dependent atmospheric scattering: blue daylight, warm low-angle light, and a dim night side. The sky, terrain haze, and scene light share one sun direction. See [atmosphere rendering](docs/ATMOSPHERE.md).

## Play

Version 0.3.18 is the current Linux development build. Run `./play.sh` from this workspace to launch it. Windows exports are deferred until the final release stage, so the familiar Windows ZIP may represent an earlier development checkpoint. Previous physical exports remain preserved under `build/archive`. The window title and game header display **v0.3.18**.

To edit the game or run from source:

Use **Godot 4.5.1 Standard** (GDScript; no .NET required). [Download the tested version](https://godotengine.org/download/archive/4.5.1-stable/).

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

The standalone planet editor runs as its own scene:

```bash
./tools/run.sh res://scenes/planet_editor.tscn
```

The script can use the temporary editor downloaded during development at `/tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64`. Files in `/tmp` may be removed by the operating system; keep your own Godot copy for future development.

## Controls

| Input | Action |
| --- | --- |
| W / S | Pitch |
| A / D | Yaw |
| Q / E | Roll |
| Shift / Ctrl | Increase / decrease throttle |
| Z / X | Full throttle / cut throttle |
| Space | Ignite or advance staging |
| P | Deploy parachute when conditions permit |
| T | Toggle stability assistance |
| M | Toggle orbital map |
| . (period) | Cycle time acceleration: 1×, 3×, 8× |
| Esc | Pause |
| F11 | Toggle fullscreen |
| Right mouse drag | Orbit the camera |
| Mouse wheel | Zoom |

Start with a modest design and keep it upright for your first launch. Watch fuel, speed, and altitude, then cut thrust and separate the capsule using staging. Deploy its parachute while descending below 2.5 km and under 180 m/s. An orbit requires sideways speed as well as height.

## Your first flights

Use **two tanks, the Sparrow engine, fins on, boosters off**, with stability assistance on and time at **1×**. This is the starter design used in the flight tests.

For **A little altitude**, launch straight up with **Space** at full throttle. At about **1.2 km altitude**, press **Space** again to separate the capsule. It will coast higher and then fall. Once descending below **2.5 km** and at **180 m/s or less**, press **P**. Allow the parachute to carry the capsule to the surface.

For **Around we go**, use the same design. The automated flight test reaches orbit with the following ascent profile and continuous steering corrections:

1. Launch upright at full throttle. Watch **APOAPSIS**, the predicted highest point of your coast, and press **X** when it reaches about **45 km**.
2. Coast upright until your actual **ALTITUDE** exceeds **18 km**, the top of the atmosphere.
3. Use **D** to turn toward the horizon. Release it as the attitude instrument approaches **0° UP**, and use small **A/D** taps to stay horizontal. Stability assistance stops rotation when you release the controls.
4. As your upward **VERTICAL SPEED** falls below about **70 m/s**, press **Z** to burn at full throttle. Keep the engine attached and maintain a horizontal heading.
5. Watch **PERIAPSIS**, the lowest point of the coast. When it rises above **18 km** and the orbit mission completes, press **X**. Press **M** to view the predicted coast around the planet.

| Contract | Completion condition |
| --- | --- |
| A little altitude | Reach 1 km and land safely |
| The sky gets quiet | Reach 12 km and land safely |
| Around we go | Establish a closed orbit with periapsis at least 18 km; recovery is optional |

Manual steering takes practice. The map predicts a coast without thrust or atmospheric drag. A capsule separated in a stable orbit has no engine to bring it back down; preserve the engine and remaining fuel if you want to attempt a later return.

## Included

- A 3D workshop with one to four fuel tanks, three engines (Sparrow, Kestrel, Titan), boosters, and fins.
- A stylized planet and launch site, a following flight camera, and an orbital map.
- A simulation of central gravity, thrust, fuel use, drag, staging, and capsule recovery.
- Three starter contracts, flight results, and saved program progress.
- Procedural engine audio, sound toggle, pause menu, and fullscreen toggle.
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

See [the Steam roadmap](docs/STEAM_ROADMAP.md) for product scope and release gates, and [third-party notices](THIRD_PARTY_NOTICES.md) for the engine dependency.

Release publication checks: `python3 tests/test_packaging.py`. For a graphical check of the actual Linux package, run `./play.sh --audio-driver Dummy --script "$PWD/tests/test_packaged_rendering.gd"` with isolated XDG data/config/cache directories and `APHELION_RENDER_DIR` pointing to a temporary capture directory. This checks a full ascent from 3.7 to 30 km and compares frames across the former 6 km boundary.

Version 0.1.3 removes the circular ocean/cloud mask around the launch island: local water shares the global ocean shading, clouds cover both consistently, and the surrounding coastline blend has an irregular boundary. Packaged Linux views were reviewed at 48.56 and 100 km; all four 6 km continuity comparisons pass.

Version 0.1.4 removes the painted cloud patches from the planet surface. A separate cloud layer is deferred to a future update.

Version 0.2.0 adds **Parts** and **Stages** tabs in the workshop. The assembly list shows the capsule, its integrated decoupler, individual fuel tanks, engine mount, and paired side attachments. Add/remove tanks (one to four), swap engines, and attach/remove boosters or fins while the 3D preview and engineering report update. This remains a guided axial builder; arbitrary attachment graphs and multiple liquid stages are future work.

With boosters attached, choose simultaneous ignition or **Boosters first, then core**. The numbered stage preview lists each Space action. Booster-first launches preserve liquid fuel until you press Space to jettison the boosters and ignite the core; the final Space action separates the capsule. The HUD and flame effects follow the selected sequence, and Save design persists it. The thrust/weight and delta-v estimates account for the selected ignition order. Wait for solid booster burnout before staging for the intended performance estimate.

Version 0.2.1 replaces the Parts controls with a draggable catalogue. Each card includes a part illustration, description, and specifications. Drag onto a compatible mount beside the 3D rocket; matching mounts highlight during the drag. Engine drops replace the engine, tank drops extend the stack, and side parts attach symmetrically. Right-click a mount to remove a tank or side attachment. One tank and an engine are retained for a flight-ready core. Wrong mounts, duplicate side attachments, and tanks beyond the four-tank limit reject drops without changing the design.

## Planned assembly and staging expansion

The agreed [rocket assembly and staging plan](docs/ROCKET_ASSEMBLY_AND_STAGING_PLAN.md) records the direct 3D building workflow, full staging mechanism, implementation workstreams, and first playable acceptance criteria. It describes planned work beyond v0.2.1.

## Connected assembly checkpoint — 0.3.0

**New** starts from a recovery capsule. Drag the capsule decoupler, tanks, and an engine onto their connection points to build a launch core. Drops show a translucent preview; incomplete builds can be saved but cannot roll out. Existing designs migrate to connected parts with stable identities. Select a tank to rotate it with **R**, duplicate with **Ctrl+D**, or remove with **Delete**. **Undo/Redo** (also Ctrl+Z / Ctrl+Y) covers part and stage edits. Right-click connection points to remove the corresponding attachment.

The **Stages** column on the right replaces ignition presets. Drag an action to another group, drag a stage header or use its arrows to reorder groups, and add or delete empty groups. New installed stageable parts create actions automatically. Hovering an action highlights its target; capsule separation highlights the discarded lower assembly. The **Flight checks** tab contains the mission selector and engineering report. The flight HUD lists completed and upcoming stages.

Space validates the entire next group before firing it: separation executes before ignition, and chute deployment executes last. An unsafe parachute action holds the whole group without side effects; retry Space when safe. Control remains with the capsule. Impossible discarded-engine ignition and incomplete craft block rollout. Active-core separation is a warning, allowing an intentional separation; the detached assembly retains fuel, thrust, mass and ballistic motion. P remains a manual parachute shortcut.

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
