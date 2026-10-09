extends SceneTree
## Plays the real game: launch, fly sideways, stage to the capsule, chute, land on terrain.
var main: Node
var log_rows: Array = []
func _initialize() -> void:
	_run.call_deferred()
func _frames(n: int) -> void:
	for i in range(n): await process_frame
func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(20)
	var kinds := []
	if main.design.has("assembly"):
		for part in main.design.assembly.parts: kinds.append(str(part.get("kind", part.get("id", "?"))))
	print("design: tanks=%s engine=%s parts=%s" % [main.design.get("tanks"), main.design.get("engine"), kinds])
	await main._roll_out()
	await _frames(30)
	main._stage()  # ignition
	print("ignite: ", main.flight.state.status)
	var f = main.flight
	await _frames(30)
	for k in range(8):
		if f.state.capsule_only: break
		main._stage()
	# Short drop: place the capsule 80 m above open terrain 3.7 km from the pad.
	var terrain = f.terrain
	var dir: Vector3 = terrain.rotation_at(f.simulation_time()) * (Basis(Vector3.RIGHT, deg_to_rad(0.35)) * f.Surface.LAUNCH_RADIAL.normalized())
	var ground := float(terrain.contact(dir * float(terrain.definition.radius), f.simulation_time()).radius)
	f.state.position = f.PLANET_CENTER + dir * (ground + 80.0)
	f.state.velocity = terrain.surface_velocity(dir * ground) - dir * 12.0
	f.state.engine_on = false
	main.throttle = 0.0
	main._chute()
	print("capsule_only=%s chute=%s ground=%.0f m above datum" % [f.state.capsule_only, f.state.chute_deployed, ground - float(terrain.definition.radius)])
	var staged_down := true
	var chute := true
	var t0 := Time.get_ticks_msec()
	var td_frame := -1
	var frame := 0
	var last := Time.get_ticks_usec()
	while frame < 60 * 70:
		await process_frame
		frame += 1
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		var s: Dictionary = f.state
		var alt := float(s.get("terrain_clearance", s.get("altitude", 0.0)))
		var up: Vector3 = (Vector3(s.position) - f.PLANET_CENTER).normalized()
		# Gentle sideways tilt during the burn so the flight drifts off the pad.
		if s.status == "flying" and not staged_down and float(s.get("max_altitude", 0.0)) > 150.0 and float(s.get("max_altitude", 0.0)) < 1200.0:
			var east := up.cross(Vector3.UP).normalized() if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			s.velocity = Vector3(s.velocity) + east * 0.25
		# Past apex: shed everything down to the capsule, then deploy the chute.
		if s.status == "flying" and not staged_down and float(s.get("vertical_speed", 0.0)) < -5.0 and float(s.get("max_altitude", 0.0)) > 800.0:
			for k in range(8):
				if f.state.capsule_only or f.state.chute_deployed: break
				main._stage()
			staged_down = true
			print("frame %d: staged, capsule_only=%s alt=%.0f" % [frame, f.state.capsule_only, alt])
		if staged_down and not chute and s.status == "flying" and alt < 2400.0:
			main._chute()
			chute = bool(f.state.chute_deployed)
			if chute: print("frame %d: chute deployed alt=%.0f speed=%.0f" % [frame, alt, float(s.get("speed", 0))])
		if td_frame < 0 and s.status != "flying" and s.status != "ready":
			td_frame = frame
			var off: float = (Vector3(s.position) - f.PLANET_CENTER).normalized().angle_to(f.terrain.rotation_at(f.simulation_time()) * f.Surface.LAUNCH_RADIAL.normalized()) * 600000.0
			print("frame %d: TOUCHDOWN %s impact=%.1f m/s, %.0f m from pad" % [frame, s.status, float(s.get("impact_speed", -1)), off])
		var phase := "flight" if td_frame < 0 else "after"
		if td_frame < 0 and alt < 300.0 and staged_down: phase = "final300m"
		log_rows.append([frame, phase, dt, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, s.status, alt])
		if (td_frame < 0 and frame % 60 == 0) or (td_frame >= 0 and (frame - td_frame) % 60 == 59):
			var keys := ["C_canopy","C_rope","C_ropesteps","C_cord"]
			var out := ""
			for k in keys:
				out += "%s=%.0f " % [k, float(Engine.get_meta(k, 0.0))]
				Engine.set_meta(k, 0.0)
			if td_frame >= 0 or alt < 400.0 and staged_down:
				print("%s ms/s: %s cloth_asleep=%s rope_asleep=%s %d %d" % [("t+%02ds" % ((frame - td_frame) / 60)) if td_frame >= 0 else "pre", out, Engine.get_meta("C_clothsleep", "?"), Engine.get_meta("C_ropesleep", "?"), 0, 0])
		if td_frame >= 0 and frame - td_frame > 60 * 4: break
	# Summaries
	var groups := {}
	for r in log_rows:
		var key: String = r[1]
		if r[1] == "after": key = "after t+%02ds" % int((r[0] - td_frame) / 60.0)
		if not groups.has(key): groups[key] = [0, 0.0, 0.0, 0.0, 0.0]
		var g: Array = groups[key]; g[0] += 1; g[1] += r[2]; g[2] = maxf(g[2], r[2]); g[3] += r[3]; g[4] += r[4]
	for key in groups:
		var g: Array = groups[key]
		print("%-14s frames=%4d fps=%6.1f worst=%7.1f ms  process=%6.2f ms  physics=%6.2f ms" % [key, g[0], 1000.0 / (g[1] / g[0]), g[2], g[3] / g[0], g[4] / g[0]])
	if td_frame >= 0:
		print("frames around touchdown:")
		for r in log_rows:
			if r[0] >= td_frame - 3 and r[0] <= td_frame + 25:
				print("  f=%d dt=%.1f ms process=%.2f physics=%.2f %s" % [r[0], r[2], r[3], r[4], r[5]])
	quit(0)
