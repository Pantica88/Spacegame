extends SceneTree
## Flight scenery, the tracking camera and atmosphere must share a render pose.
const World = preload("res://scripts/world_view.gd")
const Flight = preload("res://scripts/flight_model.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	var flight := Flight.new()
	var state: Dictionary = flight.telemetry()
	state.status = "flying"
	state.position += Vector3.BACK * 3000.0
	state.altitude = 3000.0
	state.simulation_time = 0.0
	world.begin_flight_tick()
	world.sync_flight(state, 0.0)
	world.end_flight_tick()
	var first: Vector3 = world._planet.position
	# Deliberately use a coarse 20 Hz simulation step; render four frames in it.
	state.position += Vector3.BACK * 30.0
	state.altitude += 30.0
	state.simulation_time = 0.05
	state.orientation = Basis(Vector3.UP, 0.01) * state.orientation
	world.begin_flight_tick()
	world.sync_flight(state, 0.05)
	world.end_flight_tick()
	var last: Transform3D = world._planet.transform
	var rocket: Transform3D = world._rocket.transform
	var altitude: float = world._last_altitude
	var previous_position := first
	var previous_image: Image
	for fraction in [0.25, 0.5, 0.75, 1.0]:
		world.present_flight_frame(fraction)
		assert(world._planet.position.distance_to(first.lerp(last.origin, fraction)) < 0.1, "Planet advances on every display frame between simulation ticks")
		assert(world._planet.position.distance_to(previous_position) > 7.0, "Horizon does not hold then jump at the simulation cadence")
		previous_position = world._planet.position
		var observer: Vector3 = (world.camera.global_position - world._planet.global_position) * 0.001
		for material in [world._planet.material_override, world._sky_material, world._clouds.composite_material]:
			assert(Vector3(material.get_shader_parameter("camera_planet_km")).distance_to(observer) < 0.0001, "Terrain, sky and clouds use the displayed camera/planet pose")
		var expected_focus: Vector3 = world._rocket.transform * Vector3(0, world._capsule_center_local, 0)
		assert(world._camera_focus.distance_to(expected_focus) < 0.001, "Camera tracks the displayed vessel attitude")
		if DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			frame.save_png("/tmp/aphelion-flight-interpolation-%.2f.png" % fraction)
			if previous_image != null:
				assert(frame.get_data() != previous_image.get_data(), "Each intermediate pose reaches the renderer")
			previous_image = frame
	world.present_flight_frame(0.5)
	var camera_before: Basis = world.camera.basis
	world.orbit_camera(Vector2(5, 3))
	assert(not world.camera.basis.is_equal_approx(camera_before), "Mouse orbit responds between physics ticks")
	world.begin_flight_tick()
	assert(world._planet.transform.is_equal_approx(last), "Next physics tick restores the actual planet pose")
	assert(world._rocket.transform.is_equal_approx(rocket), "Next physics tick restores the actual vessel pose")
	assert(is_equal_approx(world._last_altitude, altitude), "Render interpolation never accumulates into simulation altitude")
	world.end_flight_tick()
	world.present_flight_frame(0.3, true)
	world.present_flight_frame(0.1)
	assert(world._planet.transform.is_equal_approx(last), "Pause/resume cannot rewind to an old interpolation pose")
	# An explicit rebase, such as staging or returning from the map, must snap.
	state.position += Vector3(2000, 0, 0)
	world.sync_flight(state, 0.0)
	var rebased: Transform3D = world._planet.transform
	world.present_flight_frame(0.1)
	assert(world._planet.transform.is_equal_approx(rebased), "Explicit sync discards stale interpolation history")
	world.begin_flight_tick()
	world.sync_flight(state, 0.0)
	world.end_flight_tick(false)
	world.present_flight_frame(0.1)
	assert(world._planet.transform.is_equal_approx(rebased), "Rails warp can snap without sweeping across the planet")
	world.set_mode("workshop")
	var workshop: Transform3D = world.camera.transform
	world.present_flight_frame(0.5)
	assert(world.camera.transform.is_equal_approx(workshop), "Workshop does not inherit flight interpolation")
	world.queue_free()
	await process_frame
	print("PASS: smooth flight scenery, camera/uniform alignment, physics restoration, rebase and workshop reset")
	quit()
