extends SceneTree
const Parts = preload("res://scripts/parts.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var count := 8
	var design := Parts.default_design()
	design.engine = "titan"
	var craft := Parts.Craft.migrate(design)
	for index in range(count):
		Parts.Craft.add_part(craft, "separator", "tank_2")
		var mount: Dictionary = craft.parts[-1]
		mount.rotation = 360.0 * index / count
		Parts.Craft.add_part(craft, "tank", mount.id)
		Parts.Craft.add_part(craft, "tank", craft.parts[-1].id)
		Parts.Craft.add_part(craft, "titan", craft.parts[-1].id)
	design = Parts.Craft.project(craft, design)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.design = design
	await game._roll_out()
	game.flight.ignite()
	game.flight.state.active_engines.assign(Parts.Craft.engines(design).map(func(engine): return engine.id))
	game.flight.state.engine_on = true
	game.flight.state.position = Vector3(0, 1000, 0)
	game.flight.state.velocity = Vector3(0, 100, 0)
	game._physics_process(1.0 / 60.0)
	var start := Time.get_ticks_usec()
	for frame in range(60): game._physics_process(1.0 / 60.0)
	print("TITAN FULL GAME LOOP: %.3f ms/tick" % (float(Time.get_ticks_usec() - start) / 60000.0))
	assert(game.world._main_flames.size() == 36, "Eight radial Titans plus core have 36 nozzles")
	assert(game.flight.state.thrust > 0.0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for powered in [false, true]:
			game._set_throttle(1.0 if powered else 0.0)
			var intervals: Array[float] = []
			for frame in range(150):
				start = Time.get_ticks_usec()
				game._physics_process(1.0 / 60.0)
				await process_frame
				await RenderingServer.frame_post_draw
				if frame >= 30: intervals.append(float(Time.get_ticks_usec() - start) / 1000.0)
			intervals.sort()
			print("TITAN RENDER powered=%s: median %.2f ms, p95 %.2f ms" % [powered, intervals[intervals.size()/2], intervals[int(intervals.size()*0.95)]])
	print("PASS: double-tank Titan game loop")
	game.sound.shutdown()
	game.free()
	quit()
