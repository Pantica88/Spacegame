extends SceneTree
const Editor = preload("res://scripts/planet_editor.gd")
const Definition = preload("res://scripts/planet_definition.gd")
var editor: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	editor = Editor.new()
	root.add_child(editor)
	editor.set_process(false)
	assert(not editor.cloud_tab_active, "Editor opens on world modeling")
	editor.spin_control.button_pressed = false
	editor.cloud_layer.hide()
	var settings := Definition.new()
	settings.radius = 32000.0
	settings.relief = 1600.0
	settings.launch_site = false
	settings.coastline_irregularity = 0.65
	settings.mountain_height = 1.5
	settings.erosion = 0.5
	settings.terrain_detail = 0.75
	settings.detail_frequency = 64.0
	settings.atmosphere_visual_density = 0.0
	editor.settings = settings
	editor.parent_settings = settings
	editor.distance = settings.radius * 3.8
	editor._refresh_controls()
	var begin := Time.get_ticks_usec()
	for value in range(30):
		editor.settings.terrain_seed = 9000 + value
		editor._queue_rebuild()
	assert(editor._preview_thread == null, "Dragging coalesces changes before any generation")
	editor._tick_preview(0.06)
	assert(editor._preview_thread == null, "Preview waits for debounce")
	editor._tick_preview(0.07)
	assert(editor._preview_thread != null, "CPU generation runs in a worker")
	var scheduling_ms := (Time.get_ticks_usec() - begin) / 1000.0
	print("30 edits and preview scheduling on main thread: %.2f ms" % scheduling_ms)
	# Queue another world while the first job is running. The old result must
	# never replace the currently requested body or seed.
	editor.settings.terrain_seed = 19001
	editor._queue_rebuild()
	await _wait_for_preview()
	assert(editor.terrain.definition.terrain_seed == 19001, "Latest generation wins")
	assert(editor.terrain.surface_texture != null and editor.terrain.topography_texture != null)
	assert(editor.terrain.surface_texture.get_width() == 1024, "Live detail has a bounded texture budget")
	assert(editor.terrain.mesh == null and editor.terrain.collision == null, "Editor preview never builds collision")
	var triangle_count: int = editor.planet.mesh.surface_get_array_index_len(0) / 3
	assert(triangle_count < 70000, "Adaptive close preview stays below 70k triangles")
	var surface: Texture2D = editor.terrain.surface_texture
	var topography: Texture2D = editor.terrain.topography_texture
	var signature: String = editor.terrain.bake_signature(settings)
	var unaffected_seed: int = settings.terrain_seed
	editor._apply_shape_preset(1)
	assert(settings.terrain_seed == unaffected_seed and settings.mountain_height == 1.8, "Terrain styles preserve the seed")
	# Restore the tested shape to exercise map reuse after changing controls.
	settings.mountain_height = 1.5
	settings.coastline_irregularity = 0.65
	settings.erosion = 0.5
	settings.terrain_detail = 0.75
	settings.detail_frequency = 64.0
	editor._refresh_controls()
	editor._queue_rebuild()
	await _wait_for_preview()
	assert(editor.terrain.bake_signature(settings) == signature)
	var revision: int = editor._preview_revision
	editor.controls.atmosphere_visual_density.value_changed.emit(0.35)
	assert(editor._preview_revision == revision and not editor.rebuild_pending, "Atmosphere changes do not regenerate terrain")
	assert(editor.planet.material_override.get_shader_parameter("atmosphere_density_scale") == 0.35)
	editor.controls.orbit_phase.value_changed.emit(0.6)
	assert(editor._preview_revision == revision, "Orbit edits do not regenerate terrain")
	for view in range(4):
		editor.surface_view_picker.select(view)
		editor.surface_view_picker.item_selected.emit(view)
		assert(editor.planet.material_override.get_shader_parameter("surface_view") == view)
		if DisplayServer.get_name() != "headless":
			for frame in range(3): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/aphelion-planet-view-%d.png" % view)
	if DisplayServer.get_name() != "headless":
		editor.planet.material_override.set_shader_parameter("surface_view", 0)
		var adaptive_mesh: ArrayMesh = editor.planet.mesh
		editor.planet.mesh = editor.terrain.preview_mesh()
		editor.planet.material_override.set_shader_parameter("has_baked_topography", false)
		await _measure_render("Full globe, mesh normals")
		editor.planet.mesh = adaptive_mesh
		editor.planet.material_override.set_shader_parameter("has_baked_topography", true)
		await _measure_render("Adaptive globe, detailed normals")
	editor.distance = settings.radius * 5.0
	editor._queue_rebuild()
	await _wait_for_preview()
	assert(editor.terrain.surface_texture == surface and editor.terrain.topography_texture == topography, "Zoom refinement reuses surface maps")
	assert(editor.planet.mesh.surface_get_array_index_len(0) / 3 < triangle_count / 2, "Distant preview drops triangle density")
	editor.detail_picker.select(3)
	editor._queue_rebuild()
	await _wait_for_preview()
	var exact: Array = editor.terrain.render_mesh_for_lod(2).surface_get_arrays(0)
	var visible: Array = editor.planet.mesh.surface_get_arrays(0)
	assert(visible[Mesh.ARRAY_VERTEX] == exact[Mesh.ARRAY_VERTEX], "Explicit flight preview preserves physical layer geometry")
	assert(visible[Mesh.ARRAY_INDEX] == exact[Mesh.ARRAY_INDEX])
	# Shut down while a new generation is pending; thread lifecycle is clean.
	editor._queue_rebuild()
	editor._tick_preview(1.0)
	editor.queue_free()
	await process_frame
	print("PASS: debounced background previews, stale-result rejection, cache reuse, adaptive triangles, inspection views and clean shutdown")
	quit()

func _wait_for_preview() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while editor.rebuild_pending or editor._preview_thread != null or editor._preview_refine_pending:
		assert(Time.get_ticks_msec() < deadline, "Preview finishes within 30 seconds")
		editor._tick_preview(0.01)
		await create_timer(0.01).timeout
	assert(editor._preview_is_refined)

func _measure_render(label: String) -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for frame in range(10): await process_frame
	var gpu_ms := 0.0
	var cpu_ms := 0.0
	for frame in range(60):
		await process_frame
		await RenderingServer.frame_post_draw
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	var triangles: int = editor.planet.mesh.surface_get_array_index_len(0) / 3
	print("%s: %d triangles, %.3f ms GPU, %.3f ms render CPU" % [label, triangles, gpu_ms / 60.0, cpu_ms / 60.0])
