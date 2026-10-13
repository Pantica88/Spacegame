extends SceneTree
## Replays the owner's 2026-10-10 cloud-band view, capturing during vertical motion.
## BAND_OUTPUT selects the output directory; BAND_TEMPORAL=0 disables reconstruction.
## BAND_HEATMAP=1 enables density-sample colours; BAND_OLD_DEPTH=1 compares the
## former low-deck-only reconstruction. BAND_BENCHMARK=1 avoids image readback.
const START := Vector3(-450.2, 8166.1, 35.8)
const SNAPSHOTS := [1, 16, 32, 64, 96, 120]
var hover: Node
var motion_frame := 0
var direction := 0.0
var out := ""
var captures: Array[Dictionary] = []
var start := START
var gpu_main: Array[float] = []
var gpu_march: Array[float] = []

func _initialize() -> void:
	_run.call_deferred()

func _move() -> void:
	if direction == 0.0: return
	motion_frame += 1
	hover.hover_position = start + Vector3.UP * direction * 8.0 * motion_frame
	hover._update_camera()

func _capture(label: String) -> void:
	var path := out.path_join(label + ".png")
	root.get_texture().get_image().save_png(path)
	captures.append({"file": label + ".png", "frame": motion_frame,
		"position": [hover.hover_position.x, hover.hover_position.y, hover.hover_position.z],
		"altitude_m": hover._last_altitude})
	print("MOTION ", label, " ", hover._view_state())

func _run() -> void:
	out = OS.get_environment("BAND_OUTPUT")
	if out.is_empty():
		push_error("BAND_OUTPUT is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	if not OS.get_environment("BAND_START_Y").is_empty():
		start.y = float(OS.get_environment("BAND_START_Y"))
	root.size = Vector2i(1600, 900)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	hover = load("res://scenes/hover_preview.tscn").instantiate()
	root.add_child(hover)
	hover.set_process(false)
	hover.set_process_unhandled_input(false)
	hover.hover_hud.hide()
	hover.hover_time = 0.0
	hover.hover_yaw = 1.427
	hover.hover_pitch = -0.197
	hover._clouds.weather_time = 167.7
	hover._clouds.time_scale = 0.0
	hover._clouds.temporal = OS.get_environment("BAND_TEMPORAL") != "0"
	RenderingServer.viewport_set_measure_render_time(hover._clouds._lowres.get_viewport_rid(), true)
	if OS.get_environment("BAND_OLD_DEPTH") == "1":
		var shader := Shader.new()
		shader.code = FileAccess.get_file_as_string("res://assets/shaders/clouds_resolve.gdshader").replace(
			"if (reprojection_storm_radius_km > reprojection_radius_km)", "if (false)")
		for material in hover._clouds._resolve_materials: material.shader = shader
	if OS.get_environment("BAND_HEATMAP") == "1":
		for child in hover.get_children():
			if child.get_script() == load("res://scripts/render_cost_overlay.gd"):
				child._set_mode(child.Mode.CLOUD_SAMPLES)
				# Cursor readback stalls rendering; only snapshot explicitly below.
				child._since_sample = -100000.0
	process_frame.connect(_move)
	for d in [1.0, -1.0]:
		direction = 0.0
		motion_frame = 0
		hover.hover_position = start
		hover._update_camera()
		for i in range(120): await process_frame
		await RenderingServer.frame_post_draw
		if d == 1.0 and OS.get_environment("BAND_BENCHMARK") != "1": _capture("start")
		direction = d
		while motion_frame < 120:
			await RenderingServer.frame_post_draw
			gpu_main.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			gpu_march.append(RenderingServer.viewport_get_measured_render_time_gpu(hover._clouds._lowres.get_viewport_rid()))
			if motion_frame in SNAPSHOTS and OS.get_environment("BAND_BENCHMARK") != "1":
				_capture(("up" if d > 0.0 else "down") + "_%03d" % motion_frame)
		direction = 0.0
	var manifest := {"time": 0.0, "yaw": 1.427, "pitch": -0.197,
		"weather": 167.7, "metres_per_frame": 8.0,
		"temporal": hover._clouds.temporal,
		"heatmap": OS.get_environment("BAND_HEATMAP") == "1",
		"old_depth": OS.get_environment("BAND_OLD_DEPTH") == "1",
		"benchmark_without_readback": OS.get_environment("BAND_BENCHMARK") == "1", "captures": captures}
	gpu_main.sort()
	gpu_march.sort()
	manifest["median_gpu_ms"] = {"main": gpu_main[gpu_main.size() / 2],
		"march": gpu_march[gpu_march.size() / 2]}
	var file := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("MOTION GPU ", manifest["median_gpu_ms"])
	print("MOTION DONE ", out)
	quit(0)
