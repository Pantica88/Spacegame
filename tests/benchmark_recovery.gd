extends SceneTree
## Full recovery update CPU benchmark, including flight, world synchronization and UI.
const Parts = preload("res://scripts/parts.gd")
const Craft = preload("res://scripts/craft_model.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	for rate in [1.0,4.0]:
		var design := Parts.default_design()
		var assembly := Craft.migrate(design)
		Craft.add_part(assembly,"parachute")
		game.design = Craft.project(assembly,design)
		await game._roll_out()
		game._set_throttle(0.0)
		game.recorded = true
		game.flight.state.status = "flying"
		game.flight.state.capsule_only = true
		game.flight.state.chute_deployed = true
		game.flight.state.position = Vector3(0,0.01,0)
		game.flight.state.velocity = game.flight.terrain.surface_velocity(Vector3(0,game.flight.PLANET_RADIUS,0))+Vector3(0,-2,0)
		game.flight._has_lifted = true
		game.flight.step(1.0/60.0,{"throttle":0.0})
		assert(game.flight.state.status in ["landed","crashed"])
		game.world.sync_flight(game.flight.telemetry(),3.0,0.0)
		game.warp = rate
		game.physical_warp = true
		for phase in ["touchdown","ground","rest"]:
			var start := Time.get_ticks_usec()
			var maximum := 0
			for frame in range(240):
				var tick := Time.get_ticks_usec()
				game._physics_process(1.0/60.0)
				maximum = maxi(maximum,Time.get_ticks_usec()-tick)
			print("RECOVERY %.0fx %s: %.3f ms/tick, max %.3f, cloth sleeping=%s" % [rate,phase,(Time.get_ticks_usec()-start)/240000.0,maximum/1000.0,game.world._parachute_module.canopy.sleeping])
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	quit()
