extends "res://tests/test_atmosphere.gd"
const PlanetSurface = preload("res://scripts/planet_surface.gd")
## Graphical cloud regression and optional uncapped frame-time comparison.
## tools/run.sh --disable-vsync --script res://tests/test_clouds.gd

func _run() -> void:
	output_dir = "/tmp/aphelion-clouds"
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	_pose(Vector3(0, 30, 0))
	world._landscape.hide()
	world.camera.position = Vector3(0, 10, 0)
	world.camera.look_at(Vector3(0, 700, -1000), Vector3.UP)
	world.set_sun_direction(Vector3(0, 0.8, -0.6))
	var noise: NoiseTexture3D = world._clouds.material_override.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty():
		await noise.changed
	var day := await capture("ground-day")
	world._clouds.hide()
	var clear := await capture("ground-clear")
	var cloud_difference := difference(day, clear)
	print("Cloud/clear mean RGB difference: %.6f" % cloud_difference)
	check(cloud_difference > 0.003, "Clouds are visible from below")
	var clear_ms := await frame_time()
	world._clouds.show()
	var cloudy_ms := await frame_time()
	print("Median frame time, clear/cloudy: %.3f / %.3f ms (delta %.3f ms)" % [clear_ms, cloudy_ms, cloudy_ms-clear_ms])
	world.set_sun_direction(Vector3(0, 0.025, -1))
	var sunset := await capture("ground-sunset")
	check(warmth(sunset) > warmth(day) + 0.025, "Clouds and haze warm together at sunset")
	world.set_sun_direction(Vector3.DOWN)
	var night := await capture("ground-night")
	check(brightness(night) < brightness(day) * 0.35, "Clouds lose direct illumination at night")
	_pose(Vector3(0, 100000, 0))
	world._landscape.hide()
	world.camera.position = Vector3.ZERO
	world.camera.look_at(world._planet.position, Vector3.FORWARD)
	world.set_sun_direction(Vector3.UP)
	var orbit := await capture("orbit-cloudy")
	world._clouds.hide()
	var orbit_clear := await capture("orbit-clear")
	check(difference(orbit, orbit_clear) > 0.003, "Clouds are visible over the surface from above")
	_pose(Vector3(0, 1600000, 0))
	world._landscape.hide()
	world.camera.position = Vector3.ZERO
	world.camera.look_at(world._planet.position, Vector3.FORWARD)
	world.set_sun_direction(Vector3.UP)
	# Below the full-resolution band, the jump from orbit restarts temporal
	# reconstruction. Far above the clouds each pixel is refreshed every fourth
	# frame and keeps 70% history, so detail sharpens with a time constant of
	# about 13 frames. Captures 3 or 30 frames after a change measured that
	# convergence (0.007 and 0.0012), not depth precision.
	for frame in range(120): await process_frame
	var globe := await capture("globe-day")
	var flight_near: float = world.camera.near
	var cloud_cull_margin: float = world._clouds.extra_cull_margin
	world.camera.near = 1000.0
	# Keep the camera-anchored screen triangle inside the enlarged near plane;
	# otherwise CPU frustum culling hides this supposed depth reference entirely.
	world._clouds.extra_cull_margin = 2000.0
	for frame in range(120): await process_frame
	var precise_globe := await capture("globe-depth-reference")
	var depth_difference := difference(globe, precise_globe)
	print("Globe/depth-reference mean RGB difference: %.6f" % depth_difference)
	check(depth_difference < 0.003, "Distant clouds match a high-precision depth reference")
	world.camera.near = flight_near
	world._clouds.extra_cull_margin = cloud_cull_margin
	world.set_sun_direction(Vector3(1, -0.18, 0))
	await capture("globe-sunset")
	var height: float = world._clouds.material_override.get_shader_parameter("cloud_height_km") * 1000.0
	_pose(Vector3(0, height - 1.0, 0))
	world._landscape.hide()
	world.camera.position = Vector3.ZERO
	world.camera.look_at(Vector3(0, 400, -1000), Vector3.UP)
	world.set_sun_direction(Vector3.UP)
	var below := await capture("crossing-below")
	_pose(Vector3(0, height + 1.0, 0))
	world._landscape.hide()
	world.camera.position = Vector3.ZERO
	world.camera.look_at(Vector3(0, 400, -1000), Vector3.UP)
	world.set_sun_direction(Vector3.UP)
	var above := await capture("crossing-above")
	check(difference(below, above) < 0.015, "Crossing the shell does not flash or pop")
	var airless: Resource = PlanetSurface.home().definition.duplicate()
	airless.atmosphere_height = 0.0
	world._clouds.update_weather(airless, Vector3.UP * 601.0, Vector3.UP, true)
	check(not world._clouds.visible, "Airless planets have no clouds")
	airless.atmosphere_height = 17500.0
	airless.atmosphere_visual_density = 0.0
	world._clouds.update_weather(airless, Vector3.UP * 601.0, Vector3.UP, true)
	check(not world._clouds.visible, "Zero-density atmospheres have no clouds")
	world.set_mode("workshop")
	check(not world._clouds.visible, "Workshop hides clouds")
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: clouds below/above, sunset, night, shell crossing, airless/workshop. Captures: " + output_dir)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func frame_time() -> float:
	for frame in range(10): await process_frame
	var samples: Array[float] = []
	for frame in range(45):
		var start := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - start) * 0.001)
	samples.sort()
	return samples[samples.size() / 2]
