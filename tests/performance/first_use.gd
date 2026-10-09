extends SceneTree
## First-use wall-frame capture, including the event itself (no effect warmup).
## Pass the same --config JSON format as the checkpoint runner, with scenario
## ignition, reentry, map, or impact. Production rollout warmup is left intact.
const Game = preload("res://scripts/main.gd")
const Parts = preload("res://scripts/parts.gd")
var game: Node
var viewports: Array[Viewport] = []
var config: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _collect(node: Node) -> void:
	if node is Viewport:
		viewports.append(node)
		RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(), true)
	for child in node.get_children(true): _collect(child)

func _cover_present() -> bool:
	for child in game.ui.get_children():
		if child is ColorRect: return true
	return false

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2 and args[0] == "--config")
	config = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	assert(DisplayServer.get_name() != "headless")
	seed(17171)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var startup := Time.get_ticks_usec()
	game = Game.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.sound.enabled = false
	game.design = Parts.default_design()
	game._refresh_design(false)
	game.world._clouds.time_scale = 0.0
	await RenderingServer.frame_post_draw
	var rollout_start := Time.get_ticks_usec()
	await game._roll_out()
	# The original rollout returns before its asynchronous cover disappears.
	while _cover_present():
		await process_frame
		await RenderingServer.frame_post_draw
	var rollout_ms := (Time.get_ticks_usec() - rollout_start) / 1000.0
	game.paused = true
	var state: Dictionary = game.flight.telemetry().duplicate(true)
	var scenario := str(config.scenario)
	if scenario == "reentry":
		state.position = Vector3(0, 12000, 0)
		state.altitude = 12000.0
		state.orientation = Basis(Vector3.BACK, -PI / 2.0)
		state.status = "flying"
		state.velocity = Vector3(2000, -120, 0)
		state.air_velocity = state.velocity
		state.heat_glow = 0.0
		state.heating_rate = 0.0
		game.world.sync_flight(state, 0.0)
	elif scenario == "map":
		state.position = Vector3(0, 100000, 0)
		state.altitude = 100000.0
		state.velocity = Vector3(sqrt(game.flight.MU / (game.flight.PLANET_RADIUS + 100000.0)), 0, 0)
		state.status = "flying"
		game.world.sync_flight(state, 0.0)
		game.map_instrument.set_flight_state(state)
	_collect(root)
	# Settle the pre-event view only. Never draw the target effect here.
	for frame in range(30):
		await process_frame
		await RenderingServer.frame_post_draw
	var samples := []
	var last := Time.get_ticks_usec()
	var event_us := last
	for frame in range(120):
		if frame == 0:
			match scenario:
				"ignition":
					game.paused = false
					game._stage()
					game.paused = true
					game.flight.step(1.0 / 60.0, {"throttle": 1.0, "sas": true})
					game.world.sync_flight(game.flight.telemetry(), 0.0)
				"reentry":
					state.heat_glow = 1.0
					state.heating_rate = 180.0
					game.world.sync_flight(state, 0.0)
				"map":
					game.map_panel.show()
				"impact":
					game.world._sync_surface_impacts({"surface_impacts": [{"position": game.world._flight_position, "radius": 3.0}]}, game.world._flight_position)
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var gpu := 0.0
		for viewport in viewports:
			if viewport is SubViewport and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED: continue
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
		samples.append({"frame": frame, "elapsed_ms": (now - event_us) / 1000.0, "frame_ms": (now - last) / 1000.0, "gpu_ms": gpu})
		last = now
	var errors := []
	match scenario:
		"ignition":
			if not game.world._main_flames.any(func(flame): return flame.visible): errors.append("No exhaust visible")
		"reentry":
			if not game.world._heat_trail.visible: errors.append("No heat wake visible")
		"map":
			if not game.map_panel.is_visible_in_tree(): errors.append("Map not visible")
		"impact":
			if game.world._impact_effects.is_empty(): errors.append("No impact rendered")
	if not samples.any(func(sample): return sample.gpu_ms > 0.0): errors.append("No GPU timings")
	if root.size != Vector2i(1280, 720): errors.append("Unexpected viewport resolution")
	var result := {"status": "ok" if errors.is_empty() else "error", "errors": errors,
		"scenario": scenario, "rollout_ms": rollout_ms, "startup_ms": (rollout_start - startup) / 1000.0,
		"samples": samples, "gpu": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info().string, "resolution": [root.size.x, root.size.y]}
	var file := FileAccess.open(str(config.output_dir).path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	root.get_texture().get_image().save_png(str(config.output_dir).path_join("final.png"))
	game.sound.shutdown()
	game.free()
	print("FIRST_USE ", scenario, " ", result.status, " rollout_ms=", rollout_ms)
	quit(0 if errors.is_empty() else 1)
