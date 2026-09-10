extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Map = preload("res://scripts/orbital_map.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var world := World.new()
	root.add_child(world)
	world.hide()
	var map := Map.new()
	map.source_world = world
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(map)
	assert(map.globe.mesh == Map.Surface.home().preview_mesh(), "Map uses the cached editor-resolution globe")
	var map_vertex_count: int = map.globe.mesh.surface_get_array_len(0)
	assert(map_vertex_count > world._planet.mesh.surface_get_array_len(0), "Map detail is independent of the coarser flight mesh")
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
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/orbital-map-local.png")
	assert(map.trajectory.mesh.get_surface_count() == 1)
	assert(map.marker.mesh == null)
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
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/orbital-map-system.png")
	assert(map.system_mode and map.bodies.size() == Map.PlanetList.load_all().filter(func(definition: Resource): return bool(definition.orbit_enabled)).size())
	assert(not map.globe.visible)
	assert(not map.history_node.visible and not map.history_tail_node.visible)
	map.reset_history(start)
	for sample_index in range(Map.HISTORY_LIMIT+10):
		map.record_flight({"position":Vector3(sample_index,1000,0),"time":float(sample_index)})
	assert(map.history.size() < Map.HISTORY_LIMIT)
	assert(map.history[0].is_equal_approx((start-Map.Physics.PLANET_CENTER)*0.001))
	map.reset_history(start)
	assert(map.history.size() == 1 and map.history_mesh.get_surface_count() == 0)
	print("PASS: local trajectory, apsides and resource-backed Solar System mode")
	quit()
