extends SceneTree
## Cloud renderer rebuild: reduced-resolution clouds vs the full-resolution
## prototype, each against a reference that marches every screen pixel.
## Saves screenshots to $COMPARE_OUT; tools/cloud_compare_metrics.py scores them.
const HOVER = preload("res://scenes/hover_preview.tscn")
var hover: Node
var out := ""

func _initialize() -> void:
	_run.call_deferred()

func _mode(mode: String) -> void:
	var clouds: Node = hover._clouds
	clouds.resolution_scale = 1.0 if mode == "reference" else 0.5
	clouds.altitude_scaling = mode != "reference"

func _pose(position: Vector3, yaw: float, pitch: float) -> void:
	hover.hover_position = position
	hover.hover_yaw = yaw
	hover.hover_pitch = pitch

func _shot(name: String, frames: int) -> void:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	out = OS.get_environment("COMPARE_OUT")
	hover = HOVER.instantiate()
	root.add_child(hover)
	hover.hover_hud.visible = false
	# Frozen weather: only the camera changes between captures.
	hover._clouds.time_scale = 0.0
	var base := Vector3(57126.2, 11295.6, -77649.7)
	var views := [
		["user_18850m", base, 3.782, -0.792],
		["horizon_18850m", base, 3.782, -0.05],
		["low_9000m", base - Vector3(0, 9850.0, 0), 3.782, -0.3],
		["under_2000m", base - Vector3(0, 16850.0, 0), 3.782, 0.25],
		["high_40000m", base + Vector3(0, 21150.0, 0), 3.782, -0.792],
	]
	# Let terrain, lighting and shader compilation settle once.
	_pose(views[0][1], views[0][2], views[0][3])
	_mode("reference")
	for i in range(300): await process_frame
	for view in views:
		_pose(view[1], view[2], view[3])
		_mode("reference")
		await _shot("%s-reference" % view[0], 90)
		for mode in ["reduced"]:
			_mode(mode)
			await _shot("%s-%s" % [view[0], mode], 90)
		# Noise floor: the reference again, after the other modes.
		_mode("reference")
		await _shot("%s-reference2" % view[0], 30)
	# Motion: compare the frame after 20 frames of turning or flying with a
	# reference of the final pose.
	var motions := [
		["turn2deg", views[0][1], 3.782, -0.792, Vector3.ZERO, 2.0],
		["turn6deg", views[0][1], 3.782, -0.792, Vector3.ZERO, 6.0],
		["fly40m", views[2][1], 3.782, -0.3, Vector3(-24.0, 0.0, 32.0), 0.0],
		["climb15m", views[3][1], 3.782, 0.25, Vector3(0.0, 15.0, 4.5), 0.0],
		# High flight, where the owner saw history give way while moving.
		["fly19km", base, 3.782, -0.3, Vector3(-60.0, 0.0, 80.0), 0.0],
		["fly19km_fast", base, 3.782, -0.9, Vector3(-600.0, 0.0, 800.0), 0.0],
		["fly60km_fast", base + Vector3(0, 41150.0, 0), 3.782, -0.5, Vector3(-600.0, 0.0, 800.0), 0.0],
	]
	for motion in motions:
		var start: Vector3 = motion[1]
		var step: Vector3 = motion[4]
		var turn := deg_to_rad(motion[5])
		for mode in ["reduced"]:
			_mode(mode)
			_pose(start, motion[2], motion[3])
			for i in range(90): await process_frame
			for i in range(20):
				_pose(start + step * (i + 1), motion[2] + turn * (i + 1), motion[3])
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s-%s.png" % [out, motion[0], mode])
		_mode("reference")
		await _shot("%s-reference" % motion[0], 6)
	print("COMPARE done: ", out)
	quit(0)
