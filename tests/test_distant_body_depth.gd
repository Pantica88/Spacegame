extends SceneTree
## Graphical regression: solid body interiors must not fall through to the sky.
const World = preload("res://scripts/world_view.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This regression requires a graphical display.")
		quit(1)
		return
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	world._environment.background_mode = Environment.BG_COLOR
	world._environment.background_color = Color(1, 0, 1)
	var failures := 0
	for altitude: float in [2500000.0, 2855160.0, 3000000.0, 3369640.0, 4000000.0, 10000000.0]:
		world.sync_flight({"position": Vector3(0, altitude, 0), "altitude": altitude, "simulation_time": 1637.0}, 0.0)
		var bodies: Array[MeshInstance3D] = [world._planet]
		bodies.append_array(world._moons)
		for body in bodies:
			world.camera.look_at(body.position, Vector3.FORWARD)
			world._update_atmosphere()
			if "--baseline" in OS.get_cmdline_user_args():
				world.camera.near = 0.5
			for frame in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			var radius := float(body.get_meta("terrain").definition.radius) if body != world._planet else World.PLANET_RADIUS
			var pixel_radius := radius / world.camera.position.distance_to(body.position) * capture.get_height() / (2.0 * tan(deg_to_rad(world.camera.fov) * 0.5))
			var center := Vector2(capture.get_size()) * 0.5
			var samples := 0
			var holes := 0
			for y in range(int(center.y - pixel_radius * 0.5), int(center.y + pixel_radius * 0.5) + 1):
				for x in range(int(center.x - pixel_radius * 0.5), int(center.x + pixel_radius * 0.5) + 1):
					var color := capture.get_pixel(x, y)
					samples += 1
					if color.r > 0.5 and color.b > 0.5 and color.g < 0.1:
						holes += 1
			if holes > 0:
				failures += 1
				print("FAIL: %s at %.0f m: %d/%d sky pixels inside body" % [body.name, altitude, holes, samples])
	world.free()
	if failures == 0:
		print("PASS: planet and moon interiors stay opaque across six escape altitudes")
	quit(1 if failures else 0)
