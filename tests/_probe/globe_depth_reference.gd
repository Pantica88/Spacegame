extends "res://tests/test_atmosphere.gd"
## Why test_clouds' 1600 km "high-precision depth reference" check fails:
## separates frame-to-frame cloud noise from the near-plane change it targets.
## tools/run.sh --script res://tests/_probe/globe_depth_reference.gd

func _run() -> void:
	output_dir = "/tmp/aphelion-globe-depth"
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	var layer = world._clouds
	var noise: NoiseTexture3D = layer.material_override.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty():
		await noise.changed
	for setup in [["default", 1.0, true], ["frozen_time", 0.0, true], ["no_temporal", 1.0, false], ["frozen_no_temporal", 0.0, false]]:
		layer.time_scale = setup[1]
		layer.temporal = setup[2]
		_pose(Vector3(0, 1600000, 0))
		world._landscape.hide()
		world.camera.position = Vector3.ZERO
		world.camera.look_at(world._planet.position, Vector3.FORWARD)
		world.set_sun_direction(Vector3.UP)
		for frame in range(30): await process_frame
		var a := await capture(setup[0] + "-a")
		var b := await capture(setup[0] + "-b")
		var near: float = world.camera.near
		var margin: float = layer.extra_cull_margin
		world.camera.near = 1000.0
		layer.extra_cull_margin = 2000.0
		var c := await capture(setup[0] + "-near")
		world.camera.near = near
		layer.extra_cull_margin = margin
		# Settled: same frames-since-change as the original check, then 30 more.
		for frame in range(30): await process_frame
		var d := await capture(setup[0] + "-settled")
		world.camera.near = 1000.0
		layer.extra_cull_margin = 2000.0
		for frame in range(30): await process_frame
		var e := await capture(setup[0] + "-near-settled")
		world.camera.near = near
		layer.extra_cull_margin = margin
		print("GLOBE %s repeat=%.6f near_3f=%.6f settled_repeat=%.6f near_settled=%.6f" % [
			setup[0], difference(a, b), difference(b, c), difference(b, d), difference(d, e)])
	# test_clouds' order: a 100 km view, then a jump to 1600 km and captures
	# three frames apart. Control repeats the capture without the near change.
	layer.time_scale = 1.0
	layer.temporal = true
	for variant in ["control", "near", "hidden_control", "hidden_near"]:
		_pose(Vector3(0, 100000, 0))
		world._landscape.hide()
		world.camera.position = Vector3.ZERO
		world.camera.look_at(world._planet.position, Vector3.FORWARD)
		for frame in range(30): await process_frame
		# test_clouds hides the clouds for its orbit-clear capture and never
		# shows them again before the globe.
		if variant.begins_with("hidden"):
			layer.hide()
			await capture("jump-%s-orbit-clear" % variant)
		_pose(Vector3(0, 1600000, 0))
		world._landscape.hide()
		world.camera.position = Vector3.ZERO
		world.camera.look_at(world._planet.position, Vector3.FORWARD)
		var first := await capture("jump-%s-3f" % variant)
		var near: float = world.camera.near
		var margin: float = layer.extra_cull_margin
		if variant.ends_with("near"):
			world.camera.near = 1000.0
			layer.extra_cull_margin = 2000.0
		var second := await capture("jump-%s-6f" % variant)
		world.camera.near = near
		layer.extra_cull_margin = margin
		for frame in range(30): await process_frame
		var settled := await capture("jump-%s-settled" % variant)
		print("JUMP %s visible=%s" % [variant, layer.visible])
		print("JUMP %s 3f_vs_6f=%.6f 3f_vs_settled=%.6f 6f_vs_settled=%.6f" % [
			variant, difference(first, second), difference(first, settled), difference(second, settled)])
		layer.show()
	world.free()
	quit(0)
