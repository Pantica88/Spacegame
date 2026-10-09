extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var game := preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var world = game.world
	assert(not world._landscape.visible and not world._planet.visible, "Workshop starts without launch scenery blocking the underside")
	assert(world._hangar.is_visible_in_tree() and not world._flight_location.visible, "Workshop and launch site are separate locations")
	assert(world._environment.background_mode == Environment.BG_COLOR, "Workshop has its own indoor backdrop")
	world.workshop_camera_view("Reset")
	var initial: Transform3D = world.camera.transform
	for direction in [-1.0, 1.0]:
		var previous: Basis = world.camera.basis
		for step in range(720):
			world.orbit_camera(Vector2(0, direction * TAU / 720.0 / 0.005))
			assert(world.camera.basis.is_finite(), "Workshop camera is finite at poles")
			assert(world.camera.basis.y.dot(previous.y) > 0.999, "Workshop orbit crosses poles without flipping")
			previous = world.camera.basis
		assert(world.camera.position.distance_to(initial.origin) < 0.01, "Full orbit returns to initial position")
	var directions := {"Front": Vector3.BACK, "Back": Vector3.FORWARD, "Left": Vector3.LEFT, "Right": Vector3.RIGHT, "Top": Vector3.UP, "Bottom": Vector3.DOWN}
	for view in directions:
		world.workshop_camera_view(view)
		var offset: Vector3 = (world.camera.position - world._camera_focus).normalized()
		assert(offset.dot(directions[view]) > 0.999, "Preset looks from requested direction")
		assert(world.camera.basis.is_finite(), "Preset has valid camera basis")
	world.workshop_camera_view("Bottom")
	assert(not world._hangar_floor.visible, "Floor cuts away for engine inspection")
	world.workshop_camera_view("Reset")
	assert(world._hangar_floor.visible, "Floor returns above ground")
	var original_width: float = game.build_drop_area.size.x
	game._toggle_workshop_expanded()
	await process_frame
	assert(game.build_drop_area.size.x > original_width + 500, "Expanded assembly canvas gains sidebar space")
	for panel in game.workshop_side_panels: assert(not panel.visible)
	game._toggle_workshop_expanded()
	await process_frame
	assert(is_equal_approx(game.build_drop_area.size.x, original_width), "Panels restore original canvas bounds")
	for panel in game.workshop_side_panels: assert(panel.visible)
	# Send real viewport input through the GUI, where the assembly canvas used
	# to swallow orbit and zoom before they reached _unhandled_input.
	var point: Vector2 = game.build_drop_area.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	root.push_input(press, true)
	var yaw: float = world._yaw
	motion.relative = Vector2(60, 30)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(motion, true)
	assert(absf(world._yaw - yaw) > 0.3, "Right drag orbits through assembly GUI")
	press.pressed = false
	root.push_input(press, true)
	assert(not game.workshop_orbit_drag, "Releasing right mouse ends orbit")
	var distance: float = world._distance
	press.button_index = MOUSE_BUTTON_WHEEL_UP
	press.pressed = true
	root.push_input(press, true)
	assert(world._distance < distance, "Scroll zoom reaches camera through assembly GUI")
	var focus_before_pan: Vector3 = world._camera_focus
	press.button_index = MOUSE_BUTTON_MIDDLE
	root.push_input(press, true)
	motion.relative = Vector2(0, 80)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion, true)
	assert(world._camera_focus.distance_to(focus_before_pan) > 0.5, "Middle drag pans through assembly GUI")
	press.pressed = false
	root.push_input(press, true)
	assert(not game.workshop_pan_drag, "Middle release stops panning")
	world.workshop_camera_view("Reset")
	assert(world.camera.transform.is_equal_approx(initial), "Reset restores camera framing")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/workshop-updated.png")
		game._toggle_workshop_expanded()
		world.workshop_camera_view("Bottom")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/workshop-bottom.png")
	await game._roll_out()
	assert(game.mode == "flight", "Rollout reaches launch pad")
	assert(world._flight_location.visible and world._landscape.is_visible_in_tree(), "Rollout shows outdoor launch location")
	assert(not world._hangar.is_visible_in_tree(), "Workshop does not appear at launch pad")
	assert(world._environment.background_mode == Environment.BG_SKY, "Launch pad restores outdoor sky")
	game._return_workshop()
	assert(world._hangar.is_visible_in_tree() and not world._flight_location.visible, "Returning restores only the workshop location")
	assert(not world._landscape.is_visible_in_tree() and not world._planet.is_visible_in_tree(), "No launch scenery leaks into workshop")
	for moon in world._moons: assert(not moon.is_visible_in_tree())
	print("PASS: separate workshop/launch locations, full orbit, presets, cutaway, expansion, GUI drag and zoom")
	game.queue_free()
	await process_frame
	quit()
