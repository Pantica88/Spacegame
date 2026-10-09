extends "res://tests/test_atmosphere.gd"
## Render all four cloud families and their blend from below and orbit.
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")

func _run() -> void:
	output_dir = "/tmp/aphelion-authored-clouds"
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	var weather := Weather.new()
	Surface.home().definition.cloud_weather = weather
	var noise: NoiseTexture3D = world._clouds.material_override.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty():
		await noise.changed
	var labels := ["cumulus", "stratocumulus", "stratus", "storm", "mixed", "clear"]
	var weights := [Color(1, 0, 0, 0), Color(0, 1, 0, 0), Color(0, 0, 1, 0), Color(0, 0, 0, 1), Color(0.4, 0.2, 0.1, 0.3), Color(0, 0, 0, 0)]
	for orbit in [false, true]:
		_pose(Vector3(0, 100000 if orbit else 30, 0))
		world._landscape.hide()
		world.camera.position = Vector3.ZERO if orbit else Vector3(0, 10, 0)
		world.camera.look_at(world._planet.position if orbit else Vector3(0, 400, -1000), Vector3.FORWARD if orbit else Vector3.UP)
		world.set_sun_direction(Vector3.UP if orbit else Vector3(0, 0.8, -0.6))
		var previous: Image
		var mixed: Image
		for index in range(weights.size()):
			var map := Image.create(512, 256, false, Image.FORMAT_RGBA8)
			map.fill(weights[index])
			weather.restore(map)
			world._update_atmosphere()
			var frame := await capture(("orbit-" if orbit else "ground-") + labels[index])
			if previous != null:
				var delta := difference(previous, frame)
				print("Category delta %s: %.6f" % [labels[index], delta])
				check(delta > 0.003, "Each authored cloud family has a distinct rendered profile: " + labels[index])
			if labels[index] == "mixed": mixed = frame
			if labels[index] == "clear": check(difference(mixed, frame) > 0.01, "Mixed formations remain visible against clear sky")
			previous = frame
	var mixed_map := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	mixed_map.fill(Color(0.4, 0.2, 0.1, 0.3))
	weather.restore(mixed_map)
	world._update_atmosphere()
	var material: ShaderMaterial = world._clouds.material_override
	var thickness: float = material.get_shader_parameter("cloud_thickness_km")
	var middle: float = material.get_shader_parameter("cloud_height_km")
	var deck_fraction: float = material.get_shader_parameter("cloud_deck_fraction")
	var bottom := (middle - thickness * 0.5) * 1000.0
	for boundary in [bottom, bottom + thickness * deck_fraction * 1000.0, bottom + thickness * 1000.0]:
		var before: Image
		for offset in [-1.0, 1.0]:
			_pose(Vector3(0, boundary + offset, 0))
			world._landscape.hide()
			world.camera.position = Vector3.ZERO
			world.camera.look_at(Vector3(0, 400, -1000), Vector3.UP)
			world.set_sun_direction(Vector3.UP)
			var frame := await capture("crossing-%.0f-%+.0f" % [boundary, offset])
			if before != null:
				var delta := difference(before, frame)
				print("Authored boundary %.0f m difference: %.6f" % [boundary, delta])
				check(delta < 0.015, "Flying through the blended cloud volume stays continuous")
			before = frame
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: distinct cloud families, blended volumes from ground/orbit, and continuous volume crossings. Captures: " + output_dir)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
