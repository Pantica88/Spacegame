extends SceneTree
## Invoked by perf.sh; no gameplay source or player saves are modified.
const TimedGame = preload("res://tests/performance/timed_game.gd")
const Parts = preload("res://scripts/parts.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const FIXTURE_VERSION := 2
const SCENARIOS := ["launch", "dense_clouds", "staging", "orbit", "map", "reentry", "parachute", "landing"]
var config: Dictionary
var game: Node
var samples: Array[Dictionary] = []
var errors: Array[String] = []
var started_us := 0
var measuring_us := 0
var last_frame_us := 0
var output_dir := ""
var measured_viewports: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--config":
		push_error("Usage: --script res://tests/performance/run_scenario.gd -- --config /absolute/config.json")
		quit(1)
		return
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not decoded is Dictionary:
		push_error("Invalid performance lab configuration")
		quit(1)
		return
	config = decoded
	output_dir = str(config.get("output_dir", ""))
	if not output_dir.is_absolute_path() or DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("An absolute writable output directory is required")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or str(config.get("scenario", "")) not in SCENARIOS:
		_fail("A graphical display and a recognized scenario are required")
		return
	seed(int(config.get("seed", 17171)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 60
	started_us = Time.get_ticks_usec()
	game = TimedGame.new()
	game.perf_scenario = str(config.scenario)
	game.perf_target_ticks = maxi(120, roundi(float(config.get("sample_seconds", 8.0)) * 60.0))
	root.add_child(game)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	await _setup_fixture()
	game.paused = true
	_collect_viewports(root)
	for viewport in measured_viewports:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var setup_ms := (Time.get_ticks_usec() - started_us) / 1000.0
	await process_frame
	await RenderingServer.frame_post_draw
	var first_frame_ms := (Time.get_ticks_usec() - started_us) / 1000.0
	var startup_to_first_frame_ms := Time.get_ticks_usec() / 1000.0
	# Warm rendering of the checkpoint; ignition/deployment/separation remain
	# measured events. This does not pretend to clear the GPU driver's disk cache.
	last_frame_us = Time.get_ticks_usec()
	game.perf_take_counters()
	var warmup_end := last_frame_us + int(float(config.get("warmup_seconds", 2.0)) * 1000000.0)
	while Time.get_ticks_usec() < warmup_end:
		await _sample("warmup")
	var noise: NoiseTexture3D = game.world._clouds.material_override.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty():
		await noise.changed
	var actual_size := root.size
	var expected: Array = config.get("expected_resolution", [1280, 720])
	if actual_size != Vector2i(int(expected[0]), int(expected[1])):
		errors.append("Viewport resolution differs from requested size: %s" % actual_size)
	game.perf_take_counters()
	game.paused = false
	game.perf_running = true
	measuring_us = Time.get_ticks_usec()
	last_frame_us = measuring_us
	while game.perf_tick < game.perf_target_ticks:
		await _sample("measure")
	game.perf_running = false
	game.paused = true
	_validate_fixture()
	var events := []
	for event in game.perf_events:
		events.append({"tick": event.tick, "name": event.name, "elapsed_ms": (int(event.at_us) - measuring_us) / 1000.0})
	var metadata := {"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.call("get_video_adapter_api_version") if RenderingServer.has_method("get_video_adapter_api_version") else "unknown",
		"logical_viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"gpu": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"viewport": [actual_size.x, actual_size.y], "seed": int(config.get("seed", 17171)),
		"fixture_version": FIXTURE_VERSION, "physics_hz": Engine.physics_ticks_per_second,
		"mode": "native-physics-gameplay-checkpoint", "display_server": DisplayServer.get_name(),
		"timing_notes": "Frame wall intervals use post-draw boundaries. GPU timers may lag CPU events. GPU is summed over all active viewports, including offscreen clouds. Render CPU includes frame setup; game CPU covers main.gd callbacks only, excluding independently processing child nodes. CPU and GPU overlap; do not add them. Physics uses native 60 Hz scheduling; snapshots skip the journey to each checkpoint."}
	var result := {"schema_version": 1, "scenario": config.scenario,
		"status": "ok" if errors.is_empty() else "error", "errors": errors,
		"metadata": metadata, "setup_ms": setup_ms, "first_frame_ms": first_frame_ms,
		"startup_to_first_frame_ms": startup_to_first_frame_ms,
		"simulation_ticks": game.perf_tick, "samples": samples, "events": events,
		"observed": game.perf_seen, "final_status": game.flight.state.status}
	if bool(config.get("capture", true)):
		# Readback/PNG encoding occur only after all timed samples.
		var image := root.get_texture().get_image()
		if image.get_size() != actual_size:
			errors.append("Screenshot dimensions differ from measured viewport")
			result.status = "error"
		if image.save_png(output_dir.path_join("final.png")) != OK:
			errors.append("Could not save final screenshot")
			result.status = "error"
	_write_result(result)
	game.sound.shutdown()
	game.free()
	print("PERF_LAB ", config.scenario, " ", result.status, " samples=", samples.size())
	quit(0 if errors.is_empty() else 1)

func _sample(phase: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var now := Time.get_ticks_usec()
	var sample: Dictionary = game.perf_take_counters()
	sample.merge({"frame_index": samples.size(), "phase": phase,
		"elapsed_ms": (now - (measuring_us if phase == "measure" else started_us)) / 1000.0,
		"simulation_tick": game.perf_tick, "frame_ms": (now - last_frame_us) / 1000.0})
	last_frame_us = now
	var gpu := 0.0
	var render_cpu := RenderingServer.get_frame_setup_time_cpu()
	var viewport_times := {}
	for viewport in _active_viewports():
		var rid: RID = viewport.get_viewport_rid()
		var value := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		gpu += value
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		viewport_times[str(viewport.get_path())] = value
	sample.gpu_ms = gpu
	sample.render_cpu_ms = render_cpu
	sample.viewport_gpu_ms = viewport_times
	sample.draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	sample.objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	sample.primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	samples.append(sample)

func _collect_viewports(node: Node) -> void:
	if node == root or node is SubViewport:
		measured_viewports.append(node)
	# Cloud viewports are internal children and still consume GPU time.
	for child in node.get_children(true):
		_collect_viewports(child)

func _active_viewports() -> Array:
	var result: Array = []
	for viewport in measured_viewports:
		if viewport == root or viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			result.append(viewport)
	return result

func _heavy_design() -> Dictionary:
	var design := Parts.default_design()
	design.engine = "titan"
	var craft := Parts.Craft.migrate(design)
	var separate := []
	for index in range(8):
		Parts.Craft.add_part(craft, "separator", "tank_2")
		var mount: Dictionary = craft.parts[-1]
		mount.rotation = 360.0 * index / 8
		separate.append("separate:" + str(mount.id))
		Parts.Craft.add_part(craft, "tank", mount.id)
		Parts.Craft.add_part(craft, "tank", craft.parts[-1].id)
		Parts.Craft.add_part(craft, "titan", craft.parts[-1].id)
	var ignition := []
	for part in craft.parts:
		if part.kind in Parts.Craft.ENGINE_IDS:
			ignition.append("ignite:" + str(part.id))
	craft.stages = [ignition, separate, ["separate:decoupler"], ["deploy:capsule"]]
	assert(Parts.Craft.valid(craft), "Heavy benchmark craft must be valid")
	return Parts.Craft.project(craft, design)

func _setup_fixture() -> void:
	var scenario := str(config.scenario)
	var design := _heavy_design() if scenario in ["launch", "staging"] else Parts.default_design()
	if scenario in ["parachute", "landing"]:
		var assembly := Parts.Craft.migrate(design)
		Parts.Craft.add_part(assembly, "parachute")
		assembly.stages = [["ignite:engine"], ["separate:decoupler"], ["deploy:capsule"]]
		design = Parts.Craft.project(assembly, design)
	game.design = design
	await game._roll_out()
	game.recorded = true # Never record fixture flights, even in isolated saves.
	game.mission_index = 0
	game.world._yaw = 0.6
	game.world._pitch = 0.1
	if scenario == "launch":
		return
	game._set_throttle(0.0)
	game.flight.state.status = "flying"
	game.flight._has_lifted = true
	var altitude := 3850.0
	var velocity := Vector3(20, 0, 0)
	if scenario == "staging":
		game.flight.state.status = "ready"
		game._set_throttle(1.0)
		game._stage()
		altitude = 1000.0
		velocity = Vector3(0, 100, 0)
	elif scenario in ["orbit", "map"]:
		altitude = 100000.0
		velocity = Vector3(sqrt(game.flight.MU / (game.flight.PLANET_RADIUS + altitude)), 0, 0)
	elif scenario == "reentry":
		altitude = 12000.0
		velocity = Vector3(2000, -120, 0)
		game.flight.state.temperature = 1300.0
		game.flight.state.orientation = Basis(Vector3.BACK, -PI / 2.0)
	elif scenario in ["parachute", "landing"]:
		altitude = 1000.0
		game.flight.state.stage_index = 1
		game._stage()
		velocity = game.flight.terrain.surface_velocity(Vector3(0, game.flight.PLANET_RADIUS + altitude, 0)) + Vector3(0, -25, 0)
	game.flight.state.position = Vector3(0, altitude, 0)
	game.flight.state.velocity = velocity
	if scenario == "dense_clouds":
		var weather := Weather.new()
		var map := Image.create(512, 256, false, Image.FORMAT_RGBA8)
		map.fill(Color(0.35, 0.2, 0.15, 0.3))
		weather.restore(map)
		game.flight.terrain.definition.cloud_weather = weather
	if scenario == "landing":
		# Descend upright under a fully open chute and touch down about two
		# seconds into measurement, as a real recovery does.
		game.flight.state.chute_deployed = true
		game.flight._chute_opening = 1.0
		for i in range(600):
			game.flight.step(1.0 / 60.0, {"throttle": 0.0})
		var surface: Vector3 = game.flight.terrain.surface_velocity(Vector3(0, game.flight.PLANET_RADIUS, 0))
		var descent := maxf(-(game.flight.state.velocity - surface).y, 1.0)
		game.flight.state.position = Vector3(0, descent * 2.0, 0)
		game.flight.state.velocity = surface + Vector3(0, -descent, 0)
		game.flight.state.status = "flying"
		game.world.sync_flight(game.flight.telemetry(), 3.0, 0.0)
	else:
		game.world.sync_flight(game.flight.telemetry(), 0.0)
	game.map_instrument.reset_history(Vector3(game.flight.state.position))
	if scenario == "map":
		game._toggle_map()
		game._sync_map_rendering()
		game.map_instrument.zoom = 0.5

func _validate_fixture() -> void:
	if game.perf_tick != game.perf_target_ticks:
		errors.append("Simulation did not run the requested number of physics ticks")
	var scenario := str(config.scenario)
	if scenario == "launch" and not game.perf_seen.thrust:
		errors.append("Launch never produced thrust")
	if scenario == "staging" and not game.perf_seen.detached:
		errors.append("Staging never produced detached debris")
	if scenario == "dense_clouds" and not game.world._clouds.visible:
		errors.append("Dense cloud fixture did not render clouds")
	if scenario == "map" and not game.map_panel.is_visible_in_tree():
		errors.append("Map viewport was not visible")
	if scenario == "reentry" and not game.perf_seen.heat:
		errors.append("Reentry never displayed its heat wake")
	if scenario in ["parachute", "landing"] and not game.perf_seen.canopy:
		errors.append("Parachute fixture never displayed fabric")
	if scenario == "landing" and game.flight.state.status not in ["landed", "crashed"]:
		errors.append("Landing fixture did not reach the surface")
	var valid_gpu := false
	for sample in samples:
		if sample.phase == "measure" and sample.gpu_ms > 0.0:
			valid_gpu = true
	if not valid_gpu:
		errors.append("No valid GPU timing samples; do not interpret zero as free rendering")

func _write_result(result: Dictionary) -> void:
	var file := FileAccess.open(output_dir.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write performance result")
		quit(1)
		return
	file.store_string(JSON.stringify(result))

func _fail(message: String) -> void:
	_write_result({"schema_version": 1, "scenario": config.get("scenario", ""), "status": "error", "errors": [message], "samples": []})
	push_error(message)
	quit(1)
