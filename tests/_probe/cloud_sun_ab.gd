extends SceneTree
## Probe: old vs new cloud composite across sun positions and views.
const TimedGame = preload("res://tests/performance/timed_game.gd")
const SHOTS := "/tmp/claude-1000/-home-bo-ai-BlufftonGames-001/8f635900-3f23-4f28-9a19-c7a357a90269/scratchpad/sun/"
var game: Node
var w: Node
var sun_dir := Vector3.ZERO
func _initialize() -> void:
	_run.call_deferred()
func _pin_sun() -> void:
	if sun_dir == Vector3.ZERO: return
	w._sun_physical_position = w.camera.position + sun_dir * w.SolarBody.POSITION.length()
	w._update_camera()
func _wall(n: int) -> float:
	var last := Time.get_ticks_usec(); var total := 0.0
	for i in n:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec(); total += (now - last) / 1000.0; last = now
	return total / n
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(SHOTS)
	game = TimedGame.new()
	game.perf_scenario = "launch"
	root.add_child(game)
	game.set_process_input(false)
	await game._roll_out()
	game.recorded = true
	game.paused = true
	w = game.world
	var weather = load("res://scripts/cloud_weather_map.gd").new()
	var map := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	map.fill(Color(0.35, 0.2, 0.15, 0.3))
	weather.restore(map)
	game.flight.terrain.definition.cloud_weather = weather
	RenderingServer.frame_pre_draw.connect(_pin_sun)
	var mat: ShaderMaterial = w._clouds.material_override
	var current: String = mat.shader.code
	var old_code := current.replace("(lowres_safe || clip >= 1e19)", "lowres_safe")
	assert(old_code != current)
	var shaders := {}
	for k in {"old": old_code, "new": current}:
		var sh := Shader.new(); sh.code = old_code if k == "old" else current; shaders[k] = sh
	var up: Vector3 = w._surface_up
	var east := up.cross(Vector3.FORWARD).normalized()
	var north := east.cross(up).normalized()
	var suns := {"noon60": [60.0, 0.0], "low20_front": [20.0, 0.6], "low20_back": [20.0, 0.6 + PI], "sunrise5": [5.0, 1.2], "twilight-3": [-3.0, 0.6]}
	var views := {"level": 0.1, "up": -0.25}
	for v in views:
		w._yaw = 0.6; w._pitch = views[v]
		for s in suns:
			var el := deg_to_rad(suns[s][0]); var az: float = suns[s][1]
			sun_dir = (up * sin(el) + (north * cos(az) + east * sin(az)) * cos(el)).normalized()
			var t := {}
			for k in ["old", "new"]:
				mat.shader = shaders[k]
				for i in 30: await process_frame
				t[k] = await _wall(60)
			for k in ["old", "new", "old2"]:
				mat.shader = shaders["old" if k == "old2" else k]
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(SHOTS + v + "_" + s + "_" + k + ".png")
			print("SUN %-6s %-12s old %6.2f ms  new %6.2f ms" % [v, s, t.old, t.new])
	RenderingServer.frame_pre_draw.disconnect(_pin_sun)
	quit(0)
