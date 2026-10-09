extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Craft = preload("res://scripts/craft_model.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	for discard_core in [false, true]:
		var design := Parts.default_design()
		var assembly := Craft.migrate(design)
		Craft.add_part(assembly, "parachute")
		Craft.add_part(assembly, "decoupler", "engine")
		assembly.stages = [["ignite:engine"], ["separate:decoupler"], ["deploy:capsule"], ["separate:engine_decoupler"]]
		game.design = Craft.project(assembly, design)
		await game._roll_out()
		game._set_throttle(0.0)
		game.flight.state.status = "flying"
		game.flight.state.position = Vector3(0,1500,0)
		game.flight.state.velocity = game.flight.terrain.surface_velocity(Vector3(0,game.flight.PLANET_RADIUS+1500,0)) + Vector3(0,-25,0)
		game.flight.state.orientation = Basis(Vector3.FORWARD, 0.3)
		game.flight.state.stage_index = 1 if discard_core else 2
		game.world.sync_flight(game.flight.telemetry(), 0.0)
		if discard_core:
			var shell = game.world._engine_shells["engine_decoupler"]
			game._stage()
			check(game.flight.state.capsule_only, "Separation stage releases the core")
			check(game.world._detached_nodes[0].is_ancestor_of(shell), "Discarded core owns its engine shell")
			# Simulate the flight model removing a spent or destroyed stage.
			game.flight.state.detached.clear()
			game.world.sync_flight(game.flight.telemetry(), 0.0)
			await process_frame
			await process_frame
			check(not is_instance_valid(shell), "Discarded engine shell was actually freed")
			game.world.sync_flight(game.flight.telemetry(), 0.0)
		var module = game.world._parachute_module
		var cap_rest: Transform3D = module.cap_pivot.transform
		var capsule_rest: Transform3D = game.world._rocket.global_transform
		var position_before: Vector3 = game.flight.state.position
		var camera_before: Transform3D = game.world.camera.global_transform
		var target_before: Vector3 = game.world._camera_focus
		game._stage()
		check(game.flight.state.chute_deployed, "Player deploy stage opens parachute")
		check(game.flight.state.position == position_before, "Deploy stage preserves physics position")
		check(game.world._rocket.global_transform.is_equal_approx(capsule_rest), "Deploy stage preserves capsule transform")
		check(game.world._camera_focus.is_equal_approx(target_before), "Deploy stage preserves camera target")
		check(game.world.camera.global_transform.is_equal_approx(camera_before), "Deploy stage does not jump or zoom the camera")
		for frame in range(6): game._physics_process(1.0 / 60.0)
		check(module.elapsed > 0.09, "Flight updates reach the deployment animation after debris cleanup")
		if module.elapsed < 0.09: continue
		check(module.cap_pivot.transform != cap_rest, "Cap starts ejecting")
		check(not module.canopy.visible, "Packed fabric remains hidden during initial cap release")
		for frame in range(39): game._physics_process(1.0 / 60.0)
		check(module.cap_released and module.canopy.is_visible_in_tree(), "Canopy emerges from the released cap in flight")
		check(module.canopy.scale.x < 0.1, "Canopy is drawn out before inflating")
		var frozen: float = module.elapsed
		game.paused = true
		game._physics_process(0.5)
		check(module.elapsed == frozen, "Pause holds deployment")
		game.paused = false
		for frame in range(120): game._physics_process(1.0 / 60.0)
		check(is_equal_approx(module.elapsed, module.DURATION), "Canopy completes inflation through the player flight loop")
		check(module.canopy.is_visible_in_tree() and module.canopy.scale.is_equal_approx(Vector3.ONE), "Full canopy stays visible")
		check(module.housing.is_visible_in_tree(), "Spent housing stays on the capsule")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: staged deployment, destroyed core cleanup, cap ejection, visible canopy, pause and stable camera")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
