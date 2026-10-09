extends SceneTree

const World = preload("res://scripts/world_view.gd")
var world: Node3D

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	assert(is_instance_valid(world._heat_trail) and world._heat_trail.mesh != null, "Rollout prepares the wake before heating")
	assert(not world._heat_trail.visible, "Prepared wake stays hidden while cold")
	var prepared_mesh: Mesh = world._heat_trail.mesh
	var prepared_builds: int = world._heat_trail.profile_build_count
	world._distance = 19.0
	var state := {"position": Vector3(0, 12000, 0), "altitude": 12000.0,
		"orientation": Basis(Vector3.FORWARD, -PI / 2.0), "status": "flying",
		"engine_on": false, "fuel": 0.0, "boosters_attached": true,
		"heat_glow": 0.7, "heating_rate": 180.0, "air_velocity": Vector3(1000, -180, 0)}
	for pose in ["oblique", "broadside", "reverse", "cold", "vacuum"]:
		if pose == "broadside": state.air_velocity = Vector3(0, -800, 0)
		if pose == "reverse": state.air_velocity = Vector3(-800, 0, 0)
		if pose == "cold": state.heat_glow = 0.0
		if pose == "vacuum":
			state.heat_glow = 0.7
			state.heating_rate = 0.0
		world.sync_flight(state, 0.07)
		assert(world._heat_trail.mesh == prepared_mesh and world._heat_trail.profile_build_count == prepared_builds, "Heat onset and cooling reuse the prepared mesh")
		if pose == "cold":
			assert(world._heated_meshes.is_empty(), "Cooled hull restores original materials")
			assert(not world._heat_trail.visible, "Cooled vessel has no wake")
		else:
			assert(world._heated_meshes.size() > 0, "Heat follows actual part meshes")
			for mesh in world._heated_meshes:
				assert(mesh.material_overlay == world._heat_material)
		if pose in ["oblique", "broadside", "reverse"]:
			assert(world._heat_trail.visible, "Atmospheric heating produces a wake")
			assert(world._heat_trail.flow_direction.dot(Vector3(state.air_velocity).normalized()) > 0.999, "Wake follows air velocity in every attitude")
			assert(not world._heated_meshes.has(world._heat_trail), "Wake is excluded from hull overlays")
		if pose == "vacuum":
			assert(not world._heat_trail.visible, "Residual heat in vacuum has no wake")
			assert(world._heat_halo_material.get_shader_parameter("flow_strength") == 0.0)
		if DisplayServer.get_name() != "headless":
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			capture.save_png("/tmp/aphelion-heat-%s.png" % pose)
			if pose == "reverse":
				world.sync_flight(state, 0.05)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var moved := root.get_texture().get_image()
				moved.save_png("/tmp/aphelion-heat-motion.png")
				var changed_pixels := 0
				for y in range(0, capture.get_height(), 4):
					for x in range(0, capture.get_width(), 4):
						var before := capture.get_pixel(x,y)
						var after := moved.get_pixel(x,y)
						if absf(before.r-after.r)+absf(before.g-after.g)+absf(before.b-after.b) > 0.08: changed_pixels += 1
				assert(changed_pixels > 100, "Flow visibly moves across the hull and wake in 50 ms")
	state.heating_rate = 180.0
	state.air_velocity = Vector3(1000, 0, 0)
	world.sync_flight(state, 0.1)
	assert(world._heat_trail.path_count > 40, "Many hull-following paths replace the detached cone")
	var geometry: Array = world._heat_trail.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = geometry[Mesh.ARRAY_VERTEX]
	for index in range(0, vertices.size(), 6):
		assert(world._heat_trail._distance(vertices[index]) >= 0.04, "Plasma seeds stay outside the sampled hull")
	var phase: float = world._heat_trail.flow_phase
	world.sync_flight(state, 0.1)
	var fast_advance: float = world._heat_trail.flow_phase - phase
	state.air_velocity = Vector3(100, 0, 0)
	phase = world._heat_trail.flow_phase
	world.sync_flight(state, 0.1)
	assert(fast_advance > (world._heat_trail.flow_phase - phase) * 4.0, "1000 m/s visibly advects much faster than 100 m/s")
	phase = world._heat_trail.flow_phase
	world.sync_flight(state, 0.0)
	assert(world._heat_trail.flow_phase == phase, "Paused flow does not animate")
	_test_turn_transitions(state)
	if DisplayServer.get_name() != "headless": await _capture_continuous_turn(state)
	var detached: MeshInstance3D = world._heated_meshes[0]
	detached.reparent(world)
	world.sync_flight(state, 0.0)
	assert(detached.material_overlay == null, "Staged parts release the vessel heat overlay")
	detached.free()
	world.set_mode("workshop")
	assert(world._heated_meshes.is_empty(), "Workshop clears flight heat")
	world.set_design({"tanks": 1, "engine": "kestrel", "boosters": false})
	world.set_mode("flight")
	state.capsule_only = true
	world.sync_flight(state, 0.0)
	assert(world._heated_meshes.size() > 0, "Rebuilt recovery craft receives heat overlay")
	world.free()
	print("PASS: smooth plasma turns, continuous motion, hull clearance, cooling, staging and rebuild")
	quit(0)


func _test_turn_transitions(state: Dictionary) -> void:
	var wake = world._heat_trail
	var original_mesh: Mesh = wake.mesh
	var builds: int = wake.profile_build_count
	var phase: float = wake.flow_phase
	var last_flow := Vector3.ZERO
	for frame in range(121):
		state.orientation = Basis(Vector3.BACK, deg_to_rad(float(frame) * 3.0))
		state.air_velocity = Vector3(1000, 0, 0)
		world.sync_flight(state, 0.0)
		var expected: Vector3 = -(Basis(state.orientation).inverse() * Vector3.RIGHT)
		var actual: Vector3 = wake._material.get_shader_parameter("local_flow")
		assert(actual.distance_to(expected) < 0.0001, "Airflow follows every attitude sample without waiting for a rebuild")
		if frame > 0: assert(actual.distance_to(last_flow) > 0.01, "Consecutive turn samples move the paths")
		assert(wake.mesh == original_mesh and wake.profile_build_count == builds, "An entire turn keeps the same strands and hull profile")
		last_flow = actual
	assert(wake.flow_phase == phase, "Paused flow keeps its motion phase")
	for speed in [100.0, 1000.0, 1900.0]:
		state.air_velocity = Vector3(speed, 0, 0)
		world.sync_flight(state, 0.016)
		assert(wake.mesh == original_mesh, "Speed changes cannot swap wake geometry")
	# Keep attitude fixed while reversing movement; the wake must reverse too.
	for travel in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN]:
		state.air_velocity = travel * 1000.0
		world.sync_flight(state, 0.0)
		var local_flow: Vector3 = wake._material.get_shader_parameter("local_flow")
		assert((world._rocket.global_basis * local_flow).distance_to(-travel) < 0.0001, "Flame direction follows movement, independent of the nose")
	assert(wake.get_child_count() == 0, "No overlapping wake copies or transition queue remain")


func _capture_continuous_turn(state: Dictionary) -> void:
	state.orientation = Basis(Vector3.FORWARD, -PI / 2.0)
	state.air_velocity = Vector3(-1000, 0, 0)
	world.sync_flight(state, 0.0)
	for frame in range(4):
		state.air_velocity = Vector3(-1000, 0, 0).rotated(Vector3.BACK, deg_to_rad(frame * 5.0))
		world.sync_flight(state, 0.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aphelion-continuous-turn-%d.png" % frame)
