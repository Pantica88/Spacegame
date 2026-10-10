extends "res://tests/test_atmosphere.gd"
## Run with --disable-vsync. Rotating mode order reduces desktop-load bias.
## Times the scene without clouds, the reduced-resolution clouds and the
## full-resolution prototype (CloudLayer.full_resolution) and its compute-shader
## version (CloudLayer.compute).

func _gpu(viewport: Viewport) -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())

func _run() -> void:
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	var clouds: Node = world._clouds
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	# Clouds integrate and resolve offscreen; count those passes too.
	var lowres: SubViewport = clouds.lowres_viewport()
	var resolves: Array[SubViewport] = clouds.resolve_viewports()
	for viewport in [lowres] + resolves:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var modes := ["clear", "reduced", "full", "compute"]
	for altitude in [30.0, 3850.0, 18000.0, 100000.0]:
		_pose(Vector3(0, altitude, 0))
		world._landscape.hide()
		world.camera.position = Vector3.ZERO
		world.camera.look_at(Vector3(0, 700 if altitude < 10000.0 else -1000, -1000), Vector3.UP)
		world.set_sun_direction(Vector3(0, 0.8, -0.6))
		for frame in range(30): await process_frame
		var samples := {}
		for mode in modes: samples[mode] = []
		for round in range(6):
			for index in range(modes.size()):
				var mode: String = modes[(index + round) % modes.size()]
				clouds.visible = mode != "clear"
				clouds.full_resolution = mode == "full"
				clouds.compute = mode == "compute"
				for frame in range(8): await process_frame
				for frame in range(20):
					await process_frame
					await RenderingServer.frame_post_draw
					var gpu := _gpu(root)
					# Compute passes run inside the main viewport.
					if mode == "reduced" or mode == "full":
						# One resolve target renders per frame, alternately.
						gpu += _gpu(lowres) + (_gpu(resolves[0]) + _gpu(resolves[1])) * 0.5
					samples[mode].append(gpu)
		var medians := {}
		for mode in modes:
			samples[mode].sort()
			medians[mode] = samples[mode][samples[mode].size() / 2]
		print("GPU altitude %.0f m: clear %.3f ms; reduced +%.3f; full +%.3f; compute +%.3f" % [altitude, medians.clear,
			medians.reduced - medians.clear, medians.full - medians.clear, medians.compute - medians.clear])
	world.queue_free()
	await process_frame
	quit()
