extends SceneTree
const Physics = preload("res://scripts/physics_math.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var home: Resource = Surface.home().definition.duplicate(true)
	home.moons.clear()
	Surface.reset_home(home)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.design = game.Parts.default_design()
	await game._roll_out()
	game._stage()
	game._set_throttle(0.0)
	game.flight.state.throttle = 0.0
	var radial := Vector3(0.45, 0.34, 0.82).normalized() * (Physics.PLANET_RADIUS + Physics.ATMOSPHERE_HEIGHT + 10000.0)
	var velocity := radial.normalized().cross(Vector3.UP).normalized() * sqrt(Physics.MU / radial.length())
	game.flight.state.position = Physics.PLANET_CENTER + radial
	game.flight.state.velocity = velocity
	game._toggle_map()
	game._update_flight_ui()
	var map = game.map_instrument
	map._process(1.0 / 60.0)
	await process_frame
	check(not map.maneuver_panel.is_visible_in_tree(), "Map starts uncluttered until a plan is created")
	check(map.place_maneuver(80.0), "A future vacuum coast accepts a maneuver")
	map.maneuver_fields[0].value = 80.0
	map.precise_values.show()
	map.maneuver_fields[0].get_line_edit().grab_focus()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.pressed = true
	game._input(key)
	check(game.throttle == 0.0, "Typing in burn fields does not trigger throttle shortcuts")
	map.maneuver_fields[0].get_line_edit().release_focus()
	var paused_time: float = game.flight.simulation_time()
	game.paused = true
	game._physics_process(1.0)
	check(game.flight.simulation_time() == paused_time, "Pause preserves burn timing and simulation state")
	game.paused = false
	map._process(1.0 / 60.0)
	check(map.maneuver.components.x == 80.0, "Prograde control changes the planned impulse")
	check(map.maneuver_mesh.get_surface_count() == 1, "Edited maneuver draws a separate trajectory")
	check(map.maneuver_material.albedo_color != map.path_material.albedo_color, "Planned and current trajectories have distinct colors")
	check("Burn duration:" in map.maneuver_summary.text and "Fuel needed:" in map.maneuver_summary.text, "Editor shows timing and usable fuel estimates")
	check(map.labels.any(func(label): return label.text == "MANEUVER"), "Node has a map marker")
	game._update_flight_ui()
	check(game.navball.state.has("maneuver_direction"), "Valid plan reaches navball guidance")
	var before: float = map.maneuver.epoch
	map.maneuver_shift_buttons[1].pressed.emit()
	check(is_equal_approx(map.maneuver.epoch, before + 10.0), "Time control moves the node")
	map.maneuver_fields[1].value = -20.0
	map.maneuver_fields[2].value = 15.0
	check(map.maneuver.components == Vector3(80, -20, 15), "Normal and radial edits retain signed values")
	# Select a visible coast segment through the actual map click handler.
	var clicked := false
	for index in range(20, map._coast_points.size() - 1, 4):
		var point: Vector3 = map._coast_points[index] * 0.001
		var screen: Vector2 = map.camera.unproject_position(point)
		if not Rect2(Vector2(240, 140), map.size - Vector2(600, 210)).has_point(screen): continue
		if map._craft_icon_hit(screen) or map._point_occluded(point): continue
		if map.maneuver_gizmo.hit_test(screen) >= 0: continue
		var seconds: float = map._maneuver_path_hit(screen)
		if seconds < 1.0: continue
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = screen
		map._gui_input(click)
		check(map.orbit_menu.visible, "Clicking coast opens its context menu")
		check(map.orbit_create_button.text == "Create plan" and map.orbit_warp_button.text == "Warp here", "Orbit menu provides the requested two actions")
		map.orbit_create_button.pressed.emit()
		check(absf(map.maneuver.epoch - map._simulation_time() - seconds) < 0.01, "Create plan sets the selected future epoch")
		clicked = true
		break
	check(clicked, "A visible trajectory segment is pickable")
	map.maneuver_fields[0].value = 80.0
	map.maneuver_fields[1].value = -20.0
	map.maneuver_fields[2].value = 15.0
	map.place_maneuver(80.0)
	map.yaw = 0.9
	map.pitch = 1.05
	map._process(0.02)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aphelion-maneuver-map.png")
		check(map.maneuver_panel.get_global_rect().end.y < map.get_global_rect().end.y - 25.0, "Editor fits above map footer")
	var epoch: float = map.maneuver.epoch
	game._toggle_map()
	game._update_flight_ui()
	check(map.maneuver.epoch == epoch and game.navball.state.has("maneuver_direction"), "Closing map preserves plan and flight guidance")
	game._toggle_map()
	# Engine changes are estimates, never automatic changes to the craft.
	var fuel_before: float = game.flight.state.fuel
	map.maneuver_fields[0].value = 5000.0
	check("Insufficient" in map.maneuver_notice.text, "Unachievable burn is clearly labeled")
	check(game.flight.state.fuel == fuel_before, "Planning does not consume fuel")
	map.maneuver_fields[0].value = 80.0
	game._set_throttle(1.0)
	game._update_flight_ui()
	check(not map.maneuver_valid and not game.navball.state.has("maneuver_direction"), "Thrust invalidates coast guidance immediately")
	map._process(0.02)
	check(map.maneuver_mesh.get_surface_count() == 0, "Invalid preview is removed")
	game._set_throttle(0.0)
	game._update_flight_ui()
	check(map.maneuver_valid, "Cutting throttle recalculates the plan")
	game.flight.stage()
	game._update_flight_ui()
	check("Insufficient" in map.maneuver_notice.text, "Separated engine cannot supply the burn")
	game.flight.state.time = map.maneuver.epoch + 1.0
	game._update_flight_ui()
	check(not map.maneuver_valid and "passed" in map.maneuver_status, "Missed node expires while the simulation advances")
	check(not game.navball.state.has("maneuver_direction"), "Expired marker disappears")
	map.clear_maneuver()
	game._update_flight_ui()
	check(map.maneuver.epoch < 0.0 and map.maneuver_mesh.get_surface_count() == 0, "Deleting clears node and trajectory")
	game.flight.state.position = Vector3(0, 1000, 0)
	game._update_flight_ui()
	check(not map.place_maneuver(30.0) and "Atmosphere" in map.maneuver_status, "Atmospheric trajectory cannot be presented as a valid vacuum plan")
	await game._roll_out()
	check(map.maneuver.epoch < 0.0, "Retry clears old flight's plan")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: map maneuver placement, edits, trajectory, guidance, invalidation and retry" if failures.is_empty() else "FAIL: maneuver map")
	quit(0 if failures.is_empty() else 1)
