extends SceneTree
const HOVER = preload("res://scenes/hover_preview.tscn")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var hover = HOVER.instantiate()
	root.add_child(hover)
	hover.hover_hud.visible = false
	var base := Vector3(57126.2, 11295.6 - 18850.0, -77649.7)
	for km in [5.0, 6.0, 9.5]:
		hover.hover_position = base + Vector3(0, km * 1000.0, 0)
		hover.hover_yaw = 3.782
		hover.hover_pitch = -0.45
		for i in range(40): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/branch-%.1fkm.png" % [OS.get_environment("COMPARE_OUT"), km])
	quit(0)
