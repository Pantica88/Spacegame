extends SceneTree
## Cloud renderer rebuild: clouds during sustained vertical and forward motion
## from an owner-reported view, against a still reference at the final pose.
## Saves to $COMPARE_OUT; cloud_compare_metrics.gd scores them.
const HOVER = preload("res://scenes/hover_preview.tscn")
const START := Vector3(-12100.0, 15671.5, 6123.9)
const YAW := 1.966
const PITCH := -0.379
const WEATHER := 34.2
const SNAPSHOTS := [5, 20, 40]
var MODES := ["reduced"]
var hover: Node

func _initialize() -> void:
	_run.call_deferred()

func _pose(position: Vector3) -> void:
	hover.hover_position = position
	hover.hover_yaw = YAW
	hover.hover_pitch = PITCH

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var out := OS.get_environment("COMPARE_OUT")
	hover = HOVER.instantiate()
	root.add_child(hover)
	hover.hover_hud.visible = false
	# Ignore the desktop's mouse wheel and keys while capturing.
	hover.set_process_unhandled_input(false)
	hover._clouds.weather_time = WEATHER
	hover._clouds.time_scale = 0.0
	# Hover movement is in the launch frame: forward follows yaw and pitch.
	var view := Basis(Vector3.UP, YAW) * Basis(Vector3.RIGHT, PITCH)
	var cases := [["up", Vector3.UP], ["down", Vector3.DOWN], ["forward", -view.z], ["back", view.z]]
	_pose(START)
	for i in range(300): await process_frame
	for speed in [1.0, 8.0, 50.0]:
		for c in cases:
			for mode in MODES:
				hover._clouds.resolution_scale = 0.5
				hover._clouds.altitude_scaling = true
				_pose(START)
				for i in range(120): await process_frame
				# Snapshots taken mid-movement, without pausing the motion.
				for i in range(40):
					_pose(START + c[1] * speed * (i + 1))
					await process_frame
					if i + 1 in SNAPSHOTS:
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png("%s/%s%d_f%02d-%s.png" % [out, c[0], int(speed), i + 1, mode])
			# Still references at each snapshot pose.
			hover._clouds.resolution_scale = 1.0
			hover._clouds.altitude_scaling = false
			for frame in SNAPSHOTS:
				_pose(START + c[1] * speed * frame)
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s%d_f%02d-reference.png" % [out, c[0], int(speed), frame])
	_pose(START)
	hover._clouds.resolution_scale = 1.0
	hover._clouds.altitude_scaling = false
	for i in range(30): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/start.png" % out)
	print("MOTION done")
	quit(0)
