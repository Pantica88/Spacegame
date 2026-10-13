extends SceneTree
## Paired GPU and pixel regression for the stencil cloud composite.
## tools/run.sh --profile-gpu --script res://tests/test_cloud_composite_split.gd
const World = preload("res://scripts/world_view.gd")
const Clouds = preload("res://scripts/cloud_layer.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Overlay = preload("res://scripts/render_cost_overlay.gd")
var world: Node3D
var failures: Array[String] = []
var output_dir := "/tmp/aphelion-cloud-split"

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(960, 600)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	var layer = world._clouds
	layer.time_scale = 0.0
	layer.temporal = false
	var weather := Weather.new()
	var painted := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	painted.fill(Color(0, 0, 1, 0))
	weather.restore(painted)
	Surface.home().definition.cloud_weather = weather
	world._distance = 32.0
	world._pitch = 0.35
	for name in ["below", "inside", "above", "orbit", "far_fade", "hover", "full_resolution", "temporal"]:
		var altitude: float = {"below": 3000.0, "inside": 6000.0, "above": 12000.0, "orbit": 100000.0, "far_fade": 2700000.0, "hover": 12000.0, "full_resolution": 6000.0, "temporal": 6000.0}[name]
		layer.temporal = name == "temporal"
		layer.altitude_scaling = name != "full_resolution"
		layer.resolution_scale = 1.0 if name == "full_resolution" else 0.5
		world.sync_flight({"position": Vector3(0, altitude, 0), "altitude": altitude,
			"orientation": Basis.IDENTITY, "status": "flying", "engine_on": false,
			"fuel": 0.0, "boosters_attached": false, "heat_glow": 0.0, "heating_rate": 0.0}, 0.0)
		world._rocket.visible = name != "hover"
		var captures := {}
		var timings := {}
		for variant in [Clouds.CompositeVariant.ORIGINAL, Clouds.CompositeVariant.SPLIT, Clouds.CompositeVariant.NO_MARCH]:
			layer.set_composite_variant(variant)
			layer._sync_lowres()
			var split: bool = layer.uses_stencil_split()
			_check(layer._stencil_mask.visible == split and layer._detail_pass.visible == split, "Only split mode enables both supporting passes")
			for parameter in ["camera_planet_km", "cloud_lowres", "lowres_enabled", "full_blend", "cloud_deck_fraction"]:
				var expected: Variant = layer.material_override.get_shader_parameter(parameter)
				_check(layer._mask_material.get_shader_parameter(parameter) == expected and layer._detail_material.get_shader_parameter(parameter) == expected, "All cloud passes share " + parameter)
			if DisplayServer.get_name() == "headless": continue
			for frame in range(20): await process_frame
			var samples: Array[float] = []
			for frame in range(30):
				await process_frame
				var milliseconds := _transparent_ms()
				if milliseconds >= 0.0: samples.append(milliseconds)
			samples.sort()
			timings[variant] = samples[samples.size() / 2] if not samples.is_empty() else -1.0
			await RenderingServer.frame_post_draw
			captures[variant] = root.get_texture().get_image()
			captures[variant].save_png("%s/%s-%s.png" % [output_dir, name, Clouds.COMPOSITE_VARIANT_NAMES[variant].replace(" ", "-")])
		if not captures.is_empty():
			var error := _image_error(captures[Clouds.CompositeVariant.ORIGINAL], captures[Clouds.CompositeVariant.SPLIT])
			var unsafe_error := _image_error(captures[Clouds.CompositeVariant.ORIGINAL], captures[Clouds.CompositeVariant.NO_MARCH])
			print("SPLIT %s mean_error=%.6f max_error=%.6f unsafe_error=%.6f GPU original=%.3f split=%.3f no_march=%.3f ms" % [name, error.x, error.y, unsafe_error.x, timings[1], timings[0], timings[2]])
			_check(error.x < 0.0001 and error.y < 0.02, name + ": split preserves the original cloud/foreground composite")
			if name in ["inside", "above"]:
				_check(unsafe_error.x > 0.0001, name + ": the comparison actually exercises foreground cloud occlusion")
	# Direct shader replacement by a diagnostic must disable both extra draws.
	layer.set_composite_variant(Clouds.CompositeVariant.SPLIT)
	var production: Shader = layer.material_override.shader
	var diagnostic := Shader.new()
	diagnostic.code = Clouds.CLOUD_SHADER.code
	layer.material_override.shader = diagnostic
	layer._sync_lowres()
	_check(not layer._stencil_mask.visible and not layer._detail_pass.visible, "A diagnostic shader owns the whole composite")
	layer.material_override.shader = production
	layer._sync_lowres()
	_check(layer._detail_pass.visible == layer.uses_stencil_split(), "Restoring production restores the split")
	var overlay := Overlay.new()
	overlay.world = world
	root.add_child(overlay)
	for variant in Clouds.COMPOSITE_VARIANT_NAMES.size():
		overlay._set_variant(variant)
		_check(layer.composite_variant == variant, "F10 selects the matching complete cloud pipeline")
		_check(layer._detail_pass.visible == layer.uses_stencil_split(), "F10 leaves no extra detail pass active in diagnostics")
	overlay.free()
	world.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: cloud split preserves foreground occlusion, silhouettes, far fade and diagnostics")
	quit(0 if failures.is_empty() else 1)

func _image_error(a: Image, b: Image) -> Vector2:
	var total := 0.0
	var maximum := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var error := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			total += error
			maximum = maxf(maximum, error)
	return Vector2(total / (a.get_width() * a.get_height()), maximum)

func _transparent_ms() -> float:
	var rd := RenderingServer.get_rendering_device()
	if rd == null: return -1.0
	var result := -1.0
	for i in range(rd.get_captured_timestamps_count() - 1):
		if rd.get_captured_timestamp_name(i) == "Render 3D Transparent Pass":
			result = (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1e6
	return result
