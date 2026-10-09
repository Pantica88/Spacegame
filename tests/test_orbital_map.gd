extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Map = preload("res://scripts/orbital_map.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	# Round-trip a moon before creating the map, without changing planet assets.
	var home: Resource = ResourceLoader.load(Map.Surface.HOME.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP).duplicate(true)
	var moon := preload("res://scripts/planet_definition.gd").new()
	moon.planet_name = "Saved map moon"
	moon.radius = 12000.0
	moon.relief = 850.0
	moon.has_snow = false
	moon.has_ocean = false
	moon.launch_site = false
	moon.moon_orbit_distance_km = 400.0
	moon.orbit_enabled = false
	home.moons.append(moon)
	assert(ResourceSaver.save(home, "user://map-moon-test.tres") == OK)
	home = ResourceLoader.load("user://map-moon-test.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	home.set_meta("source_planet_path", Map.Surface.HOME.resource_path)
	Map.Surface.reset_home(home)
	var world := World.new()
	root.add_child(world)
	world.hide()
	# Reproduce opening the map while flight uses launch-relative projection.
	world._planet.material_override.set_shader_parameter("launch_origin_enabled", true)
	world._planet.material_override.set_shader_parameter("launch_origin_local", Vector3.UP * home.radius)
	world._planet.material_override.set_shader_parameter("launch_origin_view", Vector3(0, -12, -40))
	var map := Map.new()
	map.source_world = world
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(map)
	assert(map.planet_definitions.size() >= Map.PlanetList.load_all().size() + home.moons.size(), "All saved home moons are present")
	assert(map.globe.mesh == Map.Surface.home().preview_mesh(), "Map uses the cached editor-resolution globe")
	assert(map.globe.material_override.get_shader_parameter("launch_origin_enabled") == false, "Map terrain and atmosphere use the same planet-centered projection")
	assert(world._planet.material_override.get_shader_parameter("launch_origin_enabled") == true, "Map preserves flight's launch-relative projection")
	assert(map.globe.material_override.get_shader_parameter("distant_surface_smoothing_enabled") == false, "Home map preserves terrain and coast colors at orthographic camera distances")
	assert(world._planet.material_override.get_shader_parameter("distant_surface_smoothing_enabled") == true, "Map material changes preserve flight smoothing")
	var atmosphere := map.globe.get_node("MapAtmosphere") as MeshInstance3D
	assert(is_equal_approx(atmosphere.mesh.radius, home.radius + home.atmosphere_height), "Map haze extends to the saved atmosphere height")
	assert(is_equal_approx(atmosphere.material_override.get_shader_parameter("atmosphere_density_scale"), home.atmosphere_visual_density), "Map haze uses the planet's saved density")
	assert(is_equal_approx(map.globe.material_override.get_shader_parameter("atmosphere_scattering_exposure"), Map.MAP_HAZE_EXPOSURE), "Map enhances haze over the terrain itself")
	assert(is_equal_approx(atmosphere.material_override.get_shader_parameter("atmosphere_scattering_exposure"), Map.MAP_HAZE_EXPOSURE), "Terrain and outer atmosphere share scattering brightness")
	assert(world._planet.material_override.get_shader_parameter("atmosphere_scattering_exposure") == null or is_equal_approx(world._planet.material_override.get_shader_parameter("atmosphere_scattering_exposure"), 1.0), "Map haze adjustment leaves flight exposure unchanged")
	assert(atmosphere.material_override.get_shader_parameter("camera_forward").is_equal_approx(-map.camera.basis.z), "Atmosphere follows orthographic viewing direction")
	for index in range(map.bodies.size()):
		if map.planet_definitions[index].atmosphere_height == 0.0:
			assert(map.bodies[index].get_node_or_null("MapAtmosphere") == null, "Airless moons have no atmospheric haze")
	var map_vertex_count: int = map.globe.mesh.surface_get_array_len(0)
	assert(map_vertex_count >= world._planet.mesh.surface_get_array_len(0), "Map retains shared terrain detail independently of flight LOD")
	var flight_mesh: Mesh = world._planet.mesh
	world._planet.mesh = Map.Surface.home().render_mesh_for_lod(4)
	assert(map.globe.mesh.surface_get_array_len(0) == map_vertex_count, "Flight LOD changes cannot degrade the map")
	world._planet.mesh = flight_mesh
	map.hide()
	var start := Vector3(0,0,0)
	map.reset_history(start)
	map.record_flight({"position":Vector3(-20000,12000,0),"time":1.0})
	map.record_flight({"position":Vector3(-15000,24000,0),"time":2.0})
	assert(map.history.size() == 3, "History records while map is closed")
	assert(map.history[0].is_equal_approx((start-Map.Physics.PLANET_CENTER)*0.001))
	map.show()
	var test_radial := Vector3(0.45,0.34,0.82).normalized()*90000.0
	var test_velocity := test_radial.normalized().cross(Vector3.UP).normalized()*620.0
	map.state = {"position":Map.Physics.PLANET_CENTER+test_radial,"velocity":test_velocity,"time":100.0}
	map.zoom = 0.85
	map.yaw = 0.95
	map.pitch = 0.65
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/orbital-map-local.png")
	assert(map.trajectory.mesh.get_surface_count() == 1)
	assert(map.marker.mesh == null)
	assert(map.home_index >= 0)
	assert(map.bodies[map.home_index] == map.globe, "Home planet is not duplicated")
	assert(map.orbit_lines[map.home_index].is_visible_in_tree(), "Planet orbit is visible while focused locally")
	var orbit_points: PackedVector3Array = map.orbit_lines[map.home_index].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(orbit_points[0].length() < 0.1, "Home orbit passes through the home planet in the flight frame")
	assert(map.labels.any(func(label): return label.text == Map.Surface.home().definition.planet_name))
	assert(map.labels.size() >= 2)
	var path_vertices: PackedVector3Array = map.path_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var craft_screen := map.camera.unproject_position(map.marker.position)
	var path_screen_direction := (map.camera.unproject_position(path_vertices[1])-craft_screen).normalized()
	assert(map._craft_screen_direction(map.marker.position,craft_screen).dot(path_screen_direction) > 0.99)
	assert(map.history_mesh.get_surface_count() == 1)
	assert(map.history_tail_mesh.get_surface_count() == 1)
	assert(map.history_material.albedo_color != map.path_material.albedo_color)
	var focus_click := InputEventMouseButton.new()
	focus_click.button_index = MOUSE_BUTTON_LEFT
	focus_click.pressed = true
	focus_click.position = craft_screen
	map._gui_input(focus_click)
	map._process(1.0/120.0)
	assert(map.local_focus_craft)
	assert(map.camera.unproject_position(map.marker.position).distance_to(map.size*0.5) < 2.0)
	# Path and craft must follow the same telemetry without a 100 ms hold.
	var old_path: PackedVector3Array = map.path_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	map.state.position += Vector3(100,0,0)
	map._process(1.0/120.0)
	assert(map.marker.position.is_equal_approx((Vector3(map.state.position)-Map.Physics.PLANET_CENTER)*0.001))
	assert(map.labels[0].position == map.marker.position)
	var new_path: PackedVector3Array = map.path_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(new_path != old_path)
	assert(new_path[0].is_equal_approx(map.marker.position))
	map._process(1.0/120.0)
	assert(map.path_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == new_path)

	assert(map.prediction_kind == "Orbit")
	assert(map.path_material.albedo_color == Map.FUTURE_COLOR)
	map.local_focus_craft = false
	map.state = {"position":Map.Physics.PLANET_CENTER+test_radial,"velocity":-test_radial.normalized()*3000.0}
	map._process(1.0/60.0)
	assert(map.prediction_kind == "Impact", "Inbound escape-energy trajectories still hit the planet")
	assert(map.path_material.albedo_color == Map.IMPACT_COLOR)
	assert(map.impact_point.is_finite())
	assert(absf(map.impact_point.length()-float(Map.Surface.home().contact(map.impact_point*1000.0,float(map.state.get("time",0.0))).radius)*0.001) < 0.001)
	assert(map.labels.any(func(label): return label.text == "IMPACT"))
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/orbital-map-impact.png")
	map.state.velocity = test_radial.normalized()*3000.0
	map._process(1.0/60.0)
	assert(map.prediction_kind == "Escape", "Outbound escape must not show a past surface crossing")
	assert(map.path_material.albedo_color == Map.ESCAPE_COLOR)
	assert(not map.impact_point.is_finite())
	assert(not map.labels.any(func(label): return label.text == "IMPACT"))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(map.size.x-250,30)
	map._gui_input(click)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/orbital-map-system.png")
	assert(map.system_focus and map.bodies.size() == map.planet_definitions.size())
	assert(map.globe.visible and map.system_root.visible, "One scene retains the detailed planet and system orbits")
	assert(map.history_node.visible and map.history_tail_node.visible and map.trajectory.visible)
	assert(map.local_sun.visible and map.camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	var system_span := map.camera.size
	click.position = Vector2(map.size.x-90,30)
	map._gui_input(click)
	map._process(1.0/60.0)
	assert(not map.system_focus and map.camera.size < system_span)
	assert(map.orbit_lines[map.home_index].is_visible_in_tree(), "Returning to the planet retains planetary orbit lines")
	var local_span := map.camera.size
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	map._gui_input(wheel)
	map._process(1.0/60.0)
	assert(map.camera.size > local_span and map.globe.visible and map.system_root.visible, "Zoom changes framing within the same scene")
	var planet_screen := map.camera.unproject_position(map.globe.position)
	assert(map._planet_hit(planet_screen) == map.home_index, "Planet disk can be selected directly")
	click.position = planet_screen
	map._gui_input(click)
	map._process(1.0/60.0)
	assert(map.focus_index == map.home_index and not map.local_focus_craft)
	assert(map.camera.unproject_position(map.globe.position).distance_to(map.size*0.5) < 2.0)
	var other_index := 1 if map.home_index == 0 else 0
	var other_body: MeshInstance3D = map.bodies[other_index]
	assert(other_body.mesh is ArrayMesh, "Other planets use terrain models rather than placeholder spheres")
	assert(other_body.mesh == other_body.get_meta("terrain").preview_mesh())
	var other_material: ShaderMaterial = other_body.material_override
	assert(is_equal_approx(float(other_material.get_shader_parameter("BODY_RADIUS")), float(map.planet_definitions[other_index].radius)*0.001))
	map._focus_planet(other_index)
	map._process(1.0/60.0)
	var other_screen := map.camera.unproject_position(map.bodies[other_index].position)
	assert(other_screen.distance_to(map.size*0.5) < 2.0, "Focus centers other planets too")
	assert(map._planet_hit(other_screen) == other_index)
	var moon_index := -1
	for index in range(map.planet_definitions.size()):
		if map.planet_definitions[index].planet_name == "Saved map moon":
			moon_index = index
	assert(moon_index >= 0, "Saved moons are loaded into the map")
	assert(map.body_parents[moon_index] == map.home_index)
	assert(map.bodies[moon_index].visible and not map.orbit_lines[moon_index].visible, "Orbit toggle never hides a saved body")
	assert(map.bodies[moon_index].get_meta("terrain").definition.relief == 850.0)
	assert(not map.bodies[moon_index].get_meta("terrain").definition.has_snow)
	assert(is_equal_approx(map.bodies[moon_index].position.distance_to(map.globe.position), 400.0))
	assert(map.labels.any(func(label): return label.text == "Saved map moon"))
	var previous_moon_position: Vector3 = map.bodies[moon_index].position
	map.state.time = home.moons[-1].orbit_period_days * 86400.0 * 0.25
	map._focus_planet(moon_index)
	map._process(1.0 / 60.0)
	assert(not map.bodies[moon_index].position.is_equal_approx(previous_moon_position), "Moon advances along its saved orbit")
	assert(is_equal_approx(map.bodies[moon_index].position.distance_to(map.globe.position), 400.0))
	assert(map.orbit_lines[moon_index].position == map.globe.position)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/orbital-map-moon.png")
	assert(map.camera.unproject_position(map.bodies[moon_index].position).distance_to(map.size * 0.5) < 2.0)
	assert(map._planet_hit(map.camera.unproject_position(map.bodies[moon_index].position)) == moon_index)
	map.reset_history(start)
	for sample_index in range(Map.HISTORY_LIMIT+10):
		map.record_flight({"position":Vector3(sample_index,1000,0),"time":float(sample_index)})
	assert(map.history.size() < Map.HISTORY_LIMIT)
	assert(map.history[0].is_equal_approx((start-Map.Physics.PLANET_CENTER)*0.001))
	map.reset_history(start)
	assert(map.history.size() == 1 and map.history_mesh.get_surface_count() == 0)
	print("PASS: unified map, local and planetary orbits, labels, focus and flight history")
	map.free()
	world.free()
	quit()
