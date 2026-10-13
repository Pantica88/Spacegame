extends SceneTree
## Flies the saved rocket straight up at full throttle with SAS, staging each
## time thrust drops to zero while climbing, and logs performance each second.
var main: Node

func _initialize() -> void: _run.call_deferred()

func _median(values: Array) -> float:
	if values.is_empty(): return 0.0
	values.sort()
	return values[values.size() / 2]

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(20): await process_frame
	await main._roll_out()
	for i in range(60): await process_frame
	var f = main.flight
	var clouds: Node = main.world._clouds
	var main_rid := root.get_viewport_rid()
	var low_rid: RID = clouds.lowres_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	RenderingServer.viewport_set_measure_render_time(low_rid, true)
	main.sas = true
	main._set_throttle(1.0)
	main._stage()
	print("STAGE 0 t=0.0 ignition: stage_index=%s" % f.state.stage_index)
	var start := Time.get_ticks_usec()
	var last := start
	var sec := {"frame": [], "cpu": [], "phys": [], "gpu": [], "cloud": []}
	var next_report := 1.0
	var zero_thrust_since := -1.0
	var stages := 0
	var worst := 0.0
	print("PERF   t(s)  stage   alt(m)  speed  vs(m/s)  thrust(kN)  frame_med  frame_max  cpu_proc  cpu_phys  gpu_main  gpu_cloud")
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		var t := (now - start) / 1e6
		worst = maxf(worst, dt)
		sec.frame.append(dt)
		sec.cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		sec.phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		sec.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(main_rid))
		sec.cloud.append(RenderingServer.viewport_get_measured_render_time_gpu(low_rid) if clouds.is_visible_in_tree() else 0.0)
		var s: Dictionary = f.state
		var climbing := float(s.get("vertical_speed", 0.0)) > 0.0
		if float(s.get("thrust", 0.0)) <= 0.0 and climbing and not bool(s.get("capsule_only", false)):
			if zero_thrust_since < 0.0: zero_thrust_since = t
			elif t - zero_thrust_since > 0.5:
				var before = s.stage_index
				main._stage()
				stages += 1
				print("STAGE %d t=%.1f alt=%.0f speed=%.0f: stage_index %s -> %s thrust=%.0f" % [stages, t, s.altitude, s.speed, before, f.state.stage_index, f.state.thrust])
				zero_thrust_since = -1.0
		else:
			zero_thrust_since = -1.0
		if t >= next_report:
			next_report += 1.0
			print("PERF %6.0f  %5s  %7.0f  %5.0f  %6.0f  %9.1f  %8.2f  %8.2f  %8.2f  %8.2f  %8.2f  %8.2f" % [t, str(s.stage_index), s.altitude, s.speed, s.get("vertical_speed", 0.0), float(s.thrust) / 1000.0,
				_median(sec.frame), worst, _median(sec.cpu), _median(sec.phys), _median(sec.gpu), _median(sec.cloud)])
			for k in sec: sec[k] = []
			worst = 0.0
		if str(s.status) in ["landed", "crashed"] or s.get("destroyed", false):
			print("END status=%s t=%.1f max_alt=%.0f" % [s.status, t, s.max_altitude]); break
		if not climbing and float(s.thrust) <= 0.0 and t > 5.0:
			print("END apex t=%.1f alt=%.0f max_alt=%.0f stages=%d" % [t, s.altitude, s.max_altitude, stages]); break
		if t > 600.0:
			print("END timeout alt=%.0f" % s.altitude); break
	quit(0)
