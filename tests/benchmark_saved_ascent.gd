extends SceneTree
## Flies the saved craft straight up at 1x; use isolated XDG_DATA_HOME.
## Run with --profile-gpu. ASCENT_COMPARE=1 cycles rendering ablations.
## ASCENT_OUTPUT sets the capture/report directory; ASCENT_LIMIT defaults to 40 km.
## ASCENT_MODES=normal,no_wake isolates the wake while preserving hull heating.
const CloudPass = preload("res://scripts/cloud_render_pass.gd")
const MODES := ["normal", "no_heat", "no_clouds", "no_hud"]
const MODE_FRAMES := 18
const SETTLE_FRAMES := 5
var main: Node
var comparing := OS.get_environment("ASCENT_COMPARE") == "1"
var modes: PackedStringArray = OS.get_environment("ASCENT_MODES").split(",", false) if not OS.get_environment("ASCENT_MODES").is_empty() else PackedStringArray(MODES)
var mode := "normal"
var samples := {}
var output := OS.get_environment("ASCENT_OUTPUT")
var started := false

func _initialize() -> void: _run.call_deferred()

func _apply_ablation() -> void:
	if not started or not comparing: return
	var world = main.world
	if world._heat_material != null:
		for mesh in world._heated_meshes:
			if is_instance_valid(mesh): mesh.material_overlay = null if mode == "no_heat" else world._heat_material
	if is_instance_valid(world._heat_trail):
		# Restore visibility explicitly: drawing can outpace physics updates.
		var wake = world._heat_trail
		var active: bool = float(wake._material.get_shader_parameter("strength")) > 0.005 and wake.flow_direction.length_squared() > 0.5
		wake.visible = mode not in ["no_heat", "no_wake"] and active and not world._heated_meshes.is_empty()
	world._clouds.visible = mode != "no_clouds"
	main.ui.visible = mode != "no_hud"

func _passes() -> Dictionary:
	var rd := RenderingServer.get_rendering_device()
	var values := {}
	if rd == null: return values
	var count := rd.get_captured_timestamps_count()
	for i in range(count - 1):
		# Main view renders last; retain its last occurrence of each pass.
		var name := rd.get_captured_timestamp_name(i)
		var milliseconds := (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1e6
		# Multiple CanvasLayers draw separately; the last may be an empty overlay.
		values[name] = float(values.get(name, 0.0)) + milliseconds if name == "Render CanvasItems" else milliseconds
	if count > 1:
		values["total"] = (rd.get_captured_timestamp_gpu_time(count - 1) - rd.get_captured_timestamp_gpu_time(0)) / 1e6
	return values

func _median(values: Array) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]

func _record(band: int, values: Dictionary) -> void:
	var key := "%d|%s" % [band, mode]
	if not samples.has(key): samples[key] = {}
	for field in values:
		if not samples[key].has(field): samples[key][field] = []
		samples[key][field].append(values[field])

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Saved-ascent benchmark requires graphical rendering")
		quit(1)
		return
	if output.is_empty(): output = "/tmp/aphelion-saved-ascent"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1008)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.gui_disable_input = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process_input(false)
	main.set_process_unhandled_input(false)
	main.set_process_shortcut_input(false)
	await main._roll_out()
	var flight = main.flight
	var world = main.world
	main.sas = true
	main._set_throttle(1.0)
	main._stage()
	assert(main.warp == 1.0, "Benchmark flies at normal time")
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	RenderingServer.frame_pre_draw.connect(_apply_ablation)
	started = true
	print("ASCENT engine=%s viewport=%s parts=%d stages=%d compare=%s" % [Engine.get_version_info().string, root.size, main.design.assembly.parts.size(), main.design.assembly.stages.size(), comparing])
	var limit := float(OS.get_environment("ASCENT_LIMIT")) if not OS.get_environment("ASCENT_LIMIT").is_empty() else 40000.0
	var start := Time.get_ticks_usec()
	var last := start
	var next_report := 5.0
	var zero_thrust_since := -1.0
	var frame := 0
	var skip_until := 15
	var captures := [6000.0, 12000.0, 20000.0, 30000.0]
	while float(flight.state.altitude) < limit:
		mode = modes[(frame / MODE_FRAMES) % modes.size()] if comparing else "normal"
		await process_frame
		frame += 1
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		last = now
		var elapsed := float(now - start) / 1e6
		var altitude: float = flight.state.altitude
		var p := _passes()
		if frame > skip_until and (not comparing or frame % MODE_FRAMES >= SETTLE_FRAMES):
			_record(int(altitude / 2000.0) * 2, {"frame_ms": frame_ms,
				"gpu_total_ms": p.get("total", 0.0), "gpu_main_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport),
				"gpu_cloud_ms": maxf(CloudPass.captured_gpu_ms(), 0.0) if world._clouds.is_drawing() else 0.0,
				"transparent_ms": p.get("Render 3D Transparent Pass", 0.0), "opaque_ms": p.get("Render Opaque Pass", 0.0),
				"canvas_ms": p.get("Render CanvasItems", 0.0), "depth_ms": p.get("Render Depth Pre-Pass", 0.0),
				"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu()})
		if not comparing and not captures.is_empty() and altitude >= captures[0]:
			var target: float = captures.pop_front()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/ascent-%dkm.png" % [output, int(target / 1000.0)])
			skip_until = frame + 8
		if elapsed >= next_report:
			next_report += 5.0
			print("ASCENT t=%.1f alt=%.0f speed=%.0f heat=%.2f heating=%.1f stage=%s mode=%s" % [elapsed, altitude, flight.state.speed, flight.state.heat_glow, flight.state.heating_rate, flight.state.stage_index, mode])
		if float(flight.state.thrust) <= 0.0 and float(flight.state.vertical_speed) > 0.0 and not bool(flight.state.capsule_only):
			if zero_thrust_since < 0.0: zero_thrust_since = elapsed
			elif elapsed - zero_thrust_since > 0.5:
				main._stage()
				print("ASCENT stage=%s alt=%.0f" % [flight.state.stage_index, altitude])
				zero_thrust_since = -1.0
		else: zero_thrust_since = -1.0
		if flight.state.status in ["crashed", "landed"] or elapsed > 240.0:
			push_error("Ascent ended before target: %s at %.0f m" % [flight.state.status, altitude])
			break
	started = false
	RenderingServer.frame_pre_draw.disconnect(_apply_ablation)
	var rows := []
	for key in samples:
		var row := {"band_km": int(key.get_slice("|", 0)), "mode": key.get_slice("|", 1), "n": samples[key].frame_ms.size()}
		for field in samples[key]: row[field] = _median(samples[key][field])
		var times: Array = samples[key].frame_ms.duplicate()
		times.sort()
		row["frame_p95_ms"] = times[mini(times.size() - 1, int(times.size() * 0.95))]
		rows.append(row)
		print("BAND " + JSON.stringify(row))
	var report := {"engine": Engine.get_version_info().string, "resolution": str(root.size), "parts": main.design.assembly.parts.size(), "target_reached": float(flight.state.altitude) >= limit, "rows": rows}
	var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ASCENT DONE " + output + "/results.json")
	quit(0 if report.target_reached else 1)
