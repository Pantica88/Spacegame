extends SceneTree
## Integration test for the full recover / reward / retry loop. Use tools/check.sh.
var failures: Array[String] = []

func _initialize() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(game)
	await process_frame
	game.design = load("res://scripts/parts.gd").default_design()
	game.profile.data.completed = []
	game.profile.data.flights = 0
	game.profile.data.recoveries = 0
	var previous_terrain = game.flight.terrain
	game.terrain_settings.terrain_seed += 17
	game._apply_terrain_settings()
	check(game.flight.terrain != previous_terrain, "Map editor rebuilds the shared flight terrain")
	check(game.world._planet.mesh == game.flight.terrain.render_mesh_for_lod(game.world._planet_lod), "Map editor refreshes the visible planet mesh")
	game._roll_out()
	game._stage()
	var reached_target := false
	for i in range(15000):
		var state: Dictionary = game.flight.telemetry()
		if state.max_altitude >= 1000 and not reached_target:
			reached_target = true
			game._set_throttle(0)
			game._stage()
		if state.get("chute_safe", false):
			game._chute()
		if state.status in ["landed", "crashed"]:
			break
		game.flight.step(0.1, {"throttle": game.throttle, "sas": true})
	check(game.flight.state.status == "landed", "First-flight capsule lands safely")
	game._record_flight()
	game._record_flight()
	check(game.profile.data.flights == 1, "Flight records cannot be counted twice")
	check(game.profile.data.recoveries == 1, "Successful recovery is recorded")
	check("hop" in game.profile.data.completed, "Altitude plus recovery completes the contract")
	game._show_debrief()
	check(game.paused and game.modal != null, "Recovery opens the debrief")
	game._return_workshop()
	check(game.mode == "workshop" and not game.paused, "Debrief returns to an editable workshop")
	game._roll_out()
	check(game.flight.state.status == "ready" and game.flight.state.time == 0, "Retry starts a fresh flight")
	game._stage()
	game.flight.state.position = Vector3(0, 100, 0)
	game.flight.state.velocity = Vector3(0, -100, 0)
	game.flight.step(2, {"throttle": 0})
	game._record_flight()
	check(game.flight.state.status == "crashed", "Hard impact ends the retry")
	check(game.profile.data.flights == 2 and game.profile.data.recoveries == 1, "Crash preserves earlier successes without granting another recovery")
	game._show_debrief()
	check(game.modal != null, "Crash also offers a retry")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: complete first-flight recovery, mission reward, records, retry and crash loop.")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
