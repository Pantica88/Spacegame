extends SceneTree
## GPU cost of the cloud march + resolve and of the whole frame, per hover
## view (names from cloud_views.gd), as medians over CLOUD_FRAMES frames.
## Run with the window size to measure, e.g.
##   tools/run.sh --resolution 1920x1080 --disable-vsync --script res://tests/_probe/cloud_cost.gd
const HOVER = preload("res://scenes/hover_preview.tscn")
const Views = preload("res://tests/_probe/cloud_views.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
const CloudPass = preload("res://scripts/cloud_render_pass.gd")

func _initialize() -> void: _run.call_deferred()

static func _median(values: Array) -> float:
	if values.is_empty(): return -1.0
	values.sort()
	return values[values.size() / 2]

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	match OS.get_environment("CLOUD_WEATHER"):
		"procedural": PlanetSurface.home().definition.cloud_weather = null
		"mixed": PlanetSurface.home().definition.cloud_weather = Tiles.generate_weather(7, 90, 0.85, "mixed")
		"storms": PlanetSurface.home().definition.cloud_weather = Tiles.generate_weather(11, 40, 0.9, "storm")
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var frames := int(OS.get_environment("CLOUD_FRAMES")) if OS.get_environment("CLOUD_FRAMES") != "" else 90
	var names: PackedStringArray = OS.get_environment("CLOUD_VIEWS").split(",", false)
	if names.is_empty(): names = PackedStringArray(Views.VIEWS.keys())
	print("COST viewport %s  march %s" % [root.size, hover._clouds.render_pass().target_size() if hover._clouds.render_pass() else "-"])
	for view_name in names:
		var v: Array = Views.VIEWS[view_name]
		hover.hover_position = Vector3(v[0], v[1], v[2])
		hover.hover_yaw = v[3]
		hover.hover_pitch = v[4]
		for variant in ["clouds", "none"]:
			hover._clouds.visible = variant == "clouds"
			for i in 30: await process_frame
			var cloud: Array[float] = []
			var total: Array[float] = []
			for i in frames:
				await RenderingServer.frame_post_draw
				if variant == "clouds": cloud.append(CloudPass.captured_gpu_ms())
				total.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
			print("COST %-14s %-6s frame GPU %6.2f ms   cloud passes %6.2f ms" % [view_name, variant, _median(total), _median(cloud)])
	quit(0)
