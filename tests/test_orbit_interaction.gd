extends SceneTree
const Physics = preload("res://scripts/physics_math.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var failures: Array[String] = []
var game
var map
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func reset_orbit() -> void:
	game.design = game.Parts.default_design()
	await game._roll_out()
	game._stage()
	game._set_throttle(0.0)
	game.flight.state.throttle = 0.0
	var radial := Vector3(0.45, 0.34, 0.82).normalized() * 100000.0
	game.flight.state.position = Physics.PLANET_CENTER + radial
	game.flight.state.velocity = radial.normalized().cross(Vector3.UP).normalized() * sqrt(Physics.MU / radial.length())
	game.map_panel.show()
	game._update_flight_ui()
	map.yaw = 0.9
	map.pitch = 1.05
	map._process(0.02)
func run() -> void:
	var home: Resource = Surface.home().definition.duplicate(true)
	home.moons.clear()
	Surface.reset_home(home)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	map = game.map_instrument
	reset_orbit()
	await process_frame
	# Menu is anchored at the clicked orbit point and does not create a node yet.
	var selected: Dictionary = map.Maneuver.propagate(Vector3(map.state.position) - Physics.PLANET_CENTER, map.state.velocity, 80.0, Physics.MU, Physics.PLANET_RADIUS)
	var point: Vector2 = map.camera.unproject_position(Vector3(selected.position) * 0.001)
	map._show_orbit_menu(point, 80.0)
	check(map.orbit_menu.visible and map.maneuver.epoch < 0.0, "Opening menu does not create a plan")
	check(map.orbit_create_button.get_parent().get_child_count() == 2, "Context menu contains exactly two options")
	check(not map.orbit_warp_button.disabled, "Safe coast enables Warp here")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aphelion-orbit-menu.png")
	map.orbit_create_button.pressed.emit()
	map._process(0.02)
	check(not map.orbit_menu.visible and map.maneuver_valid, "Create plan replaces the popup with a valid plan")
	check(map.maneuver_gizmo.visible and map.maneuver_gizmo.handles.size() == 6, "Created node exposes six direction symbols")
	var gizmo = map.maneuver_gizmo
	for index in range(6):
		map.maneuver.components = Vector3.ZERO
		map._refresh_maneuver(true)
		map._process(0.02)
		var handle: Dictionary = gizmo.handles[index]
		for other in range(index):
			check(Vector2(handle.point).distance_to(gizmo.handles[other].point) > 38.0, "Handle hit targets do not overlap")
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = handle.point
		map._gui_input(press)
		check(gizmo.dragging == index, "Click selects direction handle %d" % index)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(handle.direction) * 25.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		gizmo._input(motion)
		var axis: int = handle.axis
		check(map.maneuver.components[axis] * float(handle.sign) > 20.0, "Outward drag adds signed delta-v for handle %d" % index)
		motion.relative *= -2.0
		gizmo._input(motion)
		check(map.maneuver.components[axis] * float(handle.sign) < -20.0, "Inward drag reduces and reverses delta-v for handle %d" % index)
		for other_axis in range(3):
			if other_axis != axis: check(map.maneuver.components[other_axis] == 0.0, "Dragging changes only its own component")
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		gizmo._input(release)
		check(gizmo.dragging == -1, "Mouse release ends capture")
	map.maneuver.components = Vector3.ZERO
	map._refresh_maneuver(true)
	map._process(0.02)
	gizmo.begin_drag(0)
	gizmo.drag_by(Vector2(gizmo.handles[0].direction) * 10.0, true)
	check(is_equal_approx(map.maneuver.components.x, 1.0), "Shift gives one-tenth drag sensitivity")
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	game._physics_process(0.01)
	check(game.throttle == 0.0, "Holding Shift during handle drag cannot increase throttle")
	var shift_release := shift.duplicate() as InputEventKey
	shift_release.pressed = false
	Input.parse_input_event(shift_release)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	gizmo._input(escape)
	check(gizmo.dragging == -1 and map.maneuver.components.x == 0.0, "Escape cancels a drag and restores its original value")
	map.maneuver.components = Vector3(80, -20, 15)
	map._refresh_maneuver(true)
	map._process(0.02)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aphelion-maneuver-handles.png")
	# Warping is independent of creating a plan and stops at the simulation epoch.
	map.clear_maneuver()
	map._focus_planet(map.home_index)
	map._process(0.02)
	check(map._maneuver_path_hit(map.camera.unproject_position(Vector3(selected.position) * 0.001)) >= 0.0, "Home-planet camera focus still permits selecting the craft orbit")
	map._show_orbit_menu(point, 37.125)
	var arrival: float = map.orbit_menu_epoch
	map.orbit_warp_button.pressed.emit()
	check(game.warp_target_time == arrival and game.warp > 1.0, "Warp here starts bounded automatic time acceleration")
	check(map.maneuver.epoch < 0.0, "Warp here does not create a maneuver")
	var stopped_time: float = game.flight.simulation_time()
	game.paused = true
	game._physics_process(2.0)
	check(game.flight.simulation_time() == stopped_time and game.warp_target_time == arrival, "Pause preserves pending warp destination")
	game.paused = false
	for frame in range(200):
		if game.warp_target_time < 0.0: break
		game._physics_process(0.13)
	check(absf(game.flight.simulation_time() - arrival) < 0.0001, "Warp stops at target without stepping past it")
	check(game.warp_target_time < 0.0 and game.warp == 1.0, "Arrival returns to normal time")
	game._warp_to_location(game.flight.simulation_time() + 80.0)
	map.cancel_warp_requested.emit()
	check(game.warp_target_time < 0.0 and game.warp == 1.0, "Stop button cancels warp immediately")
	game._warp_to_location(game.flight.simulation_time() + 80.0)
	game._set_throttle(0.2)
	check(game.warp_target_time < 0.0 and game.warp == 1.0, "Throttle cancels automatic warp")
	game._warp_to_location(game.flight.simulation_time() + 80.0)
	check(game.warp_target_time < 0.0, "Warp cannot bypass powered-flight restrictions")
	game._set_throttle(0.0)
	game.flight.state.throttle = 0.0
	game._warp_to_location(game.flight.simulation_time() + 80.0)
	game.flight.state.position = Vector3(0, 1000, 0)
	game._physics_process(0.1)
	check(game.warp_target_time < 0.0 and game.warp == 1.0, "Atmospheric safety limit cancels automatic warp")
	reset_orbit()
	game._warp_to_location(game.flight.simulation_time() + 80.0)
	await game._roll_out()
	check(game.warp_target_time < 0.0, "Retry clears a pending warp destination")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: orbit popup, six directional drag handles, fine adjustment, cancellation and warp-to-time" if failures.is_empty() else "FAIL: orbit interaction")
	quit(0 if failures.is_empty() else 1)
