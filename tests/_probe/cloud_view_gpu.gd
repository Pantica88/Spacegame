extends SceneTree
## GPU cost of the hover view from above the cloud deck, varied one factor at a time.
const HOVER = preload("res://scenes/hover_preview.tscn")

var hover: Node
var low_rid: RID

func _initialize() -> void:
	_run.call_deferred()

func _median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2]

func _measure(label: String, pos: Vector3, yaw: float, pitch: float, clouds := true, scale := -1.0, hide := []) -> void:
	for node in hide: hover.get(node).visible = false
	hover.hover_position = pos
	hover.hover_yaw = yaw
	hover.hover_pitch = pitch
	hover._clouds.visible = clouds
	var old_scale: float = hover._clouds.resolution_scale
	if scale > 0.0: hover._clouds.resolution_scale = scale
	for i in range(40): await process_frame
	var main := []
	var low := []
	var frame := []
	var last := Time.get_ticks_usec()
	for i in range(90):
		await process_frame
		var now := Time.get_ticks_usec()
		frame.append((now - last) / 1000.0)
		last = now
		main.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		low.append(RenderingServer.viewport_get_measured_render_time_gpu(low_rid) if clouds else 0.0)
	hover._clouds.resolution_scale = old_scale
	for node in hide: hover.get(node).visible = true
	print("PROBE %-34s alt %6.0f m  gpu main %6.2f  cloud-pass %6.2f  total %6.2f  frame %6.2f" % [label, hover._last_altitude, _median(main), _median(low), _median(main) + _median(low), _median(frame)])

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	hover = HOVER.instantiate()
	root.add_child(hover)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	low_rid = hover._clouds.lowres_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(low_rid, true)
	var user := Vector3(57126.2, 11295.6, -77649.7)
	var yaw := 3.782
	var pitch := -0.792
	var base := Vector3(user.x, user.y - 18850.0, user.z)
	for km in [1.7, 3.5, 5.0, 6.0, 8.0, 9.5, 12.0]:
		var p := base + Vector3(0, km * 1000.0, 0)
		await _measure("chase %.1f km" % km, p, yaw, -0.45)
		Engine.set_meta("probe_nc", true)
		await _measure("chase %.1f km, no clouds" % km, p, yaw, -0.45, false)
		Engine.set_meta("probe_air", Vector2i(1, 1))
		await _measure("chase %.1f km, no clouds, haze 1x1" % km, p, yaw, -0.45, false)
		Engine.remove_meta("probe_air")
		Engine.remove_meta("probe_nc")
	quit(0)
