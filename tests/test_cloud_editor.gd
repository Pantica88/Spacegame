extends SceneTree
## Exercises the actual editor scene, brush input and saved tile library.
const Editor = preload("res://scripts/planet_editor.gd")
const Library = preload("res://scripts/cloud_brush_library.gd")
var editor: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	editor = Editor.new()
	root.add_child(editor)
	editor.cloud_tools.get_parent().current_tab = 2
	editor.world_root.rotation = Vector3.ZERO
	editor.yaw = 0.0
	editor.pitch = 0.16
	editor.distance = float(editor.settings.radius) * 3.8
	editor._update_camera()
	for frame in range(4): await process_frame
	assert(editor.cloud_tab_active)
	assert(editor.cloud_tools.tile_buttons.size() >= 5)
	var center := Vector3(0.0, 0.16, 1.0).normalized()
	var screen: Vector2 = editor.camera.unproject_position(center * (float(editor.settings.radius) + editor._cloud_brush_height()))
	assert(editor._cloud_direction(screen).dot(center) > 0.9999, "Cursor picking agrees with the cloud preview camera offset")
	var original: Resource = editor.settings.cloud_weather
	editor.settings.cloud_weather = null
	editor._reset_cloud_history()
	editor.cloud_tools.custom_name.grab_focus()
	editor._start_cloud_stroke(screen)
	assert(root.gui_get_focus_owner() == null, "Painting returns keyboard focus to the globe")
	assert(editor.painting_clouds)
	assert(editor.settings.cloud_weather != null)
	var drag_to: Vector2 = editor.camera.unproject_position(Vector3(0.22, 0.16, 1.0).normalized() * (float(editor.settings.radius) + editor._cloud_brush_height()))
	editor._paint_cloud_to(drag_to)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(1350, 400)
	editor._input(release)
	assert(not editor.painting_clouds, "Releasing over controls finishes painting")
	assert(editor.cloud_undo.size() == 1, "A whole drag is one undo operation")
	var painted: PackedByteArray = editor.settings.cloud_weather.image.get_data()
	var undo_key := InputEventKey.new()
	undo_key.keycode = KEY_Z
	undo_key.ctrl_pressed = true
	undo_key.pressed = true
	editor._input(undo_key)
	assert(editor.settings.cloud_weather == null, "Undo restores procedural weather before the first stroke")
	editor._redo_clouds()
	assert(editor.settings.cloud_weather.image.get_data() == painted)
	editor.cloud_tools.weather_seed.value = 9871
	editor.cloud_tools.weather_count.value = 8
	editor.cloud_tools._select_weather_types(false)
	editor.cloud_tools.weather_types["mushroom"].button_pressed = true
	editor.cloud_tools._generate_weather()
	var generated: PackedByteArray = editor.settings.cloud_weather.image.get_data()
	assert(generated != painted, "Generator replaces the weather map")
	editor._undo_clouds()
	assert(editor.settings.cloud_weather.image.get_data() == painted, "Undo restores weather before generation")
	editor._redo_clouds()
	assert(editor.settings.cloud_weather.image.get_data() == generated, "Redo restores the generated weather exactly")
	editor._undo_clouds()
	editor.cloud_tools.custom_name.text = "Editor integration formation"
	editor.cloud_tools.mode = 2
	editor._start_cloud_stroke(screen)
	assert(not editor.cloud_tools.custom_paths.is_empty())
	assert(editor.cloud_tools.mode == 0, "Capturing selects the newly saved tile for painting")
	assert(editor.cloud_tools.selected_tile != null)
	var saved_path: String = editor.cloud_tools.custom_paths.back()
	assert(ResourceLoader.load(saved_path) is Image, "Custom tiles survive disk round trips")
	# Show a mix of neighboring formations without changing the planet on disk.
	editor._clear_clouds()
	var centers := [Vector3(-0.32, 0.36, 1), Vector3(0.12, 0.39, 1), Vector3(0.4, 0.05, 1), Vector3(-0.2, -0.06, 1), Vector3(0.12, -0.27, 1)]
	var ids := ["cumulus", "streets", "stratocumulus", "storm", "overcast"]
	for index in range(ids.size()):
		editor.settings.cloud_weather.stamp(centers[index].normalized(), deg_to_rad(19.0), Library.tile(ids[index]), 1.0, 0.3, false, 0.65)
	var before_save: PackedByteArray = editor.settings.cloud_weather.image.get_data()
	editor.current_path = "user://cloud-editor-test/planet.tres"
	editor._save_world()
	var saved: Resource = ResourceLoader.load(editor.current_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	assert(saved != null and saved.cloud_weather != null, "Bake & Save persists authored weather with the body")
	assert(saved.cloud_weather.image.get_data() == before_save, "Baking preserves every cloud formation weight")
	if DisplayServer.get_name() != "headless":
		# The march keeps a short temporal history; let it settle.
		for frame in range(30): await process_frame
		await RenderingServer.frame_post_draw
		var capture: Image = root.get_texture().get_image()
		capture.save_png("/tmp/aphelion-cloud-editor.png")
		editor.set_process(false)
		editor.cloud_layer.hide()
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var clear: Image = root.get_texture().get_image()
		var difference := 0.0
		var samples := 0
		for y in range(100, capture.get_height(), 4):
			for x in range(0, int(capture.get_width() * 0.70), 4):
				var first := capture.get_pixel(x, y)
				var second := clear.get_pixel(x, y)
				difference += (absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)) / 3.0
				samples += 1
		difference /= maxf(1.0, samples)
		print("Painted editor cloud/clear difference: %.6f" % difference)
		if difference < 0.003:
			push_error("Painted cloud formations must be visible in the offset editor camera")
			quit(1)
			return
		print("Cloud editor capture: /tmp/aphelion-cloud-editor.png")
	editor.settings.cloud_weather = original
	editor.queue_free()
	await process_frame
	print("PASS: editor cloud palette, camera picking, drag/release, stroke undo/redo, custom tile capture and Bake & Save weather.")
	quit()
