extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Parts = preload("res://scripts/parts.gd")
const Surface = preload("res://scripts/planet_surface.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var design: Dictionary = Parts.default_design()
	design.parachute = true
	var world := World.new()
	root.add_child(world)
	world.set_design(design)
	world.set_mode("flight")
	var f := Flight.new(); f.reset(design); f.ignite()
	var terrain := Surface.home()
	# Open terrain away from the pad: search rotated directions for dry land.
	var radial: Vector3 = Surface.LAUNCH_RADIAL
	for step in range(1, 200):
		var d: Vector3 = (Basis(Vector3.RIGHT, deg_to_rad(0.3 + step * 0.05)) * Surface.LAUNCH_RADIAL.normalized())
		var r := float(terrain.contact(d * float(terrain.definition.radius), 0.0).radius)
		if r > float(terrain.definition.radius) + 20.0:
			radial = d * r
			print("SITE %.2f deg from pad (%.1f km), ground %.0f m above datum" % [0.3 + step * 0.05, deg_to_rad(0.3 + step * 0.05) * float(terrain.definition.radius) / 1000.0, r - float(terrain.definition.radius)])
			break
	var up := radial.normalized()
	f.state.capsule_only = true; f.state.engine_on = false; f.state.throttle = 0.0
	f.state.position = Flight.PLANET_CENTER + up * (terrain.contact(radial, 0.0).radius + 60.0)
	f.state.velocity = terrain.surface_velocity(radial) - up * 15.0
	f.deploy_chute()
	for i in range(30): await process_frame
	var td := -1; var last := Time.get_ticks_usec()
	var acc := {}
	for i in range(60 * 20):
		var a := Time.get_ticks_usec()
		f.step(1.0/60.0, {"throttle": 0.0})
		var s := f.telemetry()
		world.begin_flight_tick(); world.sync_flight(s, 1.0/60.0, 1.0/60.0); world.end_flight_tick(); world.present_flight_frame(1.0)
		var b := Time.get_ticks_usec()
		await process_frame
		var now := Time.get_ticks_usec()
		if td < 0 and s.status != "flying": td = i
		var key := "air %ds" % int(i / 60) if td < 0 else "LANDED t+%02ds" % int((i - td) / 60)
		if not acc.has(key): acc[key] = [0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var k: Array = acc[key]
		k[0] += 1; k[1] += (now - last) / 1000.0; k[2] += (b - a) / 1000.0
		k[3] += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		k[4] += RenderingServer.viewport_get_measured_render_time_gpu(vp); k[5] = maxf(k[5], (now - last) / 1000.0)
		last = now
		if td >= 0 and (i - td) % 60 == 59:
			var out := "  t+%02ds per second: " % ((i - td) / 60)
			for m in ["module", "canopy", "rope", "cord"]:
				out += "%s=%s " % [m, str(snappedf(float(Engine.get_meta(m, 0)), 0.1))]; Engine.set_meta(m, 0)
			print(out + "sleeping=%s" % Engine.get_meta("sleep", false))
		elif td < 0:
			for m in ["module", "canopy", "rope", "cord"]: Engine.set_meta(m, 0)
	for key in acc:
		var k: Array = acc[key]
		print("%-14s fps=%5.1f frame=%5.2f ms  game-logic=%5.2f  render-cpu=%5.2f  gpu=%5.2f  worst=%6.1f ms" % [key, 1000.0 / (k[1] / k[0]), k[1] / k[0], k[2] / k[0], k[3] / k[0], k[4] / k[0], k[5]])
	quit(0)
