extends SceneTree
## Graphical regression for the opt-in compute cloud prototype (BUFFERED):
## paired captures against the original composite at the same poses, plus
## camera attachment, resize, hidden, map-mode and switch-back lifecycle.
## tools/run.sh --always-on-top --script res://tests/test_cloud_buffered.gd
const World = preload("res://scripts/world_view.gd")
const Clouds = preload("res://scripts/cloud_layer.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
var world: Node3D
var failures: Array[String] = []
var output_dir := "/tmp/aphelion-cloud-buffered"

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	if not Clouds.ComputePass.supported():
		await _fallback()
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(960, 600)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	var layer = world._clouds
	layer.time_scale = 0.0
	layer.temporal = false
	# Stratocumulus everywhere with a storm band: low decks and towers.
	var weather := Weather.new()
	var painted := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 16:
			painted.set_pixel(x, y, Color(0, 0.8, 0.3, 0.9 if x % 5 == 0 else 0.0))
	weather.restore(painted)
	Surface.home().definition.cloud_weather = weather
	world._distance = 32.0
	world._pitch = 0.35
	for name in ["below", "inside", "above", "orbit", "far", "flames"]:
		var altitude: float = {"below": 3000.0, "inside": 6000.0, "above": 12000.0, "orbit": 100000.0, "far": 2700000.0, "flames": 6000.0}[name]
		# Exhaust (priority 2) must still draw over the clouds (1). Hull heat is
		# left off: freeing a world with a hot hull hangs Godot's shutdown
		# (2026-10-13, independent of the clouds).
		var burning: bool = name == "flames"
		world.sync_flight({"position": Vector3(0, altitude, 0), "altitude": altitude,
			"orientation": Basis.IDENTITY, "status": "flying", "engine_on": burning, "throttle": 1.0 if burning else 0.0,
			"fuel": 1.0 if burning else 0.0, "boosters_attached": false, "heat_glow": 0.0, "heating_rate": 0.0}, 0.05)
		var captures := {}
		for variant in [Clouds.CompositeVariant.ORIGINAL, Clouds.CompositeVariant.BUFFERED]:
			layer.set_composite_variant(variant)
			for frame in range(20): await process_frame
			await RenderingServer.frame_post_draw
			captures[variant] = root.get_texture().get_image()
			captures[variant].save_png("%s/%s-%s.png" % [output_dir, name, Clouds.COMPOSITE_VARIANT_NAMES[variant].replace(" ", "-")])
		_check(layer.uses_buffered() and world.camera.compositor != null, name + ": the prototype attaches to the flight camera")
		_check(layer.material_override.render_priority == 1, name + ": the composite keeps its place between the sun and flames")
		var march_ms := _timestamp_ms("Cloud compute march", "Cloud compute march done")
		if march_ms >= 0.0: print("BUFFERED %s compute march GPU %.3f ms" % [name, march_ms])
		_check(layer._compute_pass.dispatched > 0, name + ": the compute march runs")
		_check(layer._lowres.render_target_update_mode == SubViewport.UPDATE_DISABLED, name + ": the offscreen viewports stay idle")
		var error := _image_error(captures[Clouds.CompositeVariant.ORIGINAL], captures[Clouds.CompositeVariant.BUFFERED])
		var cloud := _image_error(captures[Clouds.CompositeVariant.ORIGINAL], await _clear_capture(layer))
		print("BUFFERED %s mean_error=%.6f p99=%.4f max=%.4f clouds_vs_clear=%.6f target=%s dispatched=%d" % [
			name, error.x, error.y, error.z, cloud.x, layer._compute_pass.target_size(), layer._compute_pass.dispatched])
		# First run, RX 580: mean 0.0005-0.0091, p99 up to 0.13 (orbit). The
		# remaining differences lie on the deck's limb, which the original
		# marches at full resolution, and on storm-tower edges.
		_check(error.x < 0.015 and error.y < 0.2, "%s: the prototype matches the original composite" % name)
	# Lifecycle: resize, hidden, map mode and switching back.
	layer.set_composite_variant(Clouds.CompositeVariant.BUFFERED)
	root.size = Vector2i(800, 500)
	for frame in range(5): await process_frame
	var expected := Vector2i((Vector2(root.size) * layer.effective_scale()).round())
	_check(layer._compute_pass.target_size() == expected, "Targets follow a resize: %s vs %s" % [layer._compute_pass.target_size(), expected])
	layer.hide()
	await process_frame
	_check(not layer._compute_pass.enabled and world.camera.compositor == null, "Hiding the clouds detaches the pass")
	layer.show()
	await process_frame
	_check(layer._compute_pass.enabled and world.camera.compositor != null, "Showing the clouds reattaches the pass")
	world.get_viewport().disable_3d = true
	await process_frame
	_check(not layer._compute_pass.enabled, "Map mode (3D disabled) stops the pass")
	world.get_viewport().disable_3d = false
	await process_frame
	layer.set_composite_variant(Clouds.CompositeVariant.SPLIT)
	await process_frame
	_check(world.camera.compositor == null and not layer._compute_pass.enabled, "Returning to production detaches the pass")
	_check(layer._lowres.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Production reenables the offscreen march")
	layer.set_composite_variant(Clouds.CompositeVariant.BUFFERED)
	await process_frame
	var camera: Camera3D = world.camera
	world.free()
	_check(camera == null or not is_instance_valid(camera) or camera.compositor == null, "Freeing the world leaves no attached pass")
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("PASS: compute cloud prototype matches the original composite and follows camera, resize, hide, map and switch-back. Captures: " + output_dir)
	quit(0 if failures.is_empty() else 1)

func _clear_capture(layer: Node) -> Image:
	layer.hide()
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	layer.show()
	for frame in range(5): await process_frame
	return image

## Mean, 99th percentile and maximum per-pixel channel difference.
func _image_error(a: Image, b: Image) -> Vector3:
	var histogram := PackedInt32Array()
	histogram.resize(256)
	var total := 0.0
	var maximum := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var error := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			total += error
			maximum = maxf(maximum, error)
			histogram[mini(int(round(error * 255.0)), 255)] += 1
	var count := a.get_width() * a.get_height()
	var seen := 0
	var p99 := 0.0
	for i in 256:
		seen += histogram[i]
		if seen >= count * 0.99:
			p99 = i / 255.0
			break
	return Vector3(total / count, p99, maximum)

## GPU time between two named timestamps of the last captured frame, or -1
## when not profiling (tools/run.sh --profile-gpu).
func _timestamp_ms(begin: String, end: String) -> float:
	var rd := RenderingServer.get_rendering_device()
	var start := -1.0
	for i in rd.get_captured_timestamps_count():
		var name := rd.get_captured_timestamp_name(i)
		if name == begin: start = rd.get_captured_timestamp_gpu_time(i)
		elif name == end and start >= 0.0: return (rd.get_captured_timestamp_gpu_time(i) - start) / 1e6
	return -1.0

## Compatibility or no RenderingDevice (--rendering-method gl_compatibility):
## selecting the prototype keeps the original composite and attaches nothing.
func _fallback() -> void:
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world.sync_flight({"position": Vector3(0, 6000, 0), "altitude": 6000.0,
		"orientation": Basis.IDENTITY, "status": "flying"}, 0.0)
	var layer = world._clouds
	layer.set_composite_variant(Clouds.CompositeVariant.BUFFERED)
	for frame in range(10): await process_frame
	var code: String = layer.material_override.shader.code
	_check(not layer.uses_buffered() and layer._compute_pass == null, "No compute pass without a RenderingDevice")
	_check(world.camera.compositor == null, "Nothing attaches to the camera")
	_check(not code.begins_with("#define CLOUD_BUFFERED") and not code.contains("\n#define CLOUD_BUFFERED"), "The original composite stays selected")
	world.free()
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("PASS: without a RenderingDevice the prototype falls back to the original composite (%s)" % RenderingServer.get_current_rendering_method())
	quit(0 if failures.is_empty() else 1)
