extends SceneTree
## Requires a graphical display. Run tools/run.sh --script tests/test_rendering.gd.
## Captures go to /tmp/aphelion-render-regression (or the OS temp directory).
const World = preload("res://scripts/world_view.gd")
const RADIUS := 600000.0
var world: Node3D
var failures: Array[String] = []
var output_dir := ""

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendering regression needs a graphical display, not --headless.")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	output_dir = OS.get_environment("TMPDIR")
	if output_dir.is_empty():
		output_dir = OS.get_environment("TEMP") if OS.has_feature("windows") else "/tmp"
	output_dir = output_dir.path_join("aphelion-render-regression")
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	# Hide the animated craft for comparisons, so thrust cannot hide a terrain jump.
	world._rocket.hide()
	world._pitch = 0.85
	await _check_pair("reported_altitude", Vector3(0,3700,0), Vector3(0,3700.25,0), 0.004)
	await _check_pair("ascent_6km", Vector3(0,5999,0), Vector3(0,6001,0), 0.012)
	await _check_pair("descent_6km", Vector3(0,6001,0), Vector3(0,5999,0), 0.012)
	var boundary := sqrt(6000.0*6000.0-1000.0*1000.0)
	await _check_pair("lateral_6km", Vector3(boundary-1,1000,0), Vector3(boundary+1,1000,0), 0.012)
	# Capture the horizon and terrain at different heights and camera pitches.
	for altitude: float in [0.0, 1000.0, 3700.0, 6000.0, 12000.0, 18000.0, 40000.0, 100000.0]:
		for pitch: float in [-0.4, 0.22, 1.2]:
			world._pitch = pitch
			var capture: Image = await _capture(Vector3(0,altitude,0))
			capture.save_png(output_dir.path_join("surface-%06d-pitch-%+.2f.png" % [altitude,pitch]))
	# Close camera poses must still show the four-tank rocket and recovery capsule.
	world._rocket.show()
	world.set_design({"tanks":4,"engine":"titan","boosters":true,"fins":true})
	for distance: float in [8.0,25.0,130.0]:
		world._distance = distance
		world._pitch = 1.2
		var capture: Image = await _capture(Vector3(0,3700,0))
		capture.save_png(output_dir.path_join("craft-zoom-%03d.png" % distance))
	world._distance = 25
	world._pitch = 0.22
	var far_side: Image = await _capture(Vector3(0,-2.0*RADIUS-40000.0,0))
	far_side.save_png(output_dir.path_join("opposite-hemisphere.png"))
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: four rendered terrain-continuity comparisons; 28 camera/altitude captures at " + output_dir)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _capture(position: Vector3) -> Image:
	var altitude := (position + Vector3(0,RADIUS,0)).length() - RADIUS
	world.sync_flight({"position":position,"altitude":altitude,"orientation":Basis.IDENTITY,"engine_on":false,"fuel":0.0,"boosters_attached":true,"capsule_only":false,"chute_deployed":false},0)
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _check_pair(name: String, first_position: Vector3, second_position: Vector3, tolerance: float) -> void:
	var first: Image = await _capture(first_position)
	var second: Image = await _capture(second_position)
	first.save_png(output_dir.path_join(name+"-before.png"))
	second.save_png(output_dir.path_join(name+"-after.png"))
	var difference := 0.0
	var samples := 0
	for y in range(0,first.get_height(),8):
		for x in range(0,first.get_width(),8):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			difference += (absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))/3.0
			samples += 1
	difference /= maxf(1,samples)
	print("%s mean RGB change: %.6f (limit %.3f)" % [name,difference,tolerance])
	if difference > tolerance:
		failures.append("Visible terrain discontinuity in %s: %.6f > %.3f" % [name,difference,tolerance])
