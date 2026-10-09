extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Flight = preload("res://scripts/flight_model.gd")
const World = preload("res://scripts/world_view.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var craft := Parts.Craft.migrate(Parts.default_design())
	Parts.Craft.add_part(craft,"decoupler","engine")
	Parts.Craft.add_part(craft,"tank")
	Parts.Craft.add_part(craft,"kestrel")
	var lower_engine: Dictionary = craft.parts[-1]
	var lower_tank: String = lower_engine.parent
	Parts.Craft.add_part(craft,"separator","tank_1")
	var upper_separator: String = craft.parts[-1].id
	Parts.Craft.add_part(craft,"separator",lower_tank)
	var lower_separator: String = craft.parts[-1].id
	craft.parts[-1].rotation = 67.0
	craft.parts[-1].surface_offset = 0.2
	craft.parts.append(Parts.Craft.node("separator","separator",lower_tank,"radial_pair"))
	for part in craft.parts:
		if part.id == lower_tank: part.rotation = 35.0
	var design := Parts.Craft.project(craft,Parts.default_design())
	var lower: Dictionary = Parts.Craft.engines(design)[1]
	var world := World.new()
	root.add_child(world)
	world.set_design(design)
	world.set_mode("flight")
	var separator_nodes: Array[Node3D] = []
	var retained_separator: Node3D
	var local_poses: Array[Transform3D] = []
	var mounts := Parts.Craft.radial_instances(design,"separator")
	for candidate in world._rocket.find_children("*","Node3D",true,false):
		var id: String = candidate.get_meta("part_id", "")
		if id == upper_separator: retained_separator = candidate
		if id not in [lower_separator,"separator"]: continue
		separator_nodes.append(candidate)
		local_poses.append(candidate.transform)
		check(candidate.get_parent().get_meta("part_id", "") == lower_tank, "Separator scene parent is its attached tank")
		var position: Vector3 = world._rocket.to_local(candidate.global_position)
		check(mounts.any(func(mount): return mount.id == id and position.distance_to(mount.position) < 0.0001), "Parenting preserves separator position on rotated tank")
	check(separator_nodes.size() == 3, "Single separator and legacy pair are all rendered")
	var flight := Flight.new()
	flight.reset(design)
	var lower_flames: Array = world._engine_flames[lower.id]
	flight.execute_stage()
	world.sync_flight(flight.telemetry(),0.0)
	check(not world._engine_flames.engine[0].visible and world._engine_flames[lower.id][0].visible, "Only the ignited lower engine shows exhaust")
	flight.execute_stage()
	world.sync_flight(flight.telemetry(),0.0)
	check(world._detached_nodes.size() == 1, "Lower stage becomes a separate rendered body")
	for index in range(separator_nodes.size()):
		var separator := separator_nodes[index]
		check(world._detached_nodes[0].is_ancestor_of(separator) and not world._rocket.is_ancestor_of(separator), "Lower separators depart with the detached stage")
		check(separator.transform.is_equal_approx(local_poses[index]), "Separation preserves separator pose relative to tank")
	check(retained_separator != null and world._rocket.is_ancestor_of(retained_separator), "Upper tank separator stays attached to the vessel")
	check(is_equal_approx(flight.state.detached[0].dry_mass,Parts.TANK_DRY_MASS+Parts.ENGINES.kestrel.mass+3*Parts.SEPARATOR_MASS), "Detached mass includes every lower separator instance")
	flight.state.detached[0].position += Vector3(10,-5,3)
	flight.state.detached[0].orientation = Basis(Vector3.UP,0.7)
	world.sync_flight(flight.telemetry(),0.0)
	for index in range(separator_nodes.size()):
		check(separator_nodes[index].transform.is_equal_approx(local_poses[index]), "Separators follow moving and rotating detached tank")
	var upper_visual := world._rocket.find_child("Installed_engine",true,false)
	check(upper_visual != null and world._rocket.is_ancestor_of(upper_visual), "Upper engine remains in the rocket")
	var lower_visual := world._detached_nodes[0].find_child("Installed_" + str(lower.id),true,false) if not world._detached_nodes.is_empty() else null
	check(lower_visual != null, "Detached stage carries the lower engine")
	flight.execute_stage()
	world.sync_flight(flight.telemetry(),0.0)
	check(world._engine_flames.engine[0].visible, "Upper engine exhaust starts on its own ignition stage")
	check(lower_flames[0].visible, "Fueled running engine keeps its exhaust after separation")
	var piece: Dictionary = flight.state.detached[0]
	check(is_equal_approx(piece.thrust, Parts.ENGINES.kestrel.thrust), "Released engine retains thrust")
	var release_position: Vector3 = piece.position
	piece.position = Vector3(0,30000,0)
	piece.velocity = Vector3.ZERO
	piece.angular_momentum = Vector3.ZERO
	var fuel_before: float = piece.fuel
	flight._integrate_detached(0.02)
	check(piece.fuel < fuel_before, "Released engine continues consuming its fuel")
	piece.engines[0].fuel = 0.001
	piece.fuel = 0.001
	flight._integrate_detached(0.02)
	flight._integrate_detached(0.02)
	piece.position = release_position
	world.sync_flight(flight.telemetry(),0.0)
	check(is_zero_approx(piece.fuel) and is_zero_approx(piece.thrust), "Released engine stops at fuel exhaustion")
	check(not lower_flames[0].visible, "Released engine exhaust stops at fuel exhaustion")
	for mode in ["off", "empty", "partial"]:
		var scenario := Flight.new()
		scenario.reset(design)
		scenario.execute_stage()
		scenario.state.throttle = 0.4
		if mode == "off": scenario.state.engine_on = false
		if mode == "empty":
			scenario.state.fuel -= scenario.state.engine_fuel[lower.id]
			scenario.state.engine_fuel[lower.id] = 0.0
		scenario.execute_stage()
		var released: Dictionary = scenario.state.detached[0]
		check(is_equal_approx(released.thrust, Parts.ENGINES.kestrel.thrust * 0.4 if mode == "partial" else 0.0), "Separation preserves engine state and throttle: " + mode)
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: multistage engine rendering and separation" if failures.is_empty() else "FAIL: multistage engine rendering")
	quit(0 if failures.is_empty() else 1)
