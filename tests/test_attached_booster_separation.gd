extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Flight = preload("res://scripts/flight_model.gd")
const World = preload("res://scripts/world_view.gd")
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for burning in [false, true]:
		for explicit_release in [false, true]:
			var design := Parts.default_design()
			design.boosters = true
			var craft := Parts.Craft.migrate(design)
			craft.stages = [["ignite:engine", "ignite:boosters"] if burning else ["ignite:engine"], ["separate:boosters", "separate:decoupler"] if explicit_release else ["separate:decoupler"]]
			if not explicit_release: craft.stages.append(["separate:boosters"])
			if not burning: craft.stages.append(["ignite:boosters"])
			craft.stages.append(["deploy:capsule"])
			design = Parts.Craft.project(craft, design)
			var flight := Flight.new()
			flight.reset(design)
			var world := World.new()
			root.add_child(world)
			world.set_design(design)
			world.set_mode("flight")
			flight.execute_stage()
			world.sync_flight(flight.telemetry(), 0.0)
			var mass_before: float = flight._current_mass()
			flight.execute_stage()
			world.sync_flight(flight.telemetry(), 0.0)
			check(flight.state.detached.size() == (3 if explicit_release else 1), "Only explicitly triggered joints separate")
			var total_mass: float = flight._current_mass()
			for piece in flight.state.detached: total_mass += piece.mass
			check(is_equal_approx(total_mass, mass_before), "Separation conserves mass including booster fuel")
			if not explicit_release:
				var piece: Dictionary = flight.state.detached[0]
				for booster in world._booster_nodes:
					check(world._detached_nodes[0].is_ancestor_of(booster), "Booster remains on detached core")
				var booster_engine: Dictionary = piece.engines.filter(func(engine): return engine.id == "boosters")[0]
				check((booster_engine.thrust > 0.0) == burning, "Booster ignition state survives separation")
				flight.execute_stage()
				check(flight.state.detached.size() == 1, "Later vessel staging does not split detached assembly")
			world.queue_free()
			await process_frame
	for failure in failures: push_error(failure)
	print("PASS: attached booster separation" if failures.is_empty() else "FAIL: attached booster separation")
	quit(0 if failures.is_empty() else 1)
