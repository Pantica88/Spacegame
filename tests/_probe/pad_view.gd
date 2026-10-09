extends SceneTree
## Probe: on-pad cost when the launch complex is in/out of view.
const TimedGame = preload("res://tests/performance/timed_game.gd")
var game: Node
var vps: Array = []
func _initialize() -> void:
	_run.call_deferred()
func _collect(n: Node) -> void:
	if n == root or n is SubViewport: vps.append(n)
	for c in n.get_children(true): _collect(c)
func _measure(label: String) -> void:
	for i in 40: await process_frame
	var gpu := 0.0; var cpu := 0.0; var wall := 0.0; var dc := 0.0; var prim := 0.0; var obj := 0.0
	var n := 90; var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec(); wall += (now - last) / 1000.0; last = now
		cpu += RenderingServer.get_frame_setup_time_cpu()
		for v in vps:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid())
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(v.get_viewport_rid())
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	print("PAD %-28s wall %6.2f ms  gpu %6.2f  rcpu %5.2f  draws %5d  objs %5d  prims %8d" % [label, wall/n, gpu/n, cpu/n, int(dc/n), int(obj/n), int(prim/n)])
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = TimedGame.new()
	game.perf_scenario = "launch"
	root.add_child(game)
	game.set_process_input(false)
	await game._roll_out()
	game.recorded = true
	game.paused = true
	_collect(root)
	for v in vps: RenderingServer.viewport_set_measure_render_time(v.get_viewport_rid(), true)
	var w = game.world
	var weather_script = load("res://scripts/cloud_weather_map.gd")
	var weather = weather_script.new()
	var map := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	map.fill(Color(0.35, 0.2, 0.15, 0.3))
	weather.restore(map)
	game.flight.terrain.definition.cloud_weather = weather
	var mat: ShaderMaterial = w._clouds.material_override
	var original: String = mat.shader.code
	var inc := FileAccess.get_file_as_string("res://assets/shaders/clouds_volume.gdshaderinc")
	var inline := original.replace('#include "res://assets/shaders/clouds_volume.gdshaderinc"', inc)
	var variants := {
		"base": original,
		"A_cap64": inline.replace("const int AUTHORED_CLOUD_STEPS = 320;", "const int AUTHORED_CLOUD_STEPS = 64;"),
		"B_sky_lowres": original.replace("if (lowres_enabled && lowres_safe && clouds_beyond(segments, clip))", "if (lowres_enabled && (lowres_safe || clip >= 1e19) && clouds_beyond(segments, clip))"),
	}
	var shot_dir := "/tmp/claude-1000/-home-bo-ai-BlufftonGames-001/8f635900-3f23-4f28-9a19-c7a357a90269/scratchpad/"
	var cams := {"pad": [0.6, 0.1, 0.0], "pad_up": [0.6, -0.25, 0.0], "alt3km": [0.6, 0.05, 3000.0]}
	for c in cams:
		if cams[c][2] > 0.0:
			game.flight.state.status = "flying"; game.flight._has_lifted = true
			game.flight.state.position = Vector3(0, cams[c][2], 0)
			game.flight.state.velocity = Vector3.ZERO
			game.world.sync_flight(game.flight.telemetry(), 0.0)
		w._yaw = cams[c][0]; w._pitch = cams[c][1]
		w._update_camera()
		var shaders := {}
		for k in variants:
			var sh := Shader.new(); sh.code = variants[k]; shaders[k] = sh
			mat.shader = sh
			for i in 30: await process_frame
		for k in ["base", "A_cap64", "B_sky_lowres", "base2"]:
			mat.shader = shaders["base" if k == "base2" else k]
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot_dir + c + "_" + k + ".png")
	var orig_sh := Shader.new(); orig_sh.code = original; mat.shader = orig_sh
	quit(0)
	w._yaw = 0.6; w._pitch = 0.1; w._update_camera()
	await process_frame
	root.get_texture().get_image().save_png("/tmp/claude-1000/-home-bo-ai-BlufftonGames-001/8f635900-3f23-4f28-9a19-c7a357a90269/scratchpad/pad.png")
	for v in vps: print("VP ", v.get_path(), " ", RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid()))
	quit(0)
func _census(n: Node, out: Dictionary) -> void:
	if n is VisualInstance3D and n.is_visible_in_tree():
		var key := str(n.get_path()).get_slice("/", 3) + "/" + str(n.get_path()).get_slice("/", 4) + " " + n.get_class()
		out[key] = out.get(key, 0) + 1
	for c in n.get_children(true): _census(c, out)
