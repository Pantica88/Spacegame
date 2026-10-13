extends SceneTree
## Run headless for state/pool checks; run with a display to verify draw coverage.
var game: Node
var failures: Array[String] = []
var covered_workshop := false
var drew_wake := false
var drew_map := false
var drew_system := false
var drew_background := false
var loading_frames := 0

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _observe_loading() -> void:
	if not game._preparing_launch: return
	loading_frames += 1
	check(paused, "Loading freezes the simulation tree")
	check(game.ui.has_node("LaunchLoadingCover"), "Every preparation frame has a cover")
	covered_workshop = covered_workshop or game.mode == "workshop"
	if game.mode != "flight": return
	check(game.flight.simulation_time() == 0.0, "Loading never advances the flight clock")
	check(game.flight.state.status == "ready", "Loading never ignites the vehicle")
	if game.world._heat_trail.visible:
		drew_wake = true
		check(game.world._heat_trail.material_override.get_shader_parameter("strength") > 0.0, "Warmup draws an active wake")
	if game.map_panel.visible:
		drew_map = true
		drew_system = drew_system or game.map_instrument.system_focus
		drew_background = drew_background or game.map_instrument.background_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
	# Both a duplicate rollout and a launch hotkey must be harmless while loading.
	game._roll_out()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	root.push_input(event)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# Exercise optional heating warmup even while normal gameplay disables it.
	game.world.aerothermal_effects_enabled = true
	game.set_physics_process(false)
	game.design = game.Parts.default_design()
	var craft = game.Parts.Craft.migrate(game.design)
	game.Parts.Craft.add_part(craft, "parachute")
	game.design = game.Parts.Craft.project(craft, game.design)
	game._refresh_design(false)
	RenderingServer.frame_pre_draw.connect(_observe_loading)
	await game._roll_out()
	RenderingServer.frame_pre_draw.disconnect(_observe_loading)
	check(not paused and not game._preparing_launch, "Rollout releases the loading lock")
	check(not game.ui.has_node("LaunchLoadingCover"), "Rollout removes the cover")
	check(game.flight.simulation_time() == 0.0, "Flight starts at zero after warmup")
	check(not game.map_panel.visible and not root.disable_3d, "Flight rendering resumes after map warmup")
	check(not game.world.rendering_suspended, "World rendering resumes")
	check(game.map_instrument.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden map stops rendering")
	check(game.map_instrument.background_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden map background stops rendering")
	check(game.map_instrument.maneuver.epoch < 0.0, "Warmup creates no maneuver")
	check(not game.world._heat_trail.visible and game.world._heated_meshes.is_empty(), "No warmup heat remains")
	check(not game.world._chute.visible and not game.world._parachute_module.opened, "Warmup leaves parachute packed")
	check(game.world._planet.mesh == game.flight.terrain.render_mesh_for_lod(game.world._planet_lod), "Launch terrain mesh is restored")
	check(game.flight.terrain._render_meshes.size() == game.flight.terrain.RENDER_LODS.size(), "All flight terrain detail levels are prepared")
	for body in game.flight._debris_surfaces(game.flight.simulation_time()):
		check(body.terrain.collision != null, "Home and moon contacts are prepared under the launch cover")
	if DisplayServer.get_name() != "headless":
		check(covered_workshop, "Cover renders before craft rollout")
		check(drew_wake and drew_map and drew_system and drew_background, "Warmup renders wake, local map, system map and distant background")
		print("Warmup rendered %d covered frames" % loading_frames)
	# Exercise the effect state directly too, including headless CI.
	var world = game.world
	var packed_transform: Transform3D = world._chute.transform
	world.prewarm_effects(true)
	check(world._heat_trail.visible, "Warmup enables the reentry wake")
	check(world._chute.scale == Vector3.ONE, "Warmup displays full-size canopy geometry")
	for flame in world._main_flames:
		check(flame.visible and flame.scale.y > 0.8, "Warmup displays full-size exhaust")
	world.prewarm_effects(false)
	world.sync_flight(game.flight.telemetry(), 0.0)
	check(world._chute.transform.is_equal_approx(packed_transform), "Warmup restores packed canopy transform")
	var pooled: Array = world._impact_pool.duplicate()
	check(pooled.size() == world.IMPACT_POOL_SIZE, "Rollout fills impact pool")
	var impact_state := {"surface_impacts": [{"position": Vector3.ZERO, "radius": 3.0}]}
	world._sync_surface_impacts(impact_state, Vector3.ZERO)
	check(world._impact_effects[0].node in pooled, "First impact reuses a prepared object")
	world._clock += 1.0
	world._sync_surface_impacts(impact_state, Vector3.ZERO)
	check(world._impact_effects.is_empty() and world._impact_pool.size() == pooled.size(), "Expired impact returns to pool")
	for node in world._impact_pool: check(not node.visible, "Idle impact objects stay hidden")
	game.map_panel.show()
	await game._roll_out()
	check(world._impact_pool.size() == pooled.size(), "Repeated rollout does not grow the pool")
	check(not root.disable_3d and not game.map_panel.visible, "Retry from an open map restores flight rendering")
	for node in world._impact_pool: check(node in pooled, "Repeated rollout reuses impact objects")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: launch cover, frozen flight, effect warmup, terrain readiness and impact reuse" if failures.is_empty() else "FAIL: launch warmup")
	quit(0 if failures.is_empty() else 1)
