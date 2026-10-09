extends SceneTree
const PlanetSurface = preload("res://scripts/planet_surface.gd")
const HOVER = preload("res://scenes/hover_preview.tscn")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if OS.get_environment("NO_WEATHER") == "1":
		PlanetSurface.home().definition.cloud_weather = null
	var hover = HOVER.instantiate()
	root.add_child(hover)
	var base := Vector3(57126.2, 11295.6 - 18850.0, -77649.7)
	for km in [1.7, 5.0, 6.0, 9.5, 12.0, 18.85]:
		hover.hover_position = base + Vector3(0, km * 1000.0, 0)
		hover.hover_yaw = 3.782
		hover.hover_pitch = -0.45
		for i in range(60): await process_frame
		var f := []
		var last := Time.get_ticks_usec()
		for i in range(120):
			await process_frame
			var now := Time.get_ticks_usec()
			f.append((now - last) / 1000.0)
			last = now
		f.sort()
		print("SWEEP %5.2f km  frame median %6.2f ms" % [km, f[60]])
	quit(0)
