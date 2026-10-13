extends SceneTree
## Holds the saved craft at the reported altitude and isolates cloud paths.
const Clouds = preload("res://scripts/cloud_layer.gd")
var game: Node

func _initialize() -> void: _run.call_deferred()

func _patch(base: Shader, volume: String) -> Shader:
	var shader := Shader.new()
	shader.code = base.code.replace('#include "res://assets/shaders/clouds_volume.gdshaderinc"', volume)
	return shader

func _transparent_ms() -> float:
	var rd := RenderingServer.get_rendering_device()
	var result := 0.0
	for i in range(rd.get_captured_timestamps_count() - 1):
		if rd.get_captured_timestamp_name(i) == "Render 3D Transparent Pass":
			result = (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1e6
	return result

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	await game._roll_out()
	game.set_physics_process(false)
	var world = game.world
	var clouds = world._clouds
	clouds.time_scale = 0.0
	clouds.weather_time = 32.0
	var state: Dictionary = game.flight.telemetry().duplicate(true)
	var center := Vector3(0, world.PLANET_RADIUS, 0)
	var up: Vector3 = (Vector3(state.position) + center).normalized()
	state.position = up * (world.PLANET_RADIUS + 6321.0) - center
	state.altitude = 6321.0
	state.status = "flying"
	state.simulation_time = 32.0
	world._pitch = -0.1
	if not OS.get_environment("BAND_YAW").is_empty(): world._yaw = float(OS.get_environment("BAND_YAW"))
	world._distance = 50.0
	world.sync_flight(state, 0.0)
	var out := OS.get_environment("BAND_OUTPUT")
	DirAccess.make_dir_recursive_absolute(out)
	var low_rid: RID = clouds.lowres_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(low_rid, true)
	var labels := OS.get_environment("BAND_MODES").split(",", false) if not OS.get_environment("BAND_MODES").is_empty() else PackedStringArray(["split", "original", "no_temporal", "no_march", "detail_mask"])
	var low_shader: Shader = clouds._lowres_material.shader
	var ocean_material: ShaderMaterial = world._ocean.material()
	for label in labels:
		clouds.show()
		world._ocean.show()
		ocean_material.set_shader_parameter("cloud_reflection_enabled", label != "no_reflection")
		if label == "no_ocean": world._ocean.hide()
		clouds.altitude_scaling = label != "full_resolution"
		clouds.resolution_scale = 1.0 if label == "full_resolution" else 0.5
		clouds.temporal = label != "no_temporal"
		clouds.set_composite_variant(Clouds.CompositeVariant.ORIGINAL if label == "original" else (Clouds.CompositeVariant.NO_MARCH if label == "no_march" else Clouds.CompositeVariant.SPLIT))
		clouds._lowres_material.shader = low_shader
		if label == "no_clouds": clouds.hide()
		if label == "no_depth":
			clouds.set_composite_variant(Clouds.CompositeVariant.ORIGINAL)
			var depth_shader := Shader.new()
			depth_shader.code = clouds.material_override.shader.code.replace("return scene_distance < 100.0 ? scene_distance : 1e20;", "return 1e20;")
			clouds.material_override.shader = depth_shader
		if label == "no_ground":
			var volume := FileAccess.get_file_as_string("res://assets/shaders/clouds_volume.gdshaderinc").replace("if (ground.x > 0.0 && ground.y > ground.x) { end = min(end, ground.x); }", "")
			for material in [clouds.material_override, clouds._mask_material, clouds._detail_material, clouds._lowres_material]:
				material.shader = _patch(material.shader, volume)
			clouds._owned_composite_shader = clouds.material_override.shader
		if label in ["storm_fine", "deck_fine", "jitter", "no_shadow", "weighted_light", "single_fine", "single_medium", "deck_anchored"]:
			var volume := FileAccess.get_file_as_string("res://assets/shaders/clouds_volume.gdshaderinc")
			if label == "storm_fine": volume = volume.replace("STORM_STEP = 0.2", "STORM_STEP = 0.05").replace("STORM_GROWTH = 0.03", "STORM_GROWTH = 0.0075").replace("AUTHORED_CLOUD_STEPS = 320", "AUTHORED_CLOUD_STEPS = 1280")
			if label == "deck_fine": volume = volume.replace("max(0.08, low_path / 96.0)", "max(0.02, low_path / 384.0)").replace("AUTHORED_CLOUD_STEPS = 320", "AUTHORED_CLOUD_STEPS = 1280")
			if label == "deck_anchored": volume = volume.replace("a + low_step", "a + max(0.08, (a - start) * 0.015)")
			if label == "jitter":
				volume = volume.replace("mix(a, b, 0.25)", "mix(a, b, fract(sin(dot(fragcoord, vec2(12.9898, 78.233))) * 43758.5453) * 0.5)").replace("mix(a, b, 0.75)", "mix(a, b, 0.5 + fract(sin(dot(fragcoord, vec2(12.9898, 78.233))) * 43758.5453) * 0.5)")
			if label == "no_shadow": volume = volume.replace("sun_shadow = exp(-optical * extinction);", "sun_shadow = 1.0;")
			if label == "weighted_light":
				volume = volume.replace("formation = vec3((f0.x + f1.x) * 0.5, (f0.yz * f0.x + f1.yz * f1.x) / total);", "formation = vec3((f0.x + f1.x) * 0.5, (f0.yz * f0.x + f1.yz * f1.x) / total);\n\t\t\tpoint = (p0 * f0.x + p1 * f1.x) / total;\n\t\t\tsample_radius = length(point);\n\t\t\theight = (sample_radius - bottom) / cloud_thickness_km;")
			if label in ["single_fine", "single_medium"]:
				volume = volume.replace("if (authored_weather && (a < low_start || a >= low_end))", "if (false)").replace("STORM_STEP = 0.2", "STORM_STEP = 0.1").replace("STORM_GROWTH = 0.03", "STORM_GROWTH = 0.0075" if label == "single_fine" else "STORM_GROWTH = 0.015").replace("AUTHORED_CLOUD_STEPS = 320", "AUTHORED_CLOUD_STEPS = 640")
			clouds._lowres_material.shader = _patch(low_shader, volume)
			clouds._detail_material.shader = _patch(clouds._detail_material.shader, volume)
		if label == "detail_mask":
			var shader := Shader.new()
			shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled; stencil_mode read, compare_equal, 1; void vertex(){POSITION=vec4(VERTEX.xy,1.0,1.0);} void fragment(){ALBEDO=vec3(1,0,1);ALPHA=1.0;}"
			clouds._detail_material.shader = shader
		for i in range(60): await process_frame
		var times: Array[float] = []
		var low: Array[float] = []
		for i in range(60):
			await process_frame
			times.append(_transparent_ms())
			low.append(RenderingServer.viewport_get_measured_render_time_gpu(low_rid))
		times.sort(); low.sort()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + label + ".png")
		print("BAND %s transparent=%.3f reduced=%.3f" % [label, times[30], low[30]])
	print("BAND DONE " + out)
	quit()
