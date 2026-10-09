extends SceneTree
## Real game ascent from the pad: frame and GPU time per altitude band.
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2] if not values.is_empty() else 0.0

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(20): await process_frame
	await main._roll_out()
	for i in range(30): await process_frame
	var clouds: Node = main.world._clouds
	if OS.get_environment("TEMPORAL") == "0": clouds.temporal = false
	var main_rid := root.get_viewport_rid()
	var low_rid: RID = clouds.lowres_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	RenderingServer.viewport_set_measure_render_time(low_rid, true)
	main._set_throttle(1.0)
	main._stage()
	var f = main.flight
	var bands := {}
	var last := Time.get_ticks_usec()
	var frames := 0
	while frames < 60 * 240:
		await process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		var alt := float(f.state.get("altitude", 0.0))
		var shot := OS.get_environment("SHOT_AT")
		var hold := OS.get_environment("HOLD_AT")
		if not hold.is_empty() and alt > float(hold):
			# Freeze the climb here and compare variants of the same view.
			main.paused = true
			for variant in ["held"]:
				for i in range(30):
					main.world.sync_flight(main.flight.telemetry(), 0.0)
					await process_frame
				var fs := []
				var gm := []
				var gl := []
				var t := Time.get_ticks_usec()
				for i in range(120):
					await process_frame
					var n := Time.get_ticks_usec()
					fs.append((n - t) / 1000.0)
					t = n
					gm.append(RenderingServer.viewport_get_measured_render_time_gpu(main_rid))
					gl.append(RenderingServer.viewport_get_measured_render_time_gpu(low_rid))
				print("HOLD %s %.0f m %-14s frame %6.2f  gpu main %6.2f  cloud pass %6.2f" % [OS.get_environment("VARIANT"), alt, variant, _median(fs), _median(gm), _median(gl)])
			break
		if not shot.is_empty() and alt > float(shot):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
			print("ASCENT shot at %.0f m" % alt)
			break
		if alt > 12500.0 or f.state.status in ["landed", "crashed"]: break
		var band := int(alt / 500.0) * 500
		if not bands.has(band): bands[band] = [[], [], [], 0.0]
		bands[band][0].append(dt)
		bands[band][1].append(RenderingServer.viewport_get_measured_render_time_gpu(main_rid))
		bands[band][2].append(RenderingServer.viewport_get_measured_render_time_gpu(low_rid) if clouds.is_visible_in_tree() else 0.0)
		bands[band][3] = float(f.state.get("vertical_speed", 0.0))
	var keys := bands.keys()
	keys.sort()
	for band in keys:
		var b: Array = bands[band]
		print("ASCENT %5d-%5d m  frames %4d  frame %6.2f ms (%5.1f fps)  gpu main %6.2f  cloud pass %6.2f  climb %4.0f m/s" % [band, band + 500, b[0].size(), _median(b[0]), 1000.0 / maxf(_median(b[0]), 0.001), _median(b[1]), _median(b[2]), b[3]])
	quit(0)
