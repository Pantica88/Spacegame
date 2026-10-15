extends SceneTree
## Godot 4.5.1 graphical benchmark; renders paired ablations with vsync disabled.
const CloudPass = preload("res://scripts/cloud_render_pass.gd")
const World = preload("res://scripts/world_view.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var results: Array[Dictionary] = []
func _initialize() -> void: _run.call_deferred()
func median(values: Array[float]) -> float:
	values.sort()
	return values[values.size() / 2]
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Ocean benchmark requires graphical rendering")
		quit(1)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1100, 700)
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	var original_shader: Shader = world._ocean.material().shader
	var no_swell_shader := Shader.new()
	# Diagnostic only: remove the four swell octaves in vertex and fragment.
	# This skips work; setting their amplitudes to zero would still run the loops.
	no_swell_shader.code = original_shader.code.replace("i < 4", "i < 0")
	var terrain = Surface.home()
	var direction := Vector3.UP
	for i in range(1, 1000):
		var candidate := Vector3(sin(i * 2.4) * 0.3, 1, cos(i * 2.4) * 0.3).normalized()
		if terrain.elevation(candidate) < -200.0:
			direction = candidate
			break
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	for scenario in [{"name":"close", "altitude":3.0,"distance":25.0}, {"name":"zoom_90m", "altitude":3.0,"distance":90.0}, {"name":"zoom_500m", "altitude":3.0,"distance":500.0}, {"name":"altitude_500m", "altitude":500.0,"distance":90.0}, {"name":"altitude_6km", "altitude":6000.0,"distance":90.0}, {"name":"altitude_22km", "altitude":22000.0,"distance":90.0}, {"name":"altitude_100km", "altitude":100000.0,"distance":90.0}]:
		world._pitch = 0.35
		world._distance = scenario.distance
		var position: Vector3 = Vector3(0,-Surface.RADIUS,0) + direction * (Surface.RADIUS + scenario.altitude)
		world.sync_flight({"position":position,"altitude":scenario.altitude,"orientation":Basis(Quaternion(Vector3.UP,direction)),"engine_on":false,"fuel":0.0,"boosters_attached":false,"capsule_only":true,"chute_deployed":false},0.0)
		world.set_sun_direction(Vector3(0.5,0.65,0.55).normalized())
		world._rocket.hide()
		world._landscape.hide()
		var patch_visible: bool = world._ocean.visible
		if patch_visible != (scenario.altitude < 25000.0):
			push_error("Benchmark ocean patch is not active: " + scenario.name)
			quit(1)
			return
		var samples := {}
		for mode in ["baseline","no_ocean","no_ocean_air","no_air","no_clouds","no_swell"]:
			samples[mode] = {"gpu": [], "cloud_gpu": [], "frame": []}
		for repeat in range(2):
			var modes := ["baseline","no_ocean","no_ocean_air","no_air","no_clouds","no_swell"]
			if repeat == 1: modes.reverse()
			for mode in modes:
				world._ocean.material().shader = no_swell_shader if mode == "no_swell" else original_shader
				world._ocean.visible = patch_visible and mode != "no_ocean"
				world._clouds.visible = mode != "no_clouds"
				world._planet.material_override.set_shader_parameter("water_cutout_radius", 0.0 if mode == "no_ocean" else world._ocean.cutout_radius)
				world._planet.material_override.set_shader_parameter("seabed_fade", 0.0 if mode == "no_ocean" else world._ocean.fade)
				var density := float(terrain.definition.atmosphere_visual_density)
				for material in [world._sky_material, world._planet.material_override, world._ocean.material()]:
					material.set_shader_parameter("atmosphere_density_scale", 0.0 if mode == "no_air" or (mode == "no_ocean_air" and material == world._ocean.material()) else density)
				for frame in range(15): await process_frame
				var previous := Time.get_ticks_usec()
				for frame in range(40):
					await process_frame
					await RenderingServer.frame_post_draw
					var now := Time.get_ticks_usec()
					samples[mode].frame.append(float(now - previous) / 1000.0)
					previous = now
					samples[mode].gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
					samples[mode].cloud_gpu.append(maxf(CloudPass.captured_gpu_ms(), 0.0) if mode != "no_clouds" else 0.0)
		for mode in samples:
			var gpu: Array[float] = []
			var cloud_gpu: Array[float] = []
			var frames: Array[float] = []
			gpu.assign(samples[mode].gpu)
			cloud_gpu.assign(samples[mode].cloud_gpu)
			frames.assign(samples[mode].frame)
			var row := {"scenario":scenario.name,"mode":mode,"gpu_ms":median(gpu),"cloud_gpu_ms":median(cloud_gpu),"frame_ms":median(frames)}
			results.append(row)
			print("OCEAN_BENCH: "+JSON.stringify(row))
	var output := "/tmp/aphelion-ocean-benchmark.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"resolution":"1100x700","samples_per_case":80,"rows":results},"\t"))
	print("PASS: paired ocean distance benchmark: "+output)
	quit(0)
