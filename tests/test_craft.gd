extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Craft = preload("res://scripts/craft_model.gd")
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []
var count := 0

func check(condition: bool, message: String) -> void:
	count += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	var legacy := Parts.default_design()
	legacy.boosters = true
	legacy.booster_first = true
	var craft := Craft.migrate(legacy)
	check(Craft.valid(craft), "Legacy craft migrates to valid graph")
	var design := Craft.project(craft, legacy)
	check(design.tanks == 2 and design.boosters and design.booster_first, "Migration preserves design and ignition")
	var original_ids: Array = craft.parts.map(func(part): return part.id)
	Craft.add_part(craft, "tank")
	check(Craft.valid(craft), "Adding a tank keeps a valid connected graph")
	for id in original_ids:
		check(craft.parts.any(func(part): return part.id == id), "Existing part identity survives adding a tank")
	var lower_subassembly := Craft.descendant_ids(craft, "tank_3")
	check("engine" in lower_subassembly and "boosters" in lower_subassembly, "Tank descendants identify the connected lower subassembly")
	Craft.remove_part(craft, "tank_3")
	check(Craft.valid(craft), "Removing a connected subassembly leaves a valid graph")
	check(not craft.parts.any(func(part): return part.id in lower_subassembly), "Removing a parent removes every connected descendant")
	craft = Craft.migrate(legacy)
	var corrupt := craft.duplicate(true)
	corrupt.parts[1].parent = "engine"
	check(not Craft.valid(corrupt), "Graph cycles rejected")
	corrupt = craft.duplicate(true)
	corrupt.stages[0].append("ignite:engine")
	check(not Craft.valid(corrupt), "Duplicate stage actions rejected")
	var flight := Flight.new()
	flight.reset(design)
	check(flight.execute_stage().contains("complete"), "First configured stage executes")
	check(not flight.state.engine_on and flight.state.boosters_on, "Only boosters ignite in first group")
	var fuel: float = flight.state.fuel
	flight.step(1.0, {"throttle": 1.0})
	check(flight.state.fuel == fuel, "Unlit core retains fuel")
	var mass_before: float = flight.state.mass
	flight.execute_stage()
	check(is_equal_approx(mass_before, flight.state.mass + flight.state.detached[0].mass), "Booster separation conserves total mass")
	var debris_position: Vector3 = flight.state.detached[0].position
	flight.step(0.5, {"throttle": 1.0})
	check(flight.state.detached[0].position != debris_position, "Detached assembly retains motion")
	check(flight.state.engine_on and not flight.state.boosters_attached, "Grouped separation precedes core ignition")
	flight.execute_stage()
	check(flight.state.capsule_only, "Configured decoupler separates capsule")
	var index: int = flight.state.stage_index
	flight.state.position = Vector3(0, 10000, 0)
	flight.state.velocity = Vector3(0, 100, 0)
	flight.telemetry()
	var before := flight.state.duplicate(true)
	check(flight.execute_stage().contains("held"), "Unsafe chute stage held")
	check(flight.state == before and flight.state.stage_index == index, "Held stage has no side effects")
	flight.state.position = Vector3(0, 1000, 0)
	flight.state.velocity = Vector3(0, -50, 0)
	flight.telemetry()
	flight.execute_stage()
	check(flight.state.chute_deployed, "Safe chute stage deploys")
	check(flight.execute_stage() == "No stages remaining.", "Completed stage cannot execute twice")
	# An invalid grouped stage must not separate first and then reject ignition.
	craft.stages = [["ignite:engine", "ignite:boosters"], ["separate:decoupler", "separate:boosters"], ["deploy:capsule"]]
	design = Craft.project(craft, legacy)
	flight.reset(design)
	flight.execute_stage()
	flight._design.assembly.stages[1].append("ignite:engine")
	before = flight.state.duplicate(true)
	flight.execute_stage()
	check(flight.state == before, "Invalid grouped stage does not partly fire")
	# Complete a recovery using only stage actions, with no manual chute shortcut.
	design = Craft.project(Craft.migrate(Parts.default_design()), Parts.default_design())
	flight.reset(design)
	flight.execute_stage()
	var separated := false
	for frame in range(15000):
		var state := flight.telemetry()
		if state.max_altitude >= 1000 and not separated:
			flight.execute_stage()
			separated = true
		if state.chute_safe and not state.chute_deployed: flight.execute_stage()
		if state.status in ["landed", "crashed"]: break
		flight.step(0.1, {"throttle": 1.0})
	check(flight.state.status == "landed" and flight.state.stage_index == 3, "Configured three-stage rocket recovers safely")
	for failure in failures: push_error(failure)
	print("PASS: %d craft and stage checks." % count if failures.is_empty() else "FAIL: craft and stage checks")
	quit(0 if failures.is_empty() else 1)
