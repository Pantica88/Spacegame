extends SceneTree
## Temporal cloud reconstruction vs a full march of the same pose.
const HOVER = preload("res://scenes/hover_preview.tscn")
var hover: Node
var out := ""

func _initialize() -> void:
	_run.call_deferred()

func _active_image() -> Image:
	var clouds: Node = hover._clouds
	if clouds.temporal:
		return clouds._resolve[clouds._temporal_frame % 2].get_texture().get_image()
	return clouds.lowres_viewport().get_texture().get_image()

func _diff(a: Image, b: Image) -> Array:
	if a.get_size() != b.get_size():
		return [-1, -1, -1.0]
	var da := a.get_data()
	var db := b.get_data()
	var changed := 0
	var large := 0
	var total := 0.0
	for i in range(0, da.size(), 4):
		var d := 0
		for c in range(4): d = maxi(d, absi(da[i + c] - db[i + c]))
		if d > 2: changed += 1
		if d > 24: large += 1
		total += d
	var n := da.size() / 4
	return [100.0 * changed / n, 100.0 * large / n, total / n]

func _pose(yaw: float, pitch: float) -> void:
	hover.hover_yaw = yaw
	hover.hover_pitch = pitch

func _reference(yaw: float, pitch: float) -> Image:
	hover._clouds.temporal = false
	_pose(yaw, pitch)
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var image := _active_image()
	hover._clouds.temporal = true
	return image

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	out = OS.get_environment("COMPARE_OUT")
	hover = HOVER.instantiate()
	root.add_child(hover)
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var base := Vector3(57126.2, 11295.6 - 18850.0, -77649.7)
	for km in [2.0, 8.5]:
		hover.hover_position = base + Vector3(0, km * 1000.0, 0)
		var yaw := 3.782
		var pitch := -0.1 if km < 5.0 else -0.3
		# Still camera.
		var reference: Image = await _reference(yaw, pitch)
		hover._clouds.temporal = true
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		var still := _active_image()
		var d := _diff(still, reference)
		print("TEMPORAL %.1f km still          size %s  pixels >2: %.2f%%  >24: %.3f%%  mean %.2f" % [km, still.get_size(), d[0], d[1], d[2]])
		# Turning camera at several rates.
		for rate_deg in [0.5, 2.0, 6.0]:
			var rate := deg_to_rad(rate_deg)
			_pose(yaw, pitch)
			for i in range(8): await process_frame
			for i in range(20):
				_pose(yaw + rate * (i + 1), pitch)
				await process_frame
			await RenderingServer.frame_post_draw
			var turning := _active_image()
			var final_yaw: float = hover.hover_yaw
			turning.save_png("%s/turn-%.1fkm-%.1fdeg-temporal.png" % [out, km, rate_deg])
			var ref: Image = await _reference(final_yaw, pitch)
			ref.save_png("%s/turn-%.1fkm-%.1fdeg-reference.png" % [out, km, rate_deg])
			d = _diff(turning, ref)
			print("TEMPORAL %.1f km turn %.1f deg/f  pixels >2: %.2f%%  >24: %.3f%%  mean %.2f" % [km, rate_deg, d[0], d[1], d[2]])
	# Climbing camera: translation towards the clouds overhead.
	for step_m in [6.0, 15.0]:
		var start := base + Vector3(0, 7500.0, 0)
		var yaw := 3.782
		var pitch := 0.15
		hover.hover_position = start
		_pose(yaw, pitch)
		for i in range(8): await process_frame
		for i in range(30):
			hover.hover_position = start + Vector3(0, step_m * (i + 1), step_m * 0.3 * (i + 1))
			await process_frame
		await RenderingServer.frame_post_draw
		var moving := _active_image()
		moving.save_png("%s/climb-%.0fm-temporal.png" % [out, step_m])
		var ref: Image = await _reference(yaw, pitch)
		ref.save_png("%s/climb-%.0fm-reference.png" % [out, step_m])
		var d := _diff(moving, ref)
		print("TEMPORAL climb %.0f m/frame  pixels >2: %.2f%%  >24: %.3f%%  mean %.2f" % [step_m, d[0], d[1], d[2]])
	quit(0)
