extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Craft = preload("res://scripts/craft_model.gd")
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game._new_craft()
	await process_frame
	var card: Node
	for child in game.assembly_list.get_children():
		if child.get("part_id") == "parachute": card = child
	check(card != null and card.locked, "Parachute card is visible and awaits a capsule")
	game._attach_part("capsule", "capsule")
	await process_frame
	await process_frame
	check(game._part_available("parachute"), "Capsule unlocks parachute")
	var snap: Vector3 = game._snap_candidates("parachute")[0][1]
	var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(snap))
	check(game._update_build_drag("parachute", screen), "Parachute drag finds top mount")
	game._finish_build_drag("parachute", screen)
	await process_frame
	await process_frame
	check(game.design.get("parachute", false), "Dragging installs parachute")
	check(not game._part_available("parachute"), "Duplicate module is unavailable")
	check(Craft.valid(game.design.assembly), "Craft with top module validates")
	game._attach_part("decoupler", "decoupler")
	await process_frame
	await process_frame
	var module_part: Dictionary = game.design.assembly.parts.filter(func(p): return p.kind == "parachute")[0]
	check(module_part.parent == "capsule" and module_part.port == "top", "Adding lower stack preserves capsule top attachment")
	check(Craft.valid(game.design.assembly), "Top module and lower stack validate together")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.design))
	check(Parts.normalize_design(saved).get("parachute", false), "Parachute survives save round trip")
	var module = game.world._parachute_module
	# These checks cover the landed cloth itself; the fade is checked last.
	module.fade_after_landing = false
	check(is_instance_valid(module), "Installed model includes deployment module")
	check(not module.canopy.visible and is_zero_approx(module.elapsed), "Starts packed")
	var cap_rest: Transform3D = module.cap_pivot.transform
	module.advance(true, 0.7)
	check(module.canopy.visible and module.canopy.scale.x < 0.1, "Cap release precedes inflation")
	check(module.cap_pivot.transform != cap_rest, "Nose cap moves clear")
	var partial: float = module.elapsed
	module.advance(true, 0)
	check(module.elapsed == partial, "Paused time freezes deployment")
	module.advance(true, 3)
	check(module.canopy.scale.is_equal_approx(Vector3.ONE), "Canopy fully inflates")
	check(module.housing.visible and module.tether.visible, "Open housing and cap retention cord stay visible")
	check(module.housing.find_child("Lower_canister", true, false) != null, "Open lower canister persists")
	check(module.housing.find_child("Deployment_well_and_spool", true, false) != null, "Opened well contains visible hardware")
	var inflated_points: PackedVector3Array = module.canopy.points.duplicate()
	for frame in range(60): module.advance(true, 1.0 / 60.0, true)
	check(module.canopy.visible and module.canopy.scale.is_equal_approx(Vector3.ONE), "Touchdown preserves canopy size and visibility")
	check(module.canopy.points[0].y < inflated_points[0].y - 0.5, "Unsupported fabric falls under gravity")
	var frozen_points: PackedVector3Array = module.canopy.points.duplicate()
	module.advance(true, 0.0, true)
	check(module.canopy.points == frozen_points, "Pause freezes cloth and ropes")
	for frame in range(300): module.advance(true, 1.0 / 60.0, true)
	var low_points := 0
	for point in module.canopy.points:
		check(point.is_finite(), "Cloth remains finite during settling")
		check(point.y >= module.canopy.ground_offset + 0.034, "Cloth and cords remain above ground")
		if point.y < 0: low_points += 1
	check(low_points > module.canopy.CLOTH_COUNT / 2, "Fabric settles around the capsule rather than retracting")
	check(module.canopy.visible and module.housing.visible and module.tether.visible, "Settled fabric and released hardware remain visible")
	var slack := false
	for link in module.canopy.links:
		var length: float = module.canopy.points[int(link.x)].distance_to(module.canopy.points[int(link.y)])
		if int(link.x) >= module.canopy.CLOTH_COUNT:
			slack = slack or length < link.z * 0.9
		check(length < link.z * 1.3, "Elastic constraints bound fabric and rope stretch")
	check(slack, "Suspension cords go slack after landing")
	module.fade_after_landing = true
	module.advance(true, 1.0 / 60.0, true)
	check(module.canopy.materials[0].albedo_color.a < 1.0 and module.canopy.materials[0].transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and module.canopy.fabric.visible, "Landed chute fades while it collapses")
	check(module.collapse_bake != null and module._replaying, "Landing replays the baked collapse instead of simulating cloth")
	for frame in range(90): module.advance(true, 1.0 / 60.0, true)
	var faded_points: PackedVector3Array = module.canopy.points.duplicate()
	for frame in range(30): module.advance(true, 1.0 / 60.0, true)
	check(not module.canopy.fabric.visible and not module.canopy.cords.visible and not module.tether.visible and not module.cap_pivot.visible, "Faded chute, cords and cap are hidden")
	check(module.canopy.points == faded_points, "Faded chute stops simulating")
	module.advance(false, 0)
	check(module.canopy.fabric.visible and is_equal_approx(module.canopy.materials[0].albedo_color.a, 1.0) and module.canopy.materials[0].transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and module.cap_pivot.visible, "Repacking restores the faded chute")
	check(not module.canopy.grounded and module.canopy.points == module.canopy.rest, "Repacking resets cloth simulation")
	check(module.cap_pivot.transform.is_equal_approx(cap_rest) and not module.canopy.visible, "Reset repacks cap and canopy")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://assets/models/parachute_1/workshop.png")
	game._remove_part_to_catalogue("parachute")
	await process_frame
	await process_frame
	check(not game.design.get("parachute", false) and game._part_available("parachute"), "Return to inventory restores availability")
	# Recovery-module mass stays on the capsule after staging.
	var design := Parts.default_design()
	var assembly := Craft.migrate(design)
	Craft.add_part(assembly, "parachute")
	design = Craft.project(assembly, design)
	var base_stats := Parts.stats(Parts.default_design())
	check(is_equal_approx(Parts.stats(design).dry_mass-base_stats.dry_mass, Parts.PARACHUTE_MASS), "Module contributes 18 kg")
	var flight := Flight.new()
	flight.reset(design)
	var initial_mass := flight._current_mass()
	flight._separate_core()
	check(is_equal_approx(flight._current_mass(), Parts.CAPSULE_MASS+Parts.PARACHUTE_MASS), "Module stays with recovery capsule")
	check(is_equal_approx(initial_mass, flight._current_mass()+flight.state.detached.back().mass), "Separation conserves mass")
	flight.state.position = Vector3(0, 1000, 0)
	flight.state.velocity = Vector3(0, -20, 0)
	flight.state.status = "flying"
	var deployment_attitude := Basis.from_euler(Vector3(0.3, 0.4, 1.1))
	flight.state.orientation = deployment_attitude
	flight.telemetry()
	flight.deploy_chute()
	check(Basis(flight.state.orientation).is_equal_approx(deployment_attitude), "Deployment preserves vessel attitude")
	game.world.set_design(design)
	game.world.set_mode("flight")
	# Relaunching after a cut needs the physical landed canopy, not the fade.
	game.world._parachute_module.fade_after_landing = false
	game.world.sync_flight(flight.telemetry(), 3.0)
	check(game.world._rocket.basis.is_equal_approx(deployment_attitude), "Deployed parachute does not render vessel upright")
	var rotating_attitude := Basis.from_euler(Vector3(-0.4, 0.2, 1.5))
	flight.state.orientation = rotating_attitude
	game.world.sync_flight(flight.telemetry(), 0.0)
	check(game.world._rocket.basis.is_equal_approx(rotating_attitude), "Open parachute continues to follow vessel attitude")
	check(game.world._parachute_module.elapsed == 2.6, "Flight deployment advances module animation")
	check(game.world._parachute_module.housing.is_visible_in_tree(), "Opened housing remains visible on recovered capsule")
	flight.state.status = "landed"
	game.world.sync_flight(flight.telemetry(), 0.7)
	check(game.world._parachute_module.canopy.grounded, "Flight touchdown releases fabric pressure")
	game.world.sync_flight(flight.telemetry(), 3.0)
	check(game.world._parachute_module.canopy.visible, "Landed flight retains physical canopy")
	var spent_canopy: Node3D = game.world._parachute_module.canopy
	var landing_transform := spent_canopy.global_transform
	flight.state.chute_deployed = false
	flight.state.chute_cut = true
	flight.state.status = "flying"
	game.world.sync_flight(flight.telemetry(), 0)
	check(spent_canopy.get_parent() == game.world._landscape, "Cut canopy remains at landing site")
	check(spent_canopy.global_position.distance_to(landing_transform.origin) < 0.001 and spent_canopy.global_basis.is_equal_approx(landing_transform.basis), "Cutting does not teleport or repack cloth")
	check(game.world._parachute_module.cap_released, "Cutting keeps housing open")
	var ground_transform := spent_canopy.transform
	flight.state.position += Vector3(0, 20, 0)
	game.world.sync_flight(flight.telemetry(), 0.1)
	check(spent_canopy.transform.is_equal_approx(ground_transform), "Spent canopy stays with ground as vessel leaves")
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: parachute menu, drag attachment, save, removal, animated deployment, open housing and recovery mass")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
