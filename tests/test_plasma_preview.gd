extends SceneTree
const Preview = preload("res://scenes/plasma_preview.tscn")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var preview = Preview.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	assert(preview.airspeed == 2000.0 and preview.heat == 1.0 and preview.auto_turn, "Preview starts with a hot tumbling vessel")
	var attitude: Basis = preview.orientation
	preview._process(0.03)
	assert(not preview.orientation.is_equal_approx(attitude), "Automatic tumble turns the vessel")
	_key(preview, KEY_SPACE)
	attitude = preview.orientation
	preview._process(0.03)
	assert(preview.paused and preview.orientation.is_equal_approx(attitude), "Space pauses the vessel")
	preview.speed_slider.value = 1500.0
	assert(preview.airspeed == 1500.0, "Speed slider controls airspeed")
	preview.heat_slider.value = 0.5
	assert(preview.heat == 0.5, "Heat slider controls glow")
	preview._set_pose(0.0)
	assert(not preview.auto_turn and preview.orientation.is_equal_approx(Basis.IDENTITY), "Pose buttons disable automatic tumble")
	attitude = preview.orientation
	preview.heading_slider.value = 90.0
	preview._process(0.0)
	assert(preview.orientation.is_equal_approx(attitude), "Changing travel direction does not turn the nose")
	assert(preview.world._heat_trail.flow_direction.distance_to(Vector3.UP) < 0.0001, "Flames follow the new travel direction")
	var local_flow: Vector3 = preview.world._heat_trail._material.get_shader_parameter("local_flow")
	assert((preview.orientation * local_flow).distance_to(Vector3.DOWN) < 0.0001, "Wake streams opposite movement in world space")
	preview._set_pose(-PI / 2.0)
	assert(preview.orientation.y.distance_to(Vector3.UP) < 0.0001, "Nose-first preset follows the selected travel direction")
	preview.craft_picker.item_selected.emit(1)
	preview._process(0.0)
	assert(preview.world._capsule_only, "Recovery capsule can be inspected")
	_key(preview, KEY_R)
	assert(not preview.paused and preview.auto_turn and preview.airspeed == 2000.0 and preview.heat == 1.0 and preview.craft_index == 0, "Reset restores the test")
	preview._set_pose(-PI / 2.0)
	for i in range(25):
		preview._process(1.0 / 60.0)
		await process_frame
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aphelion-plasma-preview.png")
	preview.free()
	print("PASS: interactive plasma preview controls, pause, poses, craft selection and reset")
	quit(0)

func _key(preview: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	preview._unhandled_input(event)
