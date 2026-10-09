extends SceneTree

const World = preload("res://scripts/world_view.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._planet_lod = 1
	world._update_planet_lod(float(world.PlanetSurface.home().definition.relief) * 1.5)
	assert(world._planet_lod == 0 and world._planet.mesh == world.PlanetSurface.home().build(), "Near mountain tops the rendered mesh matches collision, even descending from a coarse LOD")
	for altitude: float in [100.0, 80000.0]:
		world._last_altitude = altitude
		for surface_up: Vector3 in [Vector3.UP, Vector3(1, 2, 3).normalized()]:
			world._surface_up = surface_up
			for direction: float in [-1.0, 1.0]:
				world._pitch = 0.0
				world._update_camera()
				var previous: Basis = world.camera.basis
				var start: Transform3D = world.camera.transform
				for step in range(1440):
					world.orbit_camera(Vector2(0.0, direction * TAU / 720.0 / 0.005))
					var current: Basis = world.camera.basis
					assert(current.is_finite(), "Flight camera remains finite at poles")
					assert(current.y.dot(previous.y) > 0.999, "Flight camera crosses poles and wraps without flipping")
					assert(current.x.dot(previous.x) > 0.999, "Camera right stays continuous")
					assert(current.z.dot((world.camera.position-world._camera_focus).normalized()) > 0.9999, "Camera keeps the rocket centered")
					previous = current
				assert(world.camera.position.distance_to(start.origin) < 0.01, "Two full vertical orbits return to the starting view")
	var flight = preload("res://scripts/flight_model.gd").new()
	flight.reset(world._design)
	flight.state.status = "flying"
	flight.state.position = Vector3(0, 1000, 0)
	flight.state.orientation = Basis(Vector3.FORWARD, 0.6)
	flight.telemetry()
	world.sync_flight(flight.state, 0.0)
	var focus_before: Vector3 = world._camera_focus + flight.state.position
	var camera_before: Vector3 = world.camera.position + flight.state.position
	assert(world._camera_focus.is_equal_approx(world._rocket.transform * Vector3(0, world._capsule_center_local, 0)), "Flight tracks control capsule before separation")
	var original_core: Node3D = world._lower_parts[0]
	flight.state.engine_on = true
	flight.state.throttle = 0.4
	flight._separate_core()
	world.sync_flight(flight.state, 0.0)
	assert((world._camera_focus + flight.state.position).distance_to(focus_before) < 0.001, "Separation preserves control capsule target in world space")
	assert((world.camera.position + flight.state.position).distance_to(camera_before) < 0.01, "Separation preserves camera position")
	assert(original_core.get_parent() == world._detached_nodes[0], "Separation reuses the loaded stage without cloning meshes")
	var exhaust: Array[Node3D] = world._detached_nodes[0].get_meta("exhaust_nodes")
	assert(not exhaust.is_empty(), "Detached core retains exhaust nodes")
	for flame in exhaust:
		assert(flame.is_visible_in_tree(), "Burning detached engine remains visibly lit")
		assert(flame.scale.y > 0.3 and flame.scale.y < 0.5, "Detached exhaust retains release throttle")
		for mesh in flame.get_children():
			if mesh is MeshInstance3D and mesh.material_override is ShaderMaterial:
				assert(float(mesh.material_override.get_shader_parameter("thrust_intensity")) > 0.0, "Original engine shutdown does not extinguish detached exhaust")
	var debris_transform: Transform3D = world._detached_nodes[0].transform
	flight.state.orientation = Basis(Vector3.RIGHT, 1.0)
	world.sync_flight(flight.state, 0.0)
	assert(world._detached_nodes[0].transform.is_equal_approx(debris_transform), "Capsule rotation does not rotate or translate detached parts")
	assert(world._camera_focus.is_equal_approx(world._rocket.transform * Vector3(0, world._capsule_center_local, 0)), "Camera continues tracking control capsule during rotation")
	flight.state.detached[0].fuel = 0.0
	world.sync_flight(flight.state, 0.0)
	for flame in exhaust:
		assert(not flame.visible, "Detached exhaust shuts off at fuel exhaustion")
	var booster_design: Dictionary = world._design.duplicate(true)
	booster_design.boosters = true
	world.set_design(booster_design)
	flight.reset(booster_design)
	flight.state.status = "flying"
	flight.state.position = Vector3(0,1000,0)
	flight.state.boosters_on = true
	world.sync_flight(flight.telemetry(), 0.0)
	var original_boosters: Array[Node3D] = world._booster_nodes.duplicate()
	flight._separate_boosters()
	flight._separate_core()
	world.sync_flight(flight.telemetry(), 0.0)
	assert(world._detached_nodes.size() == 3, "Both boosters and core can transfer during one stage")
	for index in range(2):
		assert(original_boosters[index].get_parent() == world._detached_nodes[index], "Booster transfer preserves source indexing")
		assert(original_boosters[index].is_visible_in_tree(), "Transferred booster remains visible")
		for flame in world._detached_nodes[index].get_meta("exhaust_nodes"):
			assert(flame.is_visible_in_tree(), "Released solid booster retains its exhaust")
	flight.state.destroyed = true
	flight._queue_surface_explosion(flight.state.position, 3.0)
	world.sync_flight(flight.telemetry(), 0.0)
	assert(not world._rocket.visible, "Destructive impact hides the controlled hull")
	assert(world._impact_effects.size() == 1, "Destructive impact creates a visible explosion effect")
	assert(flight.state.surface_impacts.is_empty(), "Rendering consumes the explosion event once")
	world.set_design(booster_design)
	assert(world._rocket.visible, "Rebuilding restores the craft after destruction")
	world.set_mode("workshop")
	world.workshop_camera_view("Front")
	world.orbit_camera(Vector2(0, PI / 0.005))
	assert(absf(world._pitch) > 3.0, "Workshop also supports unrestricted vertical orbit")
	print("PASS: free flight camera completes full rotations in both directions at low and high altitudes without flips.")
	world.free()
	quit(0)
