extends SceneTree
## Graphical source-game diagnostic at 3,000,000 km. One explicit 60 Hz
## physics tick per rendered frame; timings are not native-scheduler FPS.
## Run with isolated XDG storage, --resolution 1280x720 and --disable-vsync.
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This benchmark requires a graphical display")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	await game._roll_out()
	game.throttle = 0.0
	game.physical_warp = false
	var f = game.flight
	for altitude in [3000000000.0]:
		for rate in [1.0, 100000.0]:
			for variant in ["toward", "away", "no_clouds"]:
				f.state.status = "flying"
				f.state.throttle = 0.0
				f.state.position = f.PLANET_CENTER + Vector3.BACK * (f.PLANET_RADIUS + altitude)
				f.state.velocity = Vector3.BACK * 3000.0
				game.warp = rate
				var times := []
				var cpus := []
				for i in range(25):
					var start := Time.get_ticks_usec()
					game._physics_process(1.0/60.0)
					game.world.camera.look_at(game.world._planet.position if variant != "away" else -game.world._planet.position, Vector3.UP)
					game.world._update_atmosphere()
					game.world._clouds.visible = variant != "no_clouds"
					game.world._clouds._sync_lowres()
					var cpu := (Time.get_ticks_usec()-start)/1000.0
					await process_frame
					await RenderingServer.frame_post_draw
					if i >= 5:
						cpus.append(cpu)
						times.append((Time.get_ticks_usec()-start)/1000.0)
				cpus.sort()
				times.sort()
				print("FLIGHT %s altitude=%.0fkm warp=%d cpu=%.2f max_cpu=%.2f frame=%.2f max_frame=%.2f" % [variant, altitude/1000.0, rate, cpus[10], cpus[-1], times[10], times[-1]])
	game.sound.shutdown()
	game.free()
	quit()
