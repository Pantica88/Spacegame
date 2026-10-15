extends SceneTree
## Replays the reported cloud/reflection mismatch with independent toggles.
const HOVER = preload("res://scenes/hover_preview.tscn")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	hover.hover_time = 0.0
	hover.hover_position = Vector3(66306.9, -1067.5, -23038.8)
	hover.hover_yaw = -3.929
	hover.hover_pitch = -0.562
	hover._clouds.weather_time = 77.4
	DirAccess.make_dir_recursive_absolute("/tmp/cloud-reflection")
	for variant in ["all", "no_reflection", "reflection_only", "neither"]:
		hover._ocean.material().set_shader_parameter("cloud_reflection_strength", 1.0 if variant in ["all", "reflection_only"] else 0.0)
		hover._clouds.visible = variant in ["all", "no_reflection"]
		hover._clouds.render_pass().reset_history()
		for i in 60: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/cloud-reflection/%s.png" % variant)
		print("REFLECTION ", variant)
	quit(0)
