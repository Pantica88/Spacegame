extends SceneTree
## Cloud renderer rebuild: views from 19 km up in reduced, full and reference
## modes. Saves to $COMPARE_OUT.
const HOVER = preload("res://scenes/hover_preview.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var out := OS.get_environment("COMPARE_OUT")
	var hover = HOVER.instantiate()
	root.add_child(hover)
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var base := Vector3(57126.2, 11295.6 - 18850.0, -77649.7)
	for km in [19.0, 30.0, 60.0, 150.0]:
		for pitch in [-0.3, -0.9]:
			hover.hover_position = base + Vector3(0, km * 1000.0, 0)
			hover.hover_yaw = 3.782
			hover.hover_pitch = pitch
			for mode in ["reference", "reduced"]:
				hover._clouds.resolution_scale = 1.0 if mode == "reference" else 0.5
				hover._clouds.altitude_scaling = mode != "reference"
				for i in range(100): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%03dkm-%s-%s.png" % [out, int(km), "low" if pitch > -0.5 else "down", mode])
			print("VIEW %.0f km pitch %.1f altitude %.0f scale %.3f" % [km, pitch, hover._last_altitude, hover._clouds.effective_scale()])
	quit(0)
