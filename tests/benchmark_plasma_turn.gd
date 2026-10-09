extends SceneTree
## Graphical regression: a continuous 120-degree/second tumble through all attitudes.
const Preview = preload("res://scenes/plasma_preview.tscn")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Continuous plasma rendering benchmark needs a graphical display")
		quit(1)
		return
	var preview = Preview.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	preview.turn_slider.value = 120.0
	preview._process(0.0)
	var wake = preview.world._heat_trail
	var initial_mesh: Mesh = wake.mesh
	var builds: int = wake.profile_build_count
	var intervals: Array[float] = []
	var last := Time.get_ticks_usec()
	for frame in range(270):
		preview._process(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if frame >= 30: intervals.append(float(now - last) / 1000.0)
		last = now
		assert(wake.mesh == initial_mesh and wake.profile_build_count == builds, "Rapid continuous turning must not rebuild or replace the wake")
		var expected: Vector3 = -(preview.orientation.inverse() * Vector3.RIGHT)
		var actual: Vector3 = wake._material.get_shader_parameter("local_flow")
		assert(expected.distance_to(actual) < 0.0001, "Rendered airflow follows this frame's attitude")
	intervals.sort()
	print("Plasma turn frame intervals: median %.2f ms, p95 %.2f ms, max %.2f ms" % [intervals[intervals.size()/2], intervals[int(intervals.size()*0.95)], intervals[-1]])
	print("PASS: 540-degree continuous tumble with fixed strands and per-frame airflow")
	preview.free()
	quit(0)
