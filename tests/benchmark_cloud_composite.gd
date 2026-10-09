extends SceneTree
## Godot 4.5.1 graphical benchmark: paired high-altitude horizon/down views.
## Provide CLOUD_REFERENCE_SHADER=/path/to/a/previous/clouds.gdshader.
## Static rendering diagnostic; compares only the compositor, with identical density shader.
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
	seed(17171)
	Surface.reset_home(Surface.HOME)
	var reference_path := OS.get_environment("CLOUD_REFERENCE_SHADER")
	if reference_path.is_empty() or not FileAccess.file_exists(reference_path):
		push_error("Set CLOUD_REFERENCE_SHADER to a previous clouds.gdshader")
		quit(1)
		return
	var reference_source := FileAccess.get_file_as_string(reference_path)
	print("REFERENCE_SHA256: " + FileAccess.get_sha256(reference_path))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1100, 700)
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	var terrain = Surface.home()
	var direction := Vector3.UP
	for i in range(1, 1000):
		var candidate := Vector3(sin(i * 2.4) * 0.3, 1, cos(i * 2.4) * 0.3).normalized()
		if terrain.elevation(candidate) < -200.0:
			direction = candidate
			break
	var viewport := root.get_viewport_rid()
	var clouds: RID = world._clouds.lowres_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	RenderingServer.viewport_set_measure_render_time(clouds, true)
	for scenario in [{"name":"22km_horizon", "altitude":22000.0,"distance":90.0,"pitch":0.05}, {"name":"100km_horizon", "altitude":100000.0,"distance":90.0,"pitch":0.05}]:
		world._pitch = scenario.pitch
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
		var current_shader: Shader = world._clouds.material_override.shader
		var previous_shader := Shader.new()
		previous_shader.code = ("#define CLOUD_OCCUPANCY\n" if current_shader.code.begins_with("#define CLOUD_OCCUPANCY") else "") + reference_source
		var samples := {}
		for mode in ["baseline","previous_composite","cloud_scale_025","previous_composite_025"]:
			samples[mode] = {"gpu": [], "cloud_gpu": [], "frame": []}
		for repeat in range(2):
			var modes := ["baseline","previous_composite","cloud_scale_025","previous_composite_025"]
			if repeat == 1: modes.reverse()
			for mode in modes:
				world._clouds.material_override.shader = previous_shader if mode.begins_with("previous_composite") else current_shader
				world._clouds.resolution_scale = 0.25 if mode.ends_with("025") else 0.5
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
					samples[mode].cloud_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(clouds) if mode != "no_clouds" else 0.0)
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
	var output := "/tmp/aphelion-cloud-composite-benchmark.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"resolution":"1100x700","samples_per_case":80,"rows":results},"\t"))
	print("PASS: paired ocean distance benchmark: "+output)
	quit(0)
