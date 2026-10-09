extends "res://tests/test_atmosphere.gd"
## Run with --disable-vsync. Alternating pairs reduce desktop-load bias.

func _run() -> void:
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	# Clouds integrate offscreen at reduced resolution; count that pass too.
	var lowres_rid: RID = world._clouds.lowres_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(lowres_rid, true)
	for altitude in [30.0, 3850.0, 100000.0]:
		_pose(Vector3(0, altitude, 0))
		world._landscape.hide()
		world.camera.position = Vector3.ZERO
		world.camera.look_at(Vector3(0, 700 if altitude < 10000.0 else -1000, -1000), Vector3.UP)
		world.set_sun_direction(Vector3(0, 0.8, -0.6))
		for frame in range(30): await process_frame
		var clear: Array[float] = []
		var cloudy: Array[float] = []
		for pair in range(4):
			for enabled in ([false, true] if pair % 2 == 0 else [true, false]):
				world._clouds.visible = enabled
				for frame in range(6): await process_frame
				for frame in range(20):
					await process_frame
					await RenderingServer.frame_post_draw
					var gpu := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
					if enabled: gpu += RenderingServer.viewport_get_measured_render_time_gpu(lowres_rid)
					if enabled: cloudy.append(gpu)
					else: clear.append(gpu)
		clear.sort()
		cloudy.sort()
		print("GPU altitude %.0f m: clear %.3f ms; cloudy %.3f ms; delta %.3f ms" % [altitude, clear[40], cloudy[40], cloudy[40]-clear[40]])
	world.queue_free()
	await process_frame
	quit()
