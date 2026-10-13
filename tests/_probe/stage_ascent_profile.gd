extends SceneTree
## Same ascent as stage_ascent_perf.gd, but drives main's physics and process
## callbacks itself so each part of the per-frame script work is timed
## directly. Performance.TIME_PROCESS is the slowest frame of the previous
## second and includes rendering submission, so it cannot attribute cost.
## PROBE_SECONDS limits the run (default 170).
var main: Node
var acc := {}
var ready_to_drive := false
var stage_report := ""
var glow_ab := OS.get_environment("PROBE_GLOW_AB") != ""
var glow_hidden := false
var hide_member := OS.get_environment("PROBE_HIDE")
var run_start := 0

func _initialize() -> void: _run.call_deferred()

func _median(values: Array) -> float:
	if values.is_empty(): return 0.0
	values.sort()
	return values[values.size() / 2]

func _add(key: String, usec: int) -> void:
	acc[key] = acc.get(key, 0) + usec

func _physics_process(delta: float) -> bool:
	if not ready_to_drive: return false
	var t0 := Time.get_ticks_usec()
	_flight_tick(delta)
	_add("phys", Time.get_ticks_usec() - t0)
	acc["ticks"] = acc.get("ticks", 0) + 1
	return false

func _process(delta: float) -> bool:
	if not ready_to_drive: return false
	var t0 := Time.get_ticks_usec()
	main._process(delta)
	_add("proc", Time.get_ticks_usec() - t0)
	# PROBE_GLOW_AB=1 hides the aerothermal effects every other two seconds;
	# PROBE_HIDE=<world member> hides that node instead.
	var off := int((Time.get_ticks_usec() - run_start) / 2e6) % 2 == 1
	if glow_ab and off:
		main.world._clear_aero_glow()
	if hide_member != "":
		main.world.get(hide_member).visible = not off
	glow_hidden = off and (glow_ab or hide_member != "")
	return false

# Mirrors main._physics_process for a flying craft at 1x.
func _flight_tick(delta: float) -> void:
	var world = main.world
	var flight = main.flight
	if main.mode != "flight" or main.paused: return
	var t := Time.get_ticks_usec()
	world.begin_flight_tick()
	main._enforce_warp_limit()
	main._prepare_warp_to()
	var start_time: float = flight.simulation_time()
	_add("misc", Time.get_ticks_usec() - t)
	var controls := {"pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": main.throttle, "sas": main.sas}
	flight.state.throttle = main.throttle
	t = Time.get_ticks_usec()
	if main.warp > 1.0 and not main.physical_warp: flight.step_rails(delta * main.warp, main.warp)
	else: flight.step(delta * main.warp, controls)
	_add("step", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	var state: Dictionary = flight.telemetry()
	_add("telem", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	main.map_instrument.record_flight(state)
	_add("maprec", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	world.sync_flight(state, 0.0 if main.warp > 1.0 and not main.physical_warp else delta * main.warp, delta)
	_add("sync", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	world.advance_solar_time(flight.simulation_time() - start_time)
	world.set_planet_time(flight.simulation_time())
	world.end_flight_tick(main.warp <= 1.0 or main.physical_warp)
	main._enforce_warp_limit()
	_add("misc", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	main._update_flight_ui()
	_add("ui", Time.get_ticks_usec() - t)

func _timed_stage() -> String:
	var flight = main.flight
	var t := Time.get_ticks_usec()
	main._cancel_warp_to()
	main._toast(flight.execute_stage())
	var a := Time.get_ticks_usec()
	main._enforce_warp_limit()
	var telem: Dictionary = flight.telemetry()
	var b := Time.get_ticks_usec()
	main.world.sync_flight(telem, 0)
	var c := Time.get_ticks_usec()
	main._update_flight_ui()
	var d := Time.get_ticks_usec()
	return "execute_stage %.1f ms, telemetry %.1f ms, sync_flight %.1f ms, flight_ui %.1f ms" % [(a - t) / 1000.0, (b - a) / 1000.0, (c - b) / 1000.0, (d - c) / 1000.0]

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var limit := float(OS.get_environment("PROBE_SECONDS")) if OS.get_environment("PROBE_SECONDS") != "" else 170.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(20): await process_frame
	await main._roll_out()
	for i in range(60): await process_frame
	var f = main.flight
	var main_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	main.sas = true
	main._set_throttle(1.0)
	main._stage()
	main.set_physics_process(false)
	main.set_process(false)
	# The window takes keyboard focus; stray keys (period cycles warp) must
	# not change the run.
	main.set_process_input(false)
	main.set_process_unhandled_input(false)
	main.set_process_shortcut_input(false)
	root.gui_disable_input = true
	# PROBE_WARP=2..4 flies the ascent under physics warp.
	var warp_step := int(OS.get_environment("PROBE_WARP")) if OS.get_environment("PROBE_WARP") != "" else 1
	if warp_step > 1: main._select_warp_step(warp_step)
	ready_to_drive = true
	print("STAGE 0 ignition: stage_index=%s" % f.state.stage_index)
	var start := Time.get_ticks_usec()
	run_start = start
	var last := start
	var keys := ["phys", "ticks", "step", "telem", "maprec", "sync", "ui", "misc", "proc"]
	var sec := {"frame": [], "rs_cpu": [], "gpu": []}
	for k in keys: sec[k] = []
	var worst := 0.0
	var next_report := 1.0
	var zero_thrust_since := -1.0
	var stages := 0
	print("PROF  t  stage  warp  sim_t  alt(km)  speed  frame  max  | phys ticks step telem maprec sync ui misc | proc | rs_cpu gpu   (per-frame medians, ms)")
	while true:
		acc = {}
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		var t := (now - start) / 1e6
		worst = maxf(worst, dt)
		sec.frame.append(dt)
		for k in keys: sec[k].append(acc.get(k, 0) / (1.0 if k == "ticks" else 1000.0))
		sec.rs_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(main_rid) + RenderingServer.get_frame_setup_time_cpu())
		sec.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(main_rid))
		var s: Dictionary = f.state
		var climbing := float(s.get("vertical_speed", 0.0)) > 0.0
		if float(s.get("thrust", 0.0)) <= 0.0 and climbing and not bool(s.get("capsule_only", false)):
			if zero_thrust_since < 0.0: zero_thrust_since = t
			elif t - zero_thrust_since > 0.5:
				var before = s.stage_index
				var timing := _timed_stage()
				stages += 1
				print("STAGE %d t=%.1f alt=%.0f: %s -> %s  %s" % [stages, t, s.altitude, before, f.state.stage_index, timing])
				zero_thrust_since = -1.0
		else:
			zero_thrust_since = -1.0
		if dt > 80.0:
			var line := "  SLOW frame %.0f ms at t=%.2f:" % [dt, t]
			for k in keys: line += " %s=%.1f" % [k, acc.get(k, 0) / (1.0 if k == "ticks" else 1000.0)]
			print(line)
		if t >= next_report:
			next_report += 1.0
			var line := "PROF %3.0f  %s  %s%s %6.1f  %8.1f  %6.0f  %5.1f %6.1f |" % [t, str(s.stage_index), main.warp, "p" if main.physical_warp else "", f.simulation_time(), s.altitude / 1000.0, s.speed, _median(sec.frame), worst]
			for k in ["phys", "ticks", "step", "telem", "maprec", "sync", "ui", "misc"]: line += " %.2f" % _median(sec[k])
			if glow_hidden: line += " OFF"
			line += " | %.2f | %.2f %.2f" % [_median(sec.proc), _median(sec.rs_cpu), _median(sec.gpu)]
			print(line)
			for k in sec: sec[k] = []
			worst = 0.0
		if str(s.status) in ["landed", "crashed"] or s.get("destroyed", false):
			print("END status=%s t=%.1f" % [s.status, t]); break
		if t > limit:
			print("END limit alt=%.0f" % s.altitude); break
	quit(0)
