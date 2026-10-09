extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewer = load("res://scenes/asset_viewer.tscn").instantiate()
	root.add_child(viewer)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await process_frame
	assert(viewer.components.size() == 9, "Canister must retain nine named components")
	var first = viewer.tree.get_root().get_first_child()
	first.select(0)
	viewer._select_component()
	viewer.isolate = true
	viewer._apply_visibility()
	assert(viewer.components[0].visible)
	assert(not viewer.components[1].visible)
	viewer.isolate = false
	first.set_checked(0, false)
	viewer._visibility_edited()
	assert(not viewer.components[0].visible)
	assert(viewer.components[1].visible)
	viewer.slider.value = 1
	assert(viewer.components[0].position != viewer.rest[0])
	viewer._view("Reset")
	assert(viewer.components[0].position == viewer.rest[0])
	for view_name in ["Top", "Bottom", "Front"]:
		viewer._view(view_name)
		assert(viewer.camera.transform.is_finite())
	for i in [1, 2, 3, 4, 5, 6, 7, 8, 0]:
		await viewer._load_asset(i)
		assert(viewer.components.size() > 0)
		if i == 8:
			assert(viewer.components.size() == 7, "Sparrow must retain seven inspectable components")
		if i in [6, 7]:
			assert(viewer.components.size() == (5 if i == 6 else 3), "Parachute component count")
		if i == 5:
			assert(viewer.components.size() == 7, "Separator-1 must have seven inspectable components")
		if i == 4:
			assert(viewer.components.size() == 9, "Booster-1 must have nine inspectable components")
		if i == 3:
			assert(viewer.components.size() == 8, "Engine-1 must have eight inspectable components")
		assert(viewer.selected == -1)
	assert(viewer.components.size() == 9)
	var count := 0
	for part in viewer.components:
		count += viewer._triangles(part)
	assert(count == 49968)
	viewer.queue_free()
	await process_frame
	print("PASS: asset library, component isolation and visibility, explosion reset, camera presets, 49,968-triangle canister")
	quit()
