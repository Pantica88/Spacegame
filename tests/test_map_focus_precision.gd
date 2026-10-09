extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Map = preload("res://scripts/orbital_map.gd")
func _initialize():
	run.call_deferred()
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.disable_3d = true
	var world = World.new()
	root.add_child(world)
	world.hide()
	var map = Map.new()
	map.source_world = world
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(map)
	map.state = {"position":Vector3(0,30000,0),"velocity":Vector3(620,0,0),"time":100.0}
	for index in range(map.bodies.size()):
		map._focus_planet(index)
		for frame in range(10): await process_frame
		var started = Time.get_ticks_usec()
		var error = 0.0
		for frame in range(60):
			map.yaw += 0.02
			map.zoom = 0.05 if frame >= 30 else 1.0
			map.state["time"] += 0.1
			await process_frame
			var center = map.camera.unproject_position(map.bodies[index].global_position)
			error = max(error, center.distance_to(Vector2(map.viewport.size)*0.5))
			assert(map.viewport.transparent_bg, "Close view composites over the distant pass")
			assert(map.background_viewport.world_3d == map.viewport.world_3d, "Passes share map geometry")
			assert(map.background_camera.size == map.camera.size, "Zoom agrees across passes")
			assert(map.bodies[index].layers == 1, "Focused body renders only in the close pass")
			for distant in map.bodies + [map.local_sun]:
				if distant == map.bodies[index]: continue
				assert(distant.layers == 2, "Distant bodies render only in the background pass")
				var depth = -(map.background_camera.global_transform.affine_inverse() * distant.global_position).z
				assert(depth > map.background_camera.near and depth < map.background_camera.far, "Distant bodies stay inside the background depth range")
				assert(not map._map_position_behind(distant.position), "Distant labels are not rejected by the close camera")
		assert(error < 0.01, "Focused body must remain centered while orbiting and advancing time")
		assert(map.bodies[index].global_position.length() < 0.001, "Focused geometry renders at the origin")
		assert(map._planet_hit(Vector2(map.viewport.size)*0.5) == index, "Picking uses the rebased frame")
		print("FOCUS ", map.planet_definitions[index].planet_name, " ms=", (Time.get_ticks_usec()-started)/60000.0," center_error_px=",error," camera_distance=",map.camera.position.distance_to(map.bodies[index].global_position))
	map.system_focus = false
	map._process(1.0/60.0)
	assert(not map.viewport.transparent_bg and map.local_sun.layers == 1, "Leaving focus restores the single pass")
	assert(map.background_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	assert(map.render_origin == Vector3.ZERO and map.render_root.position == Vector3.ZERO, "Leaving focus restores the home frame")
	map.free()
	world.free()
	print("PASS: focused planet and moon geometry, projection and picking remain stable")
	quit()
