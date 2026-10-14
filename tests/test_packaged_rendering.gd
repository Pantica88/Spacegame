extends SceneTree
## Exercise the resources in a SHIPPING executable, not the working project.
## Since Godot 4.6, export templates refuse --script and --main-pack unless built
## with disable_path_overrides=no, so shipped builds stay locked down. Run the
## exported .pck through the test-only template instead (docs/FOUNDATION_REVIEW.md, entry 1):
## APHELION_RENDER_DIR=/tmp/packaged XDG_DATA_HOME=/tmp/aphelion-render-profile \
##   ~/godot-double/src-4.7/bin/godot.linuxbsd.template_debug.double.x86_64.testing \
##   --main-pack build/<version>/linux/APHELION.pck --audio-driver Dummy --script /absolute/path/to/this.gd
## Launch outside the project directory. Screenshots contain the full game UI.

var game: Node
var output_dir := ""
var failures: Array[String] = []

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Packaged rendering checks require a graphical display.")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	output_dir = OS.get_environment("APHELION_RENDER_DIR")
	if output_dir.is_empty():
		output_dir = "/tmp/aphelion-packaged-rendering"
	DirAccess.make_dir_recursive_absolute(output_dir)
	print("PACKAGED executable: " + OS.get_executable_path())
	print("PACKAGED version: " + str(ProjectSettings.get_setting("application/config/version", "unversioned")))
	print("PACKAGED resource root: " + ProjectSettings.globalize_path("res://"))
	# Resolve every game resource at runtime through this executable's mounted PCK.
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.enabled = false
	game.design = {"name": "Pioneer 01", "tanks": 2, "engine": "sparrow", "boosters": true, "fins": true}
	game._refresh_design(false)
	await game._roll_out()
	game._stage()
	game.toast_label.hide()
	await _save_capture("full-launchpad.png")
	# Use the shipped integrator and the normal full-throttle/SAS controls. Only
	# the waits between rendered frames are accelerated; positions aren't scripted.
	for target: float in [3700.0, 5590.0, 5990.0, 6010.0, 8000.0, 12000.0, 18000.0, 30000.0]:
		var steps := 0
		while float(game.flight.state.altitude) < target and steps < 18000:
			game.flight.step(1.0 / 60.0, {"throttle": 1.0, "sas": true, "pitch": 0.0, "yaw": 0.0, "roll": 0.0})
			steps += 1
			if game.flight.state.status != "flying" or (float(game.flight.state.vertical_speed) < 0.0 and float(game.flight.state.time) > 10.0):
				break
		var state: Dictionary = game.flight.telemetry()
		if float(state.altitude) < target:
			failures.append("Shipped flight simulation did not reach %.0f m (stopped at %.1f m)." % [target, state.altitude])
			break
		game.world.sync_flight(state, 0.0)
		game._update_flight_ui()
		print("ASCENT target=%.0f m altitude=%.3f m time=%.3f s speed=%.3f m/s" % [target, state.altitude, state.time, state.speed])
		await _save_capture("full-ascent-%05d.png" % int(target))
	# Keep the same shipped world/camera, hide moving overlays, and compare nearby
	# exact positions. This catches the old 6 km surface swap independently of UI.
	game.ui.hide()
	game.world._pitch = 1.35
	await _terrain_at(48560.0, "high-altitude-48560.png")
	await _terrain_at(100000.0, "high-altitude-100000.png")
	game.ui.hide()
	game.world._rocket.hide()
	for pitch: float in [0.22, 0.85]:
		game.world._pitch = pitch
		await _check_pair("terrain-5990-6010-pitch-%.2f" % pitch, 5990.0, 6010.0, 0.02)
		await _check_pair("terrain-6001-5999-pitch-%.2f" % pitch, 6001.0, 5999.0, 0.012)
	game.sound.shutdown()
	game.queue_free()
	for frame in range(3):
		await process_frame
	if failures.is_empty():
		print("PASS: packaged full-game ascent and four terrain continuity comparisons. Captures: " + output_dir)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _save_capture(filename: String) -> Image:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var result := capture.save_png(output_dir.path_join(filename))
	if result != OK:
		failures.append("Could not save " + filename)
	return capture

func _terrain_at(altitude: float, filename: String) -> Image:
	var state: Dictionary = game.flight.telemetry()
	state.position = Vector3(0.0, altitude, 0.0)
	state.altitude = altitude
	state.engine_on = false
	game.world.sync_flight(state, 0.0)
	return await _save_capture(filename)

func _check_pair(label: String, before: float, after: float, tolerance: float) -> void:
	var first := await _terrain_at(before, label + "-before.png")
	var second := await _terrain_at(after, label + "-after.png")
	var difference := 0.0
	var samples := 0
	for y in range(0, first.get_height(), 4):
		for x in range(0, first.get_width(), 4):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			difference += (absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b)) / 3.0
			samples += 1
	difference /= maxf(samples, 1.0)
	print("%s mean RGB change: %.6f (limit %.3f)" % [label, difference, tolerance])
	if difference > tolerance:
		failures.append("Visible terrain discontinuity in %s: %.6f > %.3f" % [label, difference, tolerance])
