extends SceneTree
const Parts = preload("res://scripts/parts.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var craft := Parts.Craft.seed()
	game.design = Parts.Craft.project(craft,Parts.default_design())
	game._refresh_design(false)
	check(game.launch_button.disabled, "Empty craft cannot roll out")
	await game._roll_out()
	check(game.mode == "workshop", "Direct rollout rejects a craft without a capsule")
	Parts.Craft.add_part(craft,"capsule")
	var capsule := craft.duplicate(true)
	Parts.Craft.add_part(craft,"tank")
	var no_engine := craft.duplicate(true)
	for index in range(Parts.Craft.MAX_TANKS - 1): Parts.Craft.add_part(craft,"tank")
	Parts.Craft.add_part(craft,"sparrow")
	var low_thrust := craft.duplicate(true)
	Parts.Craft.add_part(craft,"decoupler")
	craft.stages = [["separate:decoupler"],["ignite:engine"],["deploy:capsule"]]
	var cases := {"capsule only":capsule,"no engine":no_engine,"low thrust":low_thrust,"unsafe staging":craft}
	for label in cases:
		game.design = Parts.Craft.project(cases[label],Parts.default_design())
		game._refresh_design(false)
		check(not game.launch_button.disabled, label + " enables rollout")
		await game._roll_out()
		check(game.mode == "flight" and game.flight.state.status == "ready", label + " reaches the pad")
		if label == "capsule only":
			check(game.flight._design.tanks == 0 and game.flight._design.engine.is_empty(), "Capsule-only rollout does not add tanks or engines")
		if label == "unsafe staging":
			game.flight.execute_stage()
			game.flight.execute_stage()
			check(not game.flight.state.engine_on and not game.flight.state.active_engines.has("engine"), "Detached ignition is skipped without lighting the discarded engine")
		game._return_workshop()
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: capsule-only rollout, missing propulsion, low thrust and staging advisories" if failures.is_empty() else "FAIL: rollout checks")
	quit(0 if failures.is_empty() else 1)
