extends "res://tests/test_atmosphere.gd"
## Run with --disable-vsync. Alternating pairs reduce desktop-load bias.
## Counts the main view plus the clouds' offscreen march and resolve passes.
## CLOUD_SCALE pins the offscreen resolution (no altitude scaling).

func _gpu(viewport: Viewport) -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())

func _run() -> void:
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	var clouds: Node = world._clouds
	if OS.get_environment("CLOUD_SCALE") != "":
		clouds.resolution_scale = float(OS.get_environment("CLOUD_SCALE"))
		clouds.altitude_scaling = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var lowres: SubViewport = clouds.lowres_viewport()
	var resolves: Array = clouds._resolve
	for viewport in [lowres] + resolves:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var altitudes := [30.0, 3850.0, 18000.0, 52000.0, 100000.0]
	if OS.get_environment("CLOUD_ALTITUDES") != "":
		altitudes = Array(OS.get_environment("CLOUD_ALTITUDES").split(",")).map(func(value: String) -> float: return float(value))
	for altitude in altitudes:
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
				clouds.visible = enabled
				for frame in range(6): await process_frame
				for frame in range(20):
					await process_frame
					await RenderingServer.frame_post_draw
					var gpu := _gpu(root)
					if enabled:
						# One resolve target renders per frame, alternately. Far out
						# the composite integrates every pixel and these stop; their
						# last timings would linger.
						if lowres.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
							gpu += _gpu(lowres) + (_gpu(resolves[0]) + _gpu(resolves[1])) * 0.5
						cloudy.append(gpu)
					else:
						clear.append(gpu)
		clear.sort()
		cloudy.sort()
		print("GPU altitude %.0f m: clear %.3f ms; cloudy %.3f ms; delta %.3f ms" % [altitude, clear[40], cloudy[40], cloudy[40] - clear[40]])
	world.queue_free()
	await process_frame
	quit()
