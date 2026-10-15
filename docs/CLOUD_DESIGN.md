# Cloud design

Launch the source planet editor with `./tools/run.sh res://scenes/planet_editor.tscn`, then open **Clouds**.

## Layers

**Add** starts a separate cloud pass. The layer picker lists the topmost layer first; **Up / Down** changes which clouds cover others. Paint, erase, clear, generate, and retouch operate on the selected visible, unlocked layer. Erasing reveals lower layers without modifying their pixels.

**Duplicate selected layer** makes an independent copy with the same opacity and visibility, unlocked for editing. Layer opacity fades all formations in that layer without changing its source paint. Layer operations participate in Undo/Redo. **Bake & Save** stores the complete editable stack, including hidden layers. Existing weather maps open as a single layer. **Reset to procedural** removes the stack and can be undone.

## Generation and preview

Expand **Random weather generator**. The target label identifies the layer that will receive the result.

1. Check the cloud types you want. Enter relative weights in **parts**; `60, 30, 10` gives a 60% / 30% / 10% mix. The displayed percentages normalize the checked weights. Unchecked and zero-weight types do not generate. Counts are apportioned across the requested formations, so very small shares may round to zero.
2. Set the seed and formation count. Under **Generation design**, set minimum/maximum angular radius and cloud coverage. Mushroom formations retain their narrower footprint.
3. Choose **Replace clouds in region** or **Add to existing clouds**. Add blends formations over existing paint; Replace removes the previous paint only within the chosen region.
4. Choose **Whole planet**, **Painted selection**, or **Latitude band**. South/north latitudes delimit the band, with negative values south of the equator.
5. Click **Preview generation**. The globe shows the temporary result; authored cloud data and history are unchanged. **Reroll preview** chooses another seed from the same settings.
6. Click **Apply preview** to commit one undoable edit, or **Cancel** to discard it. Apply or Cancel before saving. Painting, switching layers/bodies, and Undo/Redo cancel pending previews.

For a painted selection, click **Paint selection** and drag on the globe. **Subtract** removes areas from the selection; **Clear selection** resets it. Both selection tools use the brush radius and soft edge. The white areas in the selection map receive generation; its left/right edges wrap around the globe. Selection paint is separate from cloud paint. An empty selection cannot generate clouds. Soft selection edges blend the result into the original paint.

## Recipes

Enter a name under **Generation recipes**, then **Save recipe**. Recipes retain the seed, formation count, selected types, relative weights, radius range, coverage, Add/Replace mode, region, latitude limits, and any painted selection. Select a saved recipe and click **Load recipe** to restore those settings, then preview it on the currently selected layer. Saving an existing name updates that recipe; **Delete recipe** removes it.

Recipes are shared across planets in `user://cloud_recipes.json`. They do not contain layer paint or change the selected layer when loaded.

## Retouching

**Smooth brush** blends nearby cloud weights to reduce abrupt changes. **Soften brush** thins boundaries without spreading clouds into neighboring empty pixels. Drag on the globe with the chosen tool; brush opacity controls its strength. Each drag is one undo operation. Other layers remain unchanged.

To move, rotate, or resize an area:

1. Set the brush radius, click **Pick region to move / transform**, then click the source area on the globe.
2. Set **Region rotation** and **Region scale**. The scale range is 25–300%.
3. Choose **Rotate / resize at source** to keep its center, or **Place region on globe…** and click a destination to move it.

The circular region moves with a feathered boundary, using the original source pixels even when source and destination overlap. The edit affects only the active layer and is undoable. Pick a new source before each transform; changing layers or undoing invalidates the previous source.

## Validation

`tools/check.sh` includes cloud design, custom mix, layer, painting, editor, and save/restart tests. The design test covers region isolation, weighted generation, size controls, add/replace blending, layer opacity and duplication, smooth/soften and transforms, preview lifecycle, recipe persistence, and saved planet opacity.
