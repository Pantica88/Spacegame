extends "res://tests/test_atmosphere.gd"
## Fixed-camera planetary rendering benchmark. Requires a graphical display:
##   tools/run.sh --disable-vsync --resolution 1920x1080 --script res://tests/benchmark_planet_rendering.gd
## Environment:
##   BENCH_OUT       output directory (default /tmp/aphelion-planet-bench)
##   BENCH_LABEL     run label written into results.json (default "run")
##   BENCH_SCENARIOS comma-separated subset of SCENARIOS
##   BENCH_VARIANTS  comma-separated subset of VARIANTS
##   BENCH_FRAMES    measured frames per variant per round (default 90)
##   BENCH_ROUNDS    interleaved rounds; variant order reverses each round (default 2)
##   BENCH_QUALITY   atmosphere preset (scripts/atmosphere_quality.gd), e.g. "reference"
## Variants isolate cost: every variant except "full" hides the volumetric
## clouds. "no_clouds" changes nothing else; "air_min"
## also forces 2 view / 1 light scattering samples, approximating the cost of
## everything except atmospheric scattering; "air_ultra" forces 64 / 6 through
## the original light loop (the sunlight table only matches its own count).
## GPU time sums the main viewport and the clouds' offscreen passes, as
## benchmark_clouds.gd does. One capture per scenario and variant is saved.

const SCENARIOS := ["workshop", "surface_day", "surface_sunset", "ascent", "upper_atmosphere", "low_orbit", "high_orbit", "night_side"]
const VARIANTS := ["full", "no_clouds", "air_min", "air_ultra"]
## Attribution-only variants, not run by default: clouds off plus the ocean
## patch or the launch site hidden. The fixtures sit at the flight origin,
## not the launch pad, so "no_site" only matters for other poses.
const EXTRA_VARIANTS := ["no_ocean", "no_site"]
var results := []

func _gpu(viewport: Viewport) -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())

func _cpu(viewport: Viewport) -> float:
	return RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())

func _list(name: String, fallback: Array) -> Array:
	var value := OS.get_environment(name)
	return fallback if value.is_empty() else Array(value.split(","))

func _run() -> void:
	output_dir = OS.get_environment("BENCH_OUT")
	if output_dir.is_empty(): output_dir = "/tmp/aphelion-planet-bench"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var frames := int(OS.get_environment("BENCH_FRAMES")) if OS.get_environment("BENCH_FRAMES") != "" else 90
	var rounds := int(OS.get_environment("BENCH_ROUNDS")) if OS.get_environment("BENCH_ROUNDS") != "" else 2
	world = World.new()
	root.add_child(world)
	if OS.get_environment("BENCH_QUALITY") != "":
		world.set_atmosphere_quality(OS.get_environment("BENCH_QUALITY"))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var clouds: Node = world._clouds
	for viewport in [clouds.lowres_viewport()] + clouds._resolve:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var variants := _list("BENCH_VARIANTS", VARIANTS)
	for scenario in _list("BENCH_SCENARIOS", SCENARIOS):
		var samples := {}
		for variant in variants: samples[variant] = []
		for round in range(rounds):
			var order := variants.duplicate()
			if round % 2 == 1: order.reverse()
			for variant in order:
				_setup(scenario, variant)
				for frame in range(20): await process_frame
				await RenderingServer.frame_post_draw
				var last := Time.get_ticks_usec()
				for frame in range(frames):
					await process_frame
					await RenderingServer.frame_post_draw
					var now := Time.get_ticks_usec()
					samples[variant].append(_sample(clouds, float(now - last) * 0.001))
					last = now
				if round == 0:
					var image := root.get_texture().get_image()
					image.save_png(output_dir.path_join("%s-%s.png" % [scenario, variant]))
		for variant in variants:
			var summary := _summarize(samples[variant])
			summary.scenario = scenario
			summary.variant = variant
			results.append(summary)
			print("%-17s %-10s frame %6.2f ms (%5.1f fps)  gpu %6.2f ms  render-cpu %5.2f ms  draws %4d  prims %8d  objs %4d" % [scenario, variant, summary.frame_ms, 1000.0 / summary.frame_ms, summary.gpu_ms, summary.render_cpu_ms, summary.draw_calls, summary.primitives, summary.objects])
	var report := {
		"label": OS.get_environment("BENCH_LABEL") if OS.get_environment("BENCH_LABEL") != "" else "run",
		"resolution": [root.size.x, root.size.y],
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"adapter": RenderingServer.get_video_adapter_name(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"frames": frames, "rounds": rounds,
		"quality": world.atmosphere_quality,
		"results": results,
	}
	var file := FileAccess.open(output_dir.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Results: " + output_dir.path_join("results.json"))
	world.queue_free()
	await process_frame
	quit()

func _sample(clouds: Node, frame_ms: float) -> Dictionary:
	var gpu := _gpu(root)
	var cpu := _cpu(root)
	var lowres: SubViewport = clouds.lowres_viewport()
	if clouds.is_visible_in_tree() and lowres.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		gpu += _gpu(lowres)
		cpu += _cpu(lowres)
		for target in clouds._resolve:
			if target.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
				gpu += _gpu(target)
				cpu += _cpu(target)
	return {
		"frame_ms": frame_ms, "gpu_ms": gpu,
		"render_cpu_ms": cpu + RenderingServer.get_frame_setup_time_cpu(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
	}

func _summarize(samples: Array) -> Dictionary:
	var summary := {}
	for key in samples[0]:
		var values: Array = samples.map(func(sample: Dictionary) -> float: return float(sample[key]))
		values.sort()
		summary[key] = values[values.size() / 2]
		if key in ["frame_ms", "gpu_ms"]:
			summary[key + "_p95"] = values[int(values.size() * 0.95)]
	return summary

func _setup(scenario: String, variant: String) -> void:
	if scenario == "workshop":
		world.set_mode("workshop")
		world._rocket.show()
	else:
		if world._mode != "flight": world.set_mode("flight")
		world._rocket.show()
		world._yaw = 0.62
		world._pitch = 0.22
		world._distance = 28.0
		match scenario:
			"surface_day":
				_place(0.0, Vector3(0, 0.8, -0.6), false)
			"surface_sunset":
				world._yaw = PI
				_place(0.0, Vector3(0, 0.03, -1), false)
			"ascent":
				world._pitch = 0.1
				_place(12000.0, Vector3(0.3, 0.7, -0.65), true)
			"upper_atmosphere":
				_place(60000.0, Vector3(0.3, 0.6, -0.75), false)
			"low_orbit":
				_place(150000.0, Vector3(0.6, 0.35, -0.7), false)
			"high_orbit":
				# Entire planet in frame, terminator visible.
				_place(1600000.0, Vector3(1, 0.4, 0.3), false)
				world._rocket.hide()
				world.camera.position = Vector3.ZERO
				world.camera.look_at(world._planet.position, Vector3.FORWARD)
			"night_side":
				# 300 km over the dark hemisphere, the horizon (48 degrees below
				# level) in frame with the backlit limb beyond it.
				_place(300000.0, Vector3(0.2, -0.85, -0.5), false)
				world._rocket.hide()
				world.camera.position = Vector3.ZERO
				world.camera.look_at(Vector3(0, -900, -1000), Vector3.UP)
	world._clouds.visible = variant == "full"
	if scenario != "workshop":
		# OceanPatch.follow() (via _place) owns visibility; only override it here.
		if variant == "no_ocean": world._ocean.visible = false
		world._landscape.visible = variant != "no_site"
	# Probe: ocean cloud-reflection mode (ocean.gdshader cloud_reflection_shading).
	if OS.get_environment("BENCH_OCEAN_SHADING") != "" and is_instance_valid(world._ocean):
		world._ocean.material().set_shader_parameter("cloud_reflection_shading", int(OS.get_environment("BENCH_OCEAN_SHADING")))
	if variant in ["air_min", "air_ultra"]:
		var counts := Vector2i(2, 1) if variant == "air_min" else Vector2i(64, 6)
		for material in _air_materials():
			material.set_shader_parameter("atmosphere_view_samples", counts.x)
			material.set_shader_parameter("atmosphere_light_samples", counts.y)

func _air_materials() -> Array:
	var materials: Array = [world._sky_material, world._planet.material_override]
	if is_instance_valid(world._ocean): materials.append(world._ocean.material())
	return materials

func _place(altitude: float, sun: Vector3, engine_on: bool) -> void:
	var position := Vector3(0, altitude, 0)
	world.sync_flight({"position": position, "altitude": altitude, "orientation": Basis.IDENTITY,
		"engine_on": engine_on, "throttle": 1.0 if engine_on else 0.0, "fuel": 1.0, "boosters_attached": false,
		"capsule_only": false, "chute_deployed": false}, 0.0)
	world.set_sun_direction(sun.normalized())
