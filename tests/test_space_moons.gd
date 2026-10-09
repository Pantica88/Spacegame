extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Map = preload("res://scripts/orbital_map.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const Flight = preload("res://scripts/flight_model.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var home: Resource = ResourceLoader.load("res://assets/planets/verdant.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP).duplicate(true)
	if home.moons.is_empty():
		var moon := Definition.new()
		moon.planet_name = "Test moon"
		moon.radius = 16000.0
		moon.has_ocean = false
		moon.launch_site = false
		home.moons.append(moon)
	home.set_meta("source_planet_path", "res://assets/planets/verdant.tres")
	World.PlanetSurface.reset_home(home)
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	assert(world._moons.size() == home.moons.size())
	var moon: MeshInstance3D = world._moons[0]
	assert(moon.visible and moon.mesh == moon.get_meta("terrain").preview_mesh())
	assert(moon.material_override.get_shader_parameter("distant_surface_smoothing_enabled") != true, "Moon retains its terrain model at a distance")
	assert(bool(world._planet.material_override.get_shader_parameter("distant_surface_smoothing_enabled")), "Only the home planet uses distant surface smoothing")
	var time := 12345.0
	var offset := World.SolarBody.moon_offset(home.moons[0], time)
	var position: Vector3 = Vector3(0, -600000, 0) + offset + Vector3(0.4, 0.3, 1.0).normalized() * home.moons[0].radius * 5.0
	var state := {"position": position, "altitude": position.distance_to(Vector3(0, -600000, 0)) - 600000.0, "simulation_time": time, "time": 0.0}
	world.sync_flight(state, 0.0)
	assert((moon.position - world._planet.position).is_equal_approx(offset), "Flight moon uses the saved orbit and rebases with the craft")
	assert(world.camera.far > world.camera.position.distance_to(world._planet.position) + home.radius, "Planet remains fully inside the far plane at moon distances")
	assert(world.camera.far > world.camera.position.distance_to(moon.position) + home.moons[0].radius, "Moon is inside the far plane")
	assert(Vector3(moon.material_override.get_shader_parameter("camera_planet_km")).is_equal_approx((world.camera.position - moon.position) * 0.001))
	var map := Map.new()
	map.source_world = world
	root.add_child(map)
	map.hide()
	map.state = state
	map._update_system()
	var moon_index := map.home_index + 1
	assert((map.bodies[moon_index].position - map.globe.position).is_equal_approx(offset * 0.001), "Flight and map moon positions agree")
	map._update_camera()
	assert(Vector3(moon.material_override.get_shader_parameter("eclipse_center_km")).is_equal_approx(-offset * 0.001), "Flight eclipse follows the planet after rebasing")
	assert(is_equal_approx(float(moon.material_override.get_shader_parameter("eclipse_radius_km")), home.radius * 0.001))
	assert(bool(moon.material_override.get_shader_parameter("foreground_atmosphere_enabled")), "Moon renders behind the home atmosphere")
	assert(Vector3(moon.material_override.get_shader_parameter("foreground_camera_planet_km")).is_equal_approx((world.camera.position - world._planet.position) * 0.001))
	assert(Vector3(map.bodies[moon_index].material_override.get_shader_parameter("eclipse_center_km")).is_equal_approx(-offset * 0.001), "Map eclipse uses the same physical distances as flight")
	assert(is_equal_approx(float(moon.material_override.get_shader_parameter("eclipse_sun_radius_km")), World.SolarBody.RADIUS * 0.001), "Flight eclipse uses the finite solar disk")
	assert(is_equal_approx(float(map.bodies[moon_index].material_override.get_shader_parameter("eclipse_sun_radius_km")), World.SolarBody.RADIUS * 0.001), "Map and flight share the solar disk")
	assert(Vector3(moon.material_override.get_shader_parameter("sun_direction")).is_equal_approx((World.SolarBody.POSITION - (Vector3(0, -600000, 0) + offset)).normalized()), "Moon sunlight stays in the physical frame after rebasing and rotation")
	world.camera.look_at(moon.position, Vector3.UP)
	world._update_atmosphere()
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/flight-space-moon.png")
	var period := float(home.moons[0].orbit_period_days) * 86400.0
	world.set_planet_time(time + period * 0.25)
	var quarter_offset: Vector3 = moon.position - world._planet.position
	assert(absf(offset.normalized().dot(quarter_offset.normalized())) < 0.0001, "Moon advances a quarter orbit in a quarter period")
	map.state["simulation_time"] = time + period * 0.25
	map._update_system()
	assert((map.bodies[moon_index].position - map.globe.position).is_equal_approx(quarter_offset * 0.001), "Map tracks flight moon motion")
	assert(not (moon.position - world._planet.position).is_equal_approx(offset), "Moon moves with world time")
	var flight := Flight.new()
	flight.ignite()
	flight.state.time = time
	flight.state.capsule_only = true
	flight.state.engine_on = false
	var moon_terrain: RefCounted = flight._debris_surfaces(time)[1].terrain
	var landing_up := Vector3(0.4, 0.3, 1.0).normalized()
	var landing_contact: Dictionary = moon_terrain.contact(landing_up, time)
	var landing_radial: Vector3 = landing_up * float(landing_contact.radius)
	var moon_center := Vector3(0, -600000, 0) + offset
	var orbit_velocity := (World.SolarBody.moon_offset(home.moons[0], time + 1.0) - World.SolarBody.moon_offset(home.moons[0], time - 1.0)) * 0.5
	var gravity_probe := Flight.new()
	gravity_probe.ignite()
	gravity_probe.state.time = time
	gravity_probe.state.capsule_only = true
	gravity_probe.state.position = moon_center + landing_up * (float(home.moons[0].radius) + 1000.0)
	gravity_probe.state.velocity = orbit_velocity
	gravity_probe.step(0.1, {"throttle": 0.0})
	assert(Vector3(gravity_probe.state.acceleration_vector).dot(-landing_up) > 1.0, "Moon gravity attracts the active craft")
	assert(gravity_probe.state.reference_body == home.moons[0].planet_name, "Flight instruments switch to the nearby moon")
	flight.state.position = moon_center + landing_radial + landing_up
	flight.state.velocity = orbit_velocity + moon_terrain.surface_velocity(landing_radial) - landing_up * 2.0
	flight.step(1.0, {"throttle": 0.0})
	assert(flight.state.status == "landed", "Capsule can land softly on a moving moon")
	assert(flight.state.landing_body == home.moons[0].planet_name and flight.state.reference_body == home.moons[0].planet_name)
	assert(float(flight.state.terrain_clearance) < 0.1, "Moon landing touches the rendered terrain")
	assert(float(flight.state.impact_speed) < 8.0, "Moon landing speed is relative to its orbiting surface")
	world.reload_planet()
	assert(world._moons.size() == home.moons.size(), "Reload replaces moon models without duplicates")
	world.set_mode("workshop")
	assert(world._moons.all(func(body): return not body.visible))
	map.free()
	world.free()
	print("PASS: flight moon terrain, orbit, gravity, landing, rebasing, clipping, map agreement and reload")
	quit()
