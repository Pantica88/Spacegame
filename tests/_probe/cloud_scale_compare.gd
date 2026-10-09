extends SceneTree
## Before/after: fixed half-resolution clouds vs altitude-stepped resolution.
const HOVER = preload("res://scenes/hover_preview.tscn")
var hover: Node

func _initialize() -> void:
	_run.call_deferred()

func _median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2]

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	hover = HOVER.instantiate()
	root.add_child(hover)
	var out := OS.get_environment("COMPARE_OUT")
	var views := [
		["user_18850m", Vector3(57126.2, 11295.6, -77649.7), 3.782, -0.792],
		["user_straight_down", Vector3(57126.2, 11295.6, -77649.7), 3.782, -1.5],
		["user_horizon", Vector3(57126.2, 11295.6, -77649.7), 3.782, -0.05],
		["low_9000m", Vector3(57126.2, 11295.6 - 9850.0, -77649.7), 3.782, -0.792],
		["high_40000m", Vector3(57126.2, 11295.6 + 21150.0, -77649.7), 3.782, -0.792],
	]
	for view in views:
		for mode in ["before", "after"]:
			hover._clouds.altitude_scaling = mode == "after"
			hover.hover_position = view[1]
			hover.hover_yaw = view[2]
			hover.hover_pitch = view[3]
			hover.hover_hud.visible = false
			for i in range(60): await process_frame
			var frames := []
			var last := Time.get_ticks_usec()
			for i in range(120):
				await process_frame
				var now := Time.get_ticks_usec()
				frames.append((now - last) / 1000.0)
				last = now
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s-%s.png" % [out, view[0], mode])
			print("COMPARE %-20s %-6s alt %6.0f m  scale %.3f  frame median %6.2f ms" % [view[0], mode, hover._last_altitude, hover._clouds.effective_scale(), _median(frames)])
	quit(0)
