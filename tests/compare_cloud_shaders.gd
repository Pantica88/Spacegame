extends "res://tests/test_atmosphere.gd"
## Compare a candidate against a saved reference without changing sample budgets.
## --resolution 800x450 --disable-vsync --script res://tests/compare_cloud_shaders.gd -- /tmp/reference.gdshader
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not FileAccess.file_exists(args[0]):
		push_error("Provide the path of a saved reference cloud shader after --")
		quit(1)
		return
	var reference := Shader.new()
	reference.code = FileAccess.get_file_as_string(args[0])
	var candidate := load("res://assets/shaders/clouds.gdshader") as Shader
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	# Freeze the time-dependent starfield for strict pixel comparisons.
	var sky_reference := Shader.new()
	sky_reference.code = FileAccess.get_file_as_string("res://assets/shaders/sky.gdshader").replace("TIME", "0.0")
	world._sky_material.shader = sky_reference
	var material: ShaderMaterial = world._clouds.material_override
	var noise: NoiseTexture3D = material.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty(): await noise.changed
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var definition: Resource = Surface.home().definition
	var saved: Resource = definition.cloud_weather
	for family in ["saved", "low", "storm", "mixed", "clear", "procedural"]:
		if family == "saved":
			definition.cloud_weather = saved
		elif family == "procedural":
			definition.cloud_weather = null
		else:
			var weather := Weather.new()
			var map := Image.create(512, 256, false, Image.FORMAT_RGBA8)
			var weights := {"low": Color(0.4, 0.3, 0.3, 0), "storm": Color(0, 0, 0, 1),
				"mixed": Color(0.4, 0.2, 0.1, 0.3), "clear": Color(0, 0, 0, 0)}
			map.fill(weights[family])
			weather.restore(map)
			definition.cloud_weather = weather
		for altitude in [30.0, 3850.0, 10000.0, 100000.0, 1600000.0]:
			_pose(Vector3(0, altitude, 0))
			world._landscape.hide()
			world.camera.position = Vector3.ZERO
			world.camera.look_at(Vector3(0, 700 if altitude < 10000 else -1000, -1000), Vector3.UP)
			world.set_sun_direction(Vector3(0, 0.8, -0.6))
			var frames: Array[Image] = []
			var times: Array[float] = []
			for shader in [reference, candidate]:
				material.shader = shader
				world._update_atmosphere()
				for frame in range(8): await process_frame
				var samples: Array[float] = []
				for frame in range(16):
					await process_frame
					await RenderingServer.frame_post_draw
					samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				samples.sort()
				times.append(samples[samples.size() / 2])
				frames.append(root.get_texture().get_image())
			var max_delta := 0.0
			for y in range(frames[0].get_height()):
				for x in range(frames[0].get_width()):
					var a := frames[0].get_pixel(x, y)
					var b := frames[1].get_pixel(x, y)
					max_delta = maxf(max_delta, maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))))
			print("%s %.0fm: GPU %.3f -> %.3f ms; max RGB delta %.6f" % [family, altitude, times[0], times[1], max_delta])
			check(max_delta <= 1.01 / 255.0, "Reference pixels preserved: %s %.0fm" % [family, altitude])
	definition.cloud_weather = saved
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: reference cloud visuals preserved across all weather and altitude cases")
	quit(0 if failures.is_empty() else 1)
