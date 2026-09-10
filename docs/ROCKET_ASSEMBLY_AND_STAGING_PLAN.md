# Rocket assembly and staging plan

Saved: 2026-09-08
Status: implementation in progress. The sections below remain the target; see the checkpoint log for implemented scope.

## Goal and reference

Build a rocket directly in 3D using an illustrated parts catalogue, snapping connections, editable attached parts, and a player-defined staging sequence. The longer-term goal is an original 3D rocket-building and flight game suitable for a future Steam release.

User-provided workflow reference: [Kerbal Space Program Vehicle Assembly Building](https://wiki.kerbalspaceprogram.com/wiki/Vehicle_Assembly_Building). The page blocked automated access during discussion; this plan records the workflow discussed with the user, not a verified summary of that page. Use original assets and presentation.

## Current starting point

Version 0.2.1 has illustrated draggable catalogue cards, labelled drop targets beside the rocket, guided tank/engine/side-attachment configuration, and simultaneous or booster-first ignition presets. The next milestone replaces that limited configuration model with individual connected parts and editable stage actions. Preserve existing flight behavior and the continuous planet renderer while making this change.

## 1. Represent individual parts

- Give every installed part a stable identity, position, rotation, attachment points, and stage assignment where applicable.
- Represent connections between parts explicitly, including parent assemblies and separation boundaries.
- Convert existing saved designs into the new format so current rockets remain usable.
- Save the entire assembly and its staging sequence together.

## 2. Create the assembly workspace

- Keep the 3D rocket central, the parts catalogue on the left, and staging on the right.
- Catalogue cards show a part picture, description, mass, and relevant performance figures.
- Provide categories for command, fuel, engines, structural parts, and aerodynamics.
- Make the rocket itself editable rather than relying on labelled drop targets beside it.

## 3. Implement direct attachment

- Drag a catalogue part into the 3D scene.
- Show a translucent placement preview and highlight compatible connection points.
- Snap the preview into place; release to attach and cancel to discard.
- Invalid placements leave the craft unchanged.

## 4. Make attached parts editable

- Select parts on the rocket to inspect, move, rotate, duplicate, or delete them.
- Moving a parent carries its connected assembly.
- Add undo/redo before expanding editing further.
- Undo/redo covers both assembly edits and staging edits.

## 5. Add symmetry and decouplers

- Support paired and four-way radial placement for boosters and fins.
- Make decouplers actual parts with explicit separation boundaries.
- Preview which assembly detaches and which remains under player control.

## 6. Build the staging mechanism

Staging is a dedicated workstream and part of the first playable milestone, not a later polish task.

### Stage column and editing

- Display numbered stage groups on the right, executed from top to bottom.
- Each group contains part icons for ignition, decoupling, or parachute deployment.
- Adding an engine, booster, decoupler, or parachute automatically creates its corresponding action in the stage column.
- Allow dragging actions between stages, reordering whole stages, and creating or removing empty stages.
- Actions grouped together execute on the same Space press.
- Hovering over a stage action highlights its part on the rocket; selecting a part highlights its stage action.
- Selecting a decoupler previews the detached assembly and the assembly that retains player control.
- Persist the complete sequence with the craft and support undo/redo for sequence changes.

### Preflight checks

- Flag a sequence that ignites an engine after discarding it.
- Flag separation of an active engine.
- Flag parachute deployment during launch.
- Also identify disconnected parts, missing fuel connections, and insufficient launch thrust.
- Make the affected part and action clear so players can correct the problem.

### Flight operation

- Space executes the next stage once.
- Mark completed stages, highlight the next stage, and show fuel remaining for active engines.
- Lock staging while paused.
- Execute the exact sequence configured in the builder.
- Preserve safe parachute deployment requirements.

### Example sequence

| Stage | Actions |
| --- | --- |
| 1 | Ignite solid boosters |
| 2 | Separate boosters and ignite core engine |
| 3 | Separate capsule |
| 4 | Deploy parachute when safe |

### Details to resolve during implementation

The discussion established the behaviors above but did not settle these mechanics:

- Which stage receives a newly created action by default.
- Whether a stage with an unsafe parachute action is blocked, or whether that action remains pending while other actions execute.
- The execution order within a grouped separation-and-ignition stage.
- Which warnings block launch versus permit an intentional risky design.
- The rule for retaining player control after a separation.

Define these consistently, expose relevant behavior in the UI, and test them before declaring staging complete.

## 7. Connect assembly and staging to flight

- Calculate mass, fuel, thrust, and balance from installed parts.
- Make ignition and separation actions target actual installed parts.
- Detached assemblies retain their own mass and motion.
- Ensure separation, fuel use, visual effects, and stage UI agree with the configured sequence.

## 8. Validate and package

- Test complete mouse-driven builds, cancelled and invalid drops, symmetry, undo/redo, and save/reload.
- Test stage creation, action reassignment, stage reordering, grouped actions, separation previews, paused staging, and prevention of duplicate stage execution.
- Fly saved designs through their configured staging sequences, including recovery.
- Check the interface at common window sizes.
- Retain existing flight, persistence, and terrain regression checks as appropriate.
- Verify the actual packaged Linux game, then update the usual launcher using a new versioned release.
- Clearly distinguish exported Windows builds from builds actually tested on Windows.

## First playable checkpoint / acceptance criteria

A player can:

1. Build a capsule–decoupler–tank–engine rocket entirely by dragging parts onto the 3D craft.
2. Edit its connections and undo mistakes.
3. Arrange ignition, separation, and parachute actions in the stage column.
4. Preview separation and understand the next stage.
5. Save and reload the complete assembly and staging plan.
6. Launch and fly that exact sequence through capsule separation and safe parachute recovery.

This checkpoint is incomplete if staging is still limited to preset ignition orders or if assembly still relies on tank counts and side-part toggles.

## Following work

Craft libraries, additional missions, and a separate cloud layer follow after the assembly and staging workflow feels good. Painted surface clouds were removed at the user's request; do not restore them as part of this work.

## Implementation checkpoint: 0.3.0 (2026-09-08)

Implemented:
- Connected-part save data with stable IDs, parent connections and tank rotation; legacy craft migration and incomplete-craft persistence.
- New craft from a starter capsule; separately attachable capsule decoupler, tanks and engine, with direct projected connection targets and translucent previews.
- Tank selection, rotation, duplication and deletion; undo/redo for assembly and stage edits.
- Right-hand editable stage groups, action drag-and-drop, group reordering, empty stages, automatic actions for added parts, and target/separation highlighting.
- Grouped flight execution, safe whole-stage validation, stage progress in the flight HUD, and saved custom sequences.
- Separated assemblies retain mass, inherited velocity and remaining propulsion in a ballistic simulation.
- Regression coverage for graph integrity, stage atomicity, staged recovery, real mouse-driven part and stage dragging, undo/redo and saved plans.

Resolved staging rules:
- Added core engines get an initial ignition group; added boosters join the first ignition group and receive a separation group; the capsule decoupler is assigned before the chute group.
- Unsafe chute deployment holds the entire stage; the player retries when safe.
- Groups execute separation, ignition, then deployment after all actions validate.
- Missing required parts, inadequate launch thrust, and ignition of discarded engines block rollout. Separating an active core is a warning.
- The command capsule retains control.

Still outstanding:
- Freeform movement of connected subassemblies and a complete attachment graph editor.
- Two/four-way symmetry selection and fully individual radial parts (current booster pair and fin set remain grouped).
- Generic multi-engine/multiple-liquid-stage simulation and complete per-part mass/balance calculations (current flight model consumes a projection of the connected single-core design).
- Full per-part inspect/move/rotate/duplicate/delete beyond tank editing.
- Category filtering, broader window-size/hardware validation and further usability polish.

## Surface-snapping correction: 0.3.1

The labelled attachment buttons from 0.3.0 misunderstood the intended interaction and have been removed. The corrected assembly flow uses the following rules:

- A new craft opens as an empty assembly bay. Only the command capsule card is enabled.
- Dropping the capsule unlocks its next compatible part. The catalogue progresses through capsule, decoupler, tank, engine, then optional side parts; unavailable cards remain visible but gray and cannot be dragged.
- The assembly canvas has no visible plus buttons or permanent attachment targets.
- A dragged 3D part follows the pointer. Away from a compatible connection surface it glows red.
- When the pointer approaches a compatible exposed surface, the dragged part snaps into its proposed position while the left mouse button remains held and glows green.
- Releasing while green connects the part. Releasing while red leaves the craft unchanged.
- Assembly occurs inside a dedicated enclosed hangar. Rollout transfers the completed vehicle to the outdoor launch pad.

The full first-playable acceptance criteria above are not yet all complete. This checkpoint is intended for playtesting the connected core builder and full custom staging mechanism.

## Fixed capsule root: 0.3.2

- The first capsule drop chooses the assembly's vertical starting height and is constrained to the hangar centerline.
- The chosen root height is stored with the connected assembly and survives save/reload.
- Decouplers, tanks, and engines extend downward from the capsule. Adding them does not move the capsule or recenter/zoom the workshop camera.
- Graphical regression checks compare the capsule's exact projected position after each axial attachment.

## Inventory return and fin surfaces: 0.3.3

- Installed parts can be grabbed in the 3D assembly and dragged back over the parts catalogue to remove them.
- Returning a part removes its stage actions, refreshes attachment availability, and creates an undo checkpoint. Returning the root capsule clears its attached vehicle.
- Fins expose compatible radial snap surfaces on the capsule and on each fuel tank. Their saved parent determines their height and whether they remain with the capsule after separation.

## Full-model drag feedback: 0.3.4

- Catalogue drags render the actual procedural model for every part type, with the complete model glowing red while invalid and green while snapped.
- Returning an installed part clears the drag preview, selected-part outline, and staging hover highlight before rebuilding the assembly view.

## Visible inventory-return drag: 0.3.5

- Grabbing an installed part creates a full-model 3D return ghost that follows the pointer.
- The return ghost is orange while moving through the assembly bay and green while over the catalogue removal target.
- Successful drops and cancelled drags both clear the ghost immediately.

## Reposition-or-return drag: 0.3.6

- An installed-part drag can end on a compatible craft surface to reposition it or on the catalogue to remove it.
- The full-model ghost snaps green at a valid repositioning surface and remains orange elsewhere.
- Fins can be moved between capsule and tank parents. The capsule can be moved vertically along the hangar centerline without changing the downward-growth rule for later attachments.

## Model-edge selection: 0.3.7

- Invisible screen-space hit areas remain available for mouse interaction but are never drawn as squares.
- Selecting any installed part renders a thin mint silhouette from that part's actual procedural geometry at its installed position.
- Legacy cylinder and cone selection overlays are retained only for the whole-lower-assembly staging preview, where they communicate discarded extent rather than an individual selected part.

## Connected-subassembly operations: 0.3.8

- Selection follows the attachment graph: the chosen part and every descendant connected beneath it receive the same model-edge highlight.
- Dragging a parent moves a full-model ghost of that complete connected subassembly. The selected part remains the grab reference while all descendants preserve their relative positions.
- Returning the selected root to the catalogue deletes the complete subtree and removes every stage action owned by its descendants. Undo restores the full subtree and its staging data.
- Selecting or dragging the capsule affects the whole vehicle; selecting or dragging the decoupler affects the complete lower launch assembly while leaving the capsule separate.

## Full-model picking and hover feedback: 0.3.9

- Each installed part has an invisible screen-space hit region sized to cover its visible model, making the full part easy to grab.
- Paired boosters and fins use separate left and right hit regions so their large combined area does not block selection of the central stack.
- Hovering outlines the affected part and its connected descendants in mint. Selecting the part changes that same subtree outline to orange.
- The hit regions remain invisible; all interaction feedback follows the procedural model silhouette.

## Engine mounting preview: 0.3.10

- Engine catalogue and repositioning ghosts never render powered exhaust.
- During free drag, the glow follows only the selected engine's bell geometry.
- At a valid engine surface, the green preview moves into its final installed orientation and includes the core feed skirt and mounting collar.

## Decoupler picking correction: 0.3.11

- The decoupler hitbox reads its anchor from the rendered assembly after every fuel-stack rebuild.
- The narrow decoupler region has pointer priority over overlapping capsule and tank regions.

## Adjustable fin surfaces: 0.3.12

- Fin placement follows the pointer vertically across the usable capsule or tank surface and clamps at that part's edges.
- The attachment graph stores the chosen surface offset, preserving fin height through repositioning, undo, and profile reloads.
- Capsule-mounted fins tilt to follow the tapered hull in both the green snap preview and final craft model.

## Distance-aware outlines: 0.3.13

- Editor outline width compensates for workshop camera distance, keeping thin parts such as the decoupler visible when zoomed out.
- The compensation is capped to preserve a clean model silhouette at close and medium range.

## Distant hover resolution and deselection: 0.3.14

- The assembly resolves hover from every overlapping pointer region each frame instead of relying on whichever Control receives a mouse-enter event.
- Normalized distance selects the nearest visible part, while the thin decoupler ring receives priority near its center at distant zoom.
- Left-clicking unused assembly space clears the selected part and returns the caption to the craft name.

## Fin snap alignment: 0.3.15

- Free and snapped fin previews share the visible attachment line as their transform origin, preventing vertical movement at the snap threshold.
- Capsule-mounted fins flare with the tapered hull; catalogue, snap, selection, and installed models use the same orientation.

## Capsule fin profile correction: 0.3.16

- Capsule fins use a compact inverted profile that tracks the hull as it widens downward; tank fins retain their taller upright profile.
- The fin geometry is centered consistently around its saved attachment height in free drag, snap preview, selection, and final rendering.

## Snap-preview occlusion: 0.3.17

- Green valid snap previews use normal scene depth, hiding geometry that will be embedded inside the parent hull after placement.
- Red free-drag previews retain x-ray visibility so a held part remains easy to track behind the craft.
