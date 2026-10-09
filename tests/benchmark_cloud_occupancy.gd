extends SceneTree
## Sequential alternating reference/candidate viewport measurements.
## --resolution 1280x720 --disable-vsync --script res://tests/benchmark_cloud_occupancy.gd -- /tmp/reference-directory
## Reference directory contains the original cloud_layer.gd and clouds.gdshader.
const World = preload("res://scripts/world_view.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const SETTINGS = ["both", "regular", "storm", "empty", "disabled", "sparse"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		push_error("Provide a reference directory and a graphical display")
		quit(1)
		return
	var reference_script = load(args[0].path_join("cloud_layer.gd"))
	var reference: MeshInstance3D = reference_script.new()
	var reference_shader := Shader.new()
	reference_shader.code = FileAccess.get_file_as_string(args[0].path_join("clouds.gdshader"))
	reference.material_override.shader = reference_shader
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._clouds.get_parent().add_child(reference)
	var noise: NoiseTexture3D = world._clouds.material_override.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty(): await noise.changed
	var definition: Resource = Surface.home().definition.duplicate()
	var original: Image = definition.cloud_weather.snapshot()
	var variants := {}
	for setting in ["both", "regular", "storm", "empty"]:
		var map := original.duplicate() as Image
		for y in range(map.get_height()):
			for x in range(map.get_width()):
				var c := original.get_pixel(x, y)
				if setting == "regular": c.a = 0.0
				elif setting == "storm": c = Color(0, 0, 0, c.a)
				elif setting == "empty": c = Color(0, 0, 0, 0)
				map.set_pixel(x, y, c)
		var weather := Weather.new()
		weather.restore(map)
		weather.has_clouds() # Prepare CPU cache before any warmup/timing.
		variants[setting] = weather
	var sparse := Weather.new()
	sparse.stamp(Vector3.UP, 0.025, Tiles.tile("mushroom"), 1.0)
	sparse.stamp(Vector3(0, 1, -0.04).normalized(), 0.03, Tiles.tile("stratocumulus"), 0.8)
	sparse.has_clouds()
	variants["sparse"] = sparse
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var results := []
	for altitude in [30.0, 3850.0, 100000.0]:
		world.sync_flight({"position": Vector3(0, altitude, 0), "altitude": altitude, "orientation": Basis.IDENTITY,
			"engine_on": false, "fuel": 0.0, "boosters_attached": false, "capsule_only": false, "chute_deployed": false}, 0.0)
		world._rocket.hide()
		world._landscape.hide()
		world.camera.position = Vector3.ZERO
		world.camera.look_at(Vector3(0, 700 if altitude < 10000 else -1000, -1000), Vector3.UP)
		world.set_sun_direction(Vector3(0, 0.8, -0.6))
		var data := {}
		for setting in SETTINGS:
			data[setting] = {"reference": {"gpu": [], "frame": []}, "candidate": {"gpu": [], "frame": []}}
		for trial in range(4):
			var order: Array = SETTINGS.duplicate()
			if trial % 2 == 1: order.reverse()
			for setting in order:
				definition.cloud_weather = variants[setting] if setting != "disabled" else variants["empty"]
				var observer: Vector3 = (world.camera.global_position - world._planet.global_position) * 0.001
				for version in (["reference", "candidate"] if trial % 2 == 0 else ["candidate", "reference"]):
					reference.update_weather(definition, observer, world._sun_direction, setting != "disabled" and version == "reference")
					world._clouds.update_weather(definition, observer, world._sun_direction, setting != "disabled" and version == "candidate")
					for frame in range(30): await process_frame
					var batch_gpu := []
					var batch_frame := []
					for frame in range(50):
						var start := Time.get_ticks_usec()
						await process_frame
						await RenderingServer.frame_post_draw
						batch_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
						batch_frame.append((Time.get_ticks_usec() - start) / 1000.0)
					data[setting][version].gpu.append_array(batch_gpu)
					data[setting][version].frame.append_array(batch_frame)
					batch_gpu.sort()
					batch_frame.sort()
					print("BATCH altitude=%.0f setting=%s trial=%d version=%s gpu=%.3f frame=%.3f" % [altitude, setting, trial, version, batch_gpu[25], batch_frame[25]])
		for setting in data:
			for version in data[setting]:
				var gpu: Array = data[setting][version].gpu
				var frame: Array = data[setting][version].frame
				gpu.sort()
				frame.sort()
				var result := {"altitude": altitude, "setting": setting, "version": version,
					"gpu_ms": gpu[100], "frame_ms": frame[100], "frame_p95_ms": frame[190]}
				results.append(result)
				print("RESULT ", JSON.stringify(result))
	world.free()
	quit()
