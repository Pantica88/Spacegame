extends SceneTree
const HOVER = preload("res://scenes/hover_preview.tscn")
func _initialize() -> void:
	_run.call_deferred()
func _med(hover, skip: bool) -> float:
	hover._clouds.storm_skip = skip
	for i in range(25): await process_frame
	var f := []
	var last := Time.get_ticks_usec()
	for i in range(80):
		await process_frame
		var now := Time.get_ticks_usec()
		f.append((now - last) / 1000.0)
		last = now
	f.sort()
	return f[40]
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var hover = HOVER.instantiate()
	root.add_child(hover)
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var base := Vector3(57126.2, 11295.6 - 18850.0, -77649.7)
	for view in [["level", -0.05], ["up 30deg", 0.5], ["chase down", -0.45]]:
		for km in [0.5, 1.7, 2.5, 3.2, 4.0, 5.0, 6.0, 9.5]:
			hover.hover_position = base + Vector3(0, km * 1000.0, 0)
			hover.hover_yaw = 3.782
			hover.hover_pitch = view[1]
			var off: float = await _med(hover, false)
			var on: float = await _med(hover, true)
			print("UNDER %-10s %4.1f km  off %6.2f  on %6.2f ms" % [view[0], km, off, on])
	quit(0)
